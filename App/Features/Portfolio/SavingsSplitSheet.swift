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
    /// Maaş tetikli birikim planı varsa (specs/10 §7) sayfa planla dolu açılır.
    @State private var plan: SavingsPlanRule?
    @State private var usesPlan = false

    /// Alım fiyatın kuyumcunun/bankanın satış fiyatıdır.
    private var unitPrice: Decimal? { board.quote(asset)?.price(.ask) }
    private var budget: Decimal { SavingsSplit.amount(of: income, percent: percent) }
    private var quantity: Decimal {
        if usesPlan, let plan, let unitPrice {
            return plan.quantity(at: unitPrice) ?? 0
        }
        return unitPrice.map { SavingsSplit.quantity(for: budget, unitPrice: $0, wholeUnits: asset.unit == .piece) } ?? 0
    }

    private var assetChoices: [AssetCode] {
        guard let asset = plan?.asset, !Self.assets.contains(asset) else { return Self.assets }
        return Self.assets + [asset]
    }

    private var planText: String? {
        guard let plan else { return nil }
        switch plan.target {
        case let .quantity(value):
            return "\(plan.asset.formatQuantity(value, locale: locale)) \(plan.asset.unitLabel) \(plan.asset.displayName())"
        case let .amount(value):
            return "\(Money(value, .TRY).formatted(locale: locale, fractionDigits: 0)) · \(plan.asset.displayName())"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let planText {
                    Section {
                        Toggle(isOn: $usesPlan) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Birikim planına göre")
                                Text(verbatim: planText).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: usesPlan) { _, on in
                            if on, let plan {
                                asset = plan.asset
                                goalID = plan.goalID
                            }
                        }
                    }
                }
                Section {
                    Picker("Oran", selection: $percent) {
                        ForEach(Self.percents, id: \.self) { value in
                            Text(verbatim: (value / 100).formattedPercent(locale: locale, fractionDigits: 0)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(usesPlan)
                    Picker("Varlık", selection: $asset) {
                        ForEach(assetChoices, id: \.self) { Text(verbatim: $0.displayName()).tag($0) }
                    }
                    if !goals.isEmpty {
                        Picker("Hedef", selection: $goalID) {
                            Text("Yok").tag(UUID?.none)
                            ForEach(goals) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    }
                } header: {
                    Text("\(Money(income, .TRY).formatted(locale: locale, fractionDigits: 0)) gelir kaydedildi. Bir kısmını birikime ayırmak ister misin?")
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
            .task {
                if plan == nil, let rule = (try? PlanStore(context: context).salaryPlans())?.first?.rule {
                    plan = rule
                    usesPlan = true
                    asset = rule.asset
                    goalID = rule.goalID
                }
                await board.refresh(including: Set(Self.assets).union(plan.map { [$0.asset] } ?? []))
            }
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
                               note: usesPlan ? String(localized: "Birikim planı") : String(localized: "Gelirden birikime")),
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
