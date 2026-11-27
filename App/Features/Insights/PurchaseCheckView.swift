import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// "Alabilir miyim?" (REQ-I3, specs/10 §3). Kayıt oluşturmaz; sonucu söyler, tavsiye vermez (C6).
struct PurchaseCheckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(PriceBoard.self) private var board
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var editor: PrefillBox?
    @FocusState private var amountFocused: Bool

    private var amount: Decimal? {
        AmountParser(locale: locale).parse(amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var account: LedgerAccount? { accounts.first { $0.id == accountID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tutar", text: $amountText, prompt: Text(verbatim: "12.000"))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .focused($amountFocused)
                        .accessibilityIdentifier("purchase.amount")
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Ödeme", selection: $accountID) {
                        Text("Nakit ya da banka").tag(UUID?.none)
                        ForEach(accounts.filter { $0.kind == .card }) { card in
                            Text(verbatim: card.name).tag(Optional(card.id))
                        }
                    }
                } footer: {
                    Text("Hiçbir kayıt oluşmaz; yalnız bu alımın bütçene ve hedeflerine etkisi hesaplanır.")
                }

                if let amount {
                    results(amount)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Alabilir miyim?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear { amountFocused = true }
            .sheet(item: $editor) { box in
                TransactionEditor(mode: .create(.expense), prefill: box.prefill)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private func results(_ amount: Decimal) -> some View {
        let store = InsightStore(context: context)
        let purchase = try? store.purchaseContext(now: .now, calendar: calendar)
        let card = account.flatMap { account in
            account.statementDay.map { PurchasePlanner.Card(statementDay: $0, dueDay: account.paymentDueDay) }
        }
        let counts = card == nil ? [1] : [1, 3, 6]
        let scenarios = purchase.map {
            PurchasePlanner.scenarios(amount: amount, counts: counts, context: $0, card: card, calendar: calendar)
        } ?? []

        ForEach(scenarios) { scenario in
            Section {
                ScenarioRows(scenario: scenario, hasBudget: purchase?.hasBudget ?? false)
                Button("İşlem olarak ekle") {
                    editor = PrefillBox(prefill: .init(amount: amount, accountID: accountID, installments: scenario.count))
                }
            } header: {
                if scenario.count == 1 {
                    Text("Peşin")
                } else {
                    Text("\(scenario.count) taksit · ayda \(money(scenario.installment))")
                }
            }
        }

        let prices = buyPrices
        let goals = (try? store.goalsForPurchase(prices: prices, now: .now, calendar: calendar)) ?? []
        if let saving = purchase?.monthlySaving {
            let impacts = goals.compactMap { PurchasePlanner.goalImpact(amount: amount, goal: $0, monthlySaving: saving) }
            if !impacts.isEmpty {
                Section {
                    ForEach(impacts, id: \.name) { impact in
                        LabeledContent {
                            if impact.delay > 0 {
                                Text("\(impact.delay) ay gecikir").foregroundStyle(.orange)
                            } else {
                                Text("Değişmez").foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: impact.name)
                                Text("\(impact.monthsBefore) ay yerine \(impact.monthsAfter) ay")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Hedefler")
                } footer: {
                    Text("Son 3 ayın ortalama birikimine göre (ayda \(money(saving))). Taksitli de olsa toplam tutar aynıdır.")
                }
            }
        } else if !goals.isEmpty {
            Section("Hedefler") {
                Text("Hedeflere etkisi için en az 3 aylık kayıt gerekir.").foregroundStyle(.secondary)
            }
        }
    }

    /// Hedef miktarlarını TL'ye çevirmek için satış (kuyumcunun sattığı) fiyatı.
    private var buyPrices: [AssetCode: Decimal] {
        var result: [AssetCode: Decimal] = [:]
        for goal in (try? GoalStore(context: context).goals()) ?? [] {
            guard case let .quantity(asset, _)? = goal.goal?.target, let quote = board.quote(asset) else { continue }
            result[asset] = quote.price(.ask)
        }
        return result
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }
}

private struct PrefillBox: Identifiable {
    let id = UUID()
    let prefill: TransactionEditor.Prefill
}

private struct ScenarioRows: View {
    let scenario: PurchasePlanner.Scenario
    let hasBudget: Bool
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent(hasBudget ? LocalizedStringKey("Bu ay bütçene") : LocalizedStringKey("Bu ay giderine"),
                       value: money(scenario.thisMonth))
        LabeledContent {
            if scenario.remainingAfter < 0 {
                Text("\(money(scenario.shortfall)) açık").foregroundStyle(.red)
            } else {
                Text(verbatim: money(scenario.remainingAfter))
            }
        } label: {
            Text(hasBudget ? LocalizedStringKey("Bütçeden kalan") : LocalizedStringKey("Ay sonunda kalan"))
        }
        LabeledContent {
            Text(verbatim: "\(money(scenario.perDayBefore)) → \(money(scenario.perDayAfter))")
                .foregroundStyle(scenario.perDayAfter < scenario.perDayBefore ? Color.orange : Color.primary)
        } label: {
            Text("Günlük harcayabileceğin")
        }
        if let due = scenario.firstDue {
            LabeledContent("İlk ödeme", value: due.formatted(.dateTime.day().month(.wide)))
        }
        if scenario.schedule.count > 1 {
            DisclosureGroup("Aylara dağılım") {
                ForEach(scenario.schedule, id: \.month) { share in
                    LabeledContent(share.month.title(calendar: calendar), value: money(share.amount))
                }
            }
        }
        if scenario.exceedsLimit {
            Label("Kart limiti bu tutara yetmiyor", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }
}
