import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// "Maaş geldi → bir kısmını birikime ayır" (REQ-P10, specs/09 §6). Gelir kaydedilince bir kez
/// sorulur; alım kullanıcı "Alımı kaydet"e basınca oluşur (C5). "Bir daha sorma" ile kapanır.
struct SavingsSplitSheet: View {
    static let promptKey = "savings.splitPrompt"
    private static let assets: [AssetCode] = [.gold(.gram24), .gold(.quarter), .fx(.USD), .fx(.EUR)]
    private static let percents: [Decimal] = [10, 15, 20, 25]

    let income: Decimal

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]
    @AppStorage(promptKey) private var offersSplit = true
    @State private var percent: Decimal = 10
    @State private var asset: AssetCode = .gold(.gram24)
    @State private var goalID: UUID?
    @State private var saveFailed = false

    /// Alım fiyatın kuyumcunun/bankanın satış fiyatıdır.
    private var unitPrice: Decimal? { board.quote(asset)?.price(.ask) }
    private var budget: Decimal { SavingsSplit.amount(of: income, percent: percent) }
    private var quantity: Decimal {
        unitPrice.map { SavingsSplit.quantity(for: budget, unitPrice: $0, wholeUnits: asset.unit == .piece) } ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Oran", selection: $percent) {
                        ForEach(Self.percents, id: \.self) { value in
                            Text(verbatim: (value / 100).formattedPercent(locale: locale, fractionDigits: 0)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Varlık", selection: $asset) {
                        ForEach(Self.assets, id: \.self) { Text(verbatim: $0.displayName()).tag($0) }
                    }
                    if !goals.isEmpty {
                        Picker("Hedef", selection: $goalID) {
                            Text("Yok").tag(UUID?.none)
                            ForEach(goals) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    }
                } header: {
                    Text("\(Money(income, .TRY).formatted(locale: locale, fractionDigits: 0)) gelir kaydedildi. Bir kısmını birikime ayıralım mı?")
                        .textCase(nil)
                } footer: {
                    summary
                }

                Section {
                    Toggle("Gelir kaydedince bunu sor", isOn: $offersSplit)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Birikime ayır")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Şimdi değil") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Alımı kaydet", action: save)
                        .primaryActionStyle()
                        .disabled(quantity <= 0)
                }
            }
            .alert("Alım kaydedilemedi", isPresented: $saveFailed) { Button("Tamam") {} }
            .task { await board.refresh(including: Set(Self.assets)) }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let unitPrice {
            if quantity > 0 {
                let cost = Money(quantity * unitPrice, .TRY).formatted(locale: locale, fractionDigits: 0)
                Text("\(asset.formatQuantity(quantity, locale: locale)) \(asset.unitLabel) \(asset.displayName()) · \(cost). Fiyat \(asset.formatPrice(unitPrice, locale: locale)) ₺, kuyumcunun ya da bankanın fiyatı farklıysa alımdan sonra düzeltebilirsin.")
            } else {
                Text("\(Money(budget, .TRY).formatted(locale: locale, fractionDigits: 0)) bir adet \(asset.displayName()) almaya yetmiyor; oranı artır ya da başka varlık seç.")
            }
        } else {
            Text("Fiyat yükleniyor…")
        }
    }

    private func save() {
        guard let unitPrice, quantity > 0 else { return }
        Task {
            let usdTRY = await board.usdTRY(on: .now)
            do {
                let record = try PortfolioStore(context: context).save(
                    TradeDraft(asset: asset, side: .buy, quantity: quantity, unitPrice: unitPrice, date: .now,
                               note: String(localized: "Gelirden birikime")),
                    usdTRYAtTrade: usdTRY)
                if let goalID {
                    record.goalID = goalID
                    try context.save()
                }
                await board.refresh(including: [asset])
                dismiss()
            } catch {
                saveFailed = true
            }
        }
    }
}
