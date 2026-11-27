import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Alım/satım formu (REQ-P1, P5, P6). Birim fiyat güncel piyasa fiyatıyla ön doldurulur
/// (alışta satış fiyatı, satışta bozdurma fiyatı); kuyumcunun verdiği gerçek fiyat yazılabilir.
struct TradeEditor: View {
    enum Mode {
        case create(AssetCode?)
        case edit(AssetTrade)
    }

    let mode: Mode

    @Environment(PriceBoard.self) private var board
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query private var customAssets: [CustomAsset]

    @State private var asset: AssetCode?
    @State private var side: Trade.Side = .buy
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var feeText = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var priceIsPrefilled = false
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var confirmsDeletion = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case quantity, price, fee }

    private var editing: AssetTrade? {
        if case .edit(let record) = mode { return record }
        return nil
    }

    private var parser: AmountParser { AmountParser(locale: locale) }

    private var draft: TradeDraft {
        TradeDraft(asset: asset, side: side, quantity: parser.parse(quantityText), unitPrice: parser.parse(priceText),
                   fee: feeText.isEmpty ? 0 : (parser.parse(feeText) ?? -1), date: date, note: note)
    }

    private var issues: [TradeDraft.Issue] {
        let existing = asset.flatMap { try? PortfolioStore(context: context).trades(for: $0, excluding: editing?.id) } ?? []
        return draft.issues(existing: existing)
    }

    private func customName(_ asset: AssetCode?) -> String? {
        guard case .custom(let id)? = asset else { return nil }
        return customAssets.first { $0.id.uuidString == id }?.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Yön", selection: $side) {
                        Text("Alış").tag(Trade.Side.buy)
                        Text("Satış").tag(Trade.Side.sell)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    NavigationLink {
                        AssetPicker(selection: $asset)
                    } label: {
                        LabeledContent("Varlık") {
                            if let asset {
                                Label {
                                    Text(verbatim: asset.displayName(customName: customName(asset)))
                                } icon: {
                                    AssetBadge(asset: asset)
                                }
                            } else {
                                Text("Seç")
                            }
                        }
                    }
                }

                Section {
                    field("Miktar", text: $quantityText, suffix: asset?.unitLabel ?? "", focus: .quantity)
                    field("Birim fiyat", text: $priceText, suffix: "₺", focus: .price)
                        .onChange(of: priceText) { _, _ in if focus == .price { priceIsPrefilled = false } }
                    field("İşçilik / komisyon", text: $feeText, suffix: "₺", focus: .fee)
                    if let total = draft.total, issues.isEmpty || issues.allSatisfy({ if case .oversell = $0 { return false }; return true }) {
                        LabeledContent(side == .buy ? "Ödenen" : "Eline geçen") {
                            Text(verbatim: Money(total, .TRY).formatted(locale: locale)).monospacedDigit().fontWeight(.semibold)
                        }
                    }
                } footer: {
                    if priceIsPrefilled, let asset, let quote = board.quote(asset) {
                        Text("\(side == .buy ? Text("Satış") : Text("Bozdurma")) fiyatı · \(RelativeTimeText.text(for: quote.asOf)). Kuyumcunun verdiği fiyatı yazabilirsin.")
                    }
                }

                Section {
                    DatePicker("Tarih", selection: $date, in: ...Date.now)
                    TextField("Not", text: $note, axis: .vertical).lineLimit(1...3)
                }

                let visible = issues.filter { issue in
                    switch issue {
                    case .missingAsset, .missingQuantity, .missingPrice: false
                    default: true
                    }
                }
                if !visible.isEmpty {
                    Section {
                        ForEach(visible, id: \.self) { issue in
                            Label(message(issue), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button("İşlemi sil", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? (side == .buy ? "Alış" : "Satış") : "İşlemi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }
                        .primaryActionStyle()
                        .disabled(!issues.isEmpty || isSaving)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onChange(of: asset) { _, _ in prefillPrice() }
            .onChange(of: side) { _, _ in prefillPrice() }
            .confirmationDialog("Bu işlem silinsin mi?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let editing { try? PortfolioStore(context: context).delete(editing) }
                    dismiss()
                }
            }
            .alert("İşlem kaydedilemedi", isPresented: $saveFailed) {
                Button("Tamam", role: .cancel) {}
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                load()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, suffix: String, focus field: Field) -> some View {
        HStack {
            TextField(title, text: text)
                .monospacedDigit()
                .focused($focus, equals: field)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            if !suffix.isEmpty {
                Text(verbatim: suffix).foregroundStyle(.secondary)
            }
        }
    }

    private func message(_ issue: TradeDraft.Issue) -> LocalizedStringKey {
        switch issue {
        case .missingAsset: "Varlık seç."
        case .missingQuantity: "Miktar gir."
        case .nonPositiveQuantity: "Miktar sıfırdan büyük olmalı."
        case .fractionalPieces: "Bu varlık adetle alınır; küsurat olamaz."
        case .missingPrice: "Birim fiyat gir."
        case .nonPositivePrice: "Fiyat sıfırdan büyük olmalı."
        case .negativeFee: "Ücret geçersiz."
        case .futureDate: "Tarih ileride olamaz."
        case .oversell(let available):
            "Elinde \(asset?.formatQuantity(available, locale: locale) ?? "0") \(asset?.unitLabel ?? "") var; daha fazlası satılamaz."
        }
    }

    private func load() {
        if let editing, let draft = editing.draft {
            asset = draft.asset
            side = draft.side
            quantityText = draft.quantity.map { plain($0) } ?? ""
            priceText = draft.unitPrice.map { plain($0) } ?? ""
            feeText = draft.fee.isZero ? "" : plain(draft.fee)
            date = draft.date
            note = draft.note
        } else if case .create(let preset) = mode {
            asset = preset
            prefillPrice()
            focus = asset == nil ? nil : .quantity
        }
    }

    /// Gruplama ayırıcısı olmadan yerel biçim (düzenlenebilir metin).
    private func plain(_ value: Decimal) -> String {
        var text = value.formattedNumber(locale: locale, fractionDigits: 0...8)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty {
            text = text.replacingOccurrences(of: grouping, with: "")
        }
        return text
    }

    private func prefillPrice() {
        guard editing == nil, priceText.isEmpty || priceIsPrefilled, let asset, let quote = board.quote(asset) else { return }
        priceText = plain(quote.price(side == .buy ? .ask : .bid))
        priceIsPrefilled = true
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        // Reel getiri için işlem günündeki kur: düzenlemede tarih değişmediyse eskisi korunur.
        var usdTRY = editing?.trade?.usdTRYAtTrade
        if usdTRY == nil || editing?.date != date {
            usdTRY = await board.usdTRY(on: date)
        }
        do {
            try PortfolioStore(context: context).save(draft, editing: editing, usdTRYAtTrade: usdTRY)
            await board.refresh(including: asset.map { [$0] } ?? [])
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

/// Varlık seçici (REQ-P2): altın türleri, metaller, döviz, kripto, serbest varlıklar.
struct AssetPicker: View {
    @Binding var selection: AssetCode?
    @Environment(PriceBoard.self) private var board
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \CustomAsset.name) private var customAssets: [CustomAsset]
    @State private var creatingCustom = false

    private static let currencies: [CurrencyCode] = [.USD, .EUR, .GBP, .CHF]
    private static let cryptos = ["bitcoin", "ethereum", "tether", "solana"]

    var body: some View {
        List {
            Section("Altın") { ForEach(GoldKind.allCases, id: \.self) { row(.gold($0)) } }
            Section("Değerli metaller") { ForEach(PreciousMetal.allCases, id: \.self) { row(.metal($0)) } }
            Section("Döviz") { ForEach(Self.currencies, id: \.self) { row(.fx($0)) } }
            Section("Kripto") { ForEach(Self.cryptos, id: \.self) { row(.crypto($0)) } }
            Section {
                ForEach(customAssets) { custom in row(custom.code, name: custom.name) }
                Button("Yeni serbest varlık…", systemImage: "plus") { creatingCustom = true }
            } header: {
                Text("Serbest varlık")
            } footer: {
                Text("Fon, hisse, mevduat gibi fiyatını kendin girdiğin varlıklar.")
            }
        }
        .navigationTitle("Varlık")
        .sheet(isPresented: $creatingCustom) {
            CustomAssetEditor(asset: nil) { created in
                selection = created.code
                dismiss()
            }
        }
    }

    private func row(_ asset: AssetCode, name: String? = nil) -> some View {
        Button {
            selection = asset
            dismiss()
        } label: {
            HStack {
                AssetBadge(asset: asset)
                Text(verbatim: asset.displayName(customName: name))
                Spacer()
                if let quote = board.quote(asset) {
                    Text(verbatim: asset.formatPrice(quote.price(.ask), locale: locale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if asset == selection {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
    }
}

/// Serbest varlık oluşturma ve fiyat güncelleme.
struct CustomAssetEditor: View {
    let asset: CustomAsset?
    var onCreate: ((CustomAsset) -> Void)?

    @Environment(PriceBoard.self) private var board
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var priceText = ""
    @State private var didLoad = false

    init(asset: CustomAsset?, onCreate: ((CustomAsset) -> Void)? = nil) {
        self.asset = asset
        self.onCreate = onCreate
    }

    private var price: Decimal? { AmountParser(locale: locale).parse(priceText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ad", text: $name, prompt: Text("Örn. AFT fonu"))
                HStack {
                    TextField("Güncel birim fiyat", text: $priceText)
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(verbatim: "₺").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(asset == nil ? "Serbest varlık" : "Fiyatı güncelle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .primaryActionStyle()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || price == nil)
                }
            }
            .task {
                guard !didLoad, let asset else { return }
                didLoad = true
                name = asset.name
                if let price = asset.manualPrice {
                    priceText = price.formattedNumber(locale: locale, fractionDigits: 0...8)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 220)
        #endif
    }

    private func save() {
        guard let price else { return }
        let target = asset ?? CustomAsset(name: name)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.manualPrice = price
        target.manualPriceDate = .now
        if asset == nil { context.insert(target) }
        try? context.save()
        board.reloadManualQuotes()
        onCreate?(target)
        dismiss()
    }
}
