import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Birikim planları (REQ-I7, specs/10 §7): Birikim sekmesinde hedeflerin altında.
struct PlansSection: View {
    @Query(sort: \SavingsPlan.createdAt) private var plans: [SavingsPlan]
    @Query private var trades: [AssetTrade]
    @State private var isAdding = false

    var body: some View {
        Section {
            ForEach(plans) { plan in
                NavigationLink {
                    PlanDetailView(plan: plan)
                } label: {
                    PlanRow(plan: plan)
                }
            }
            Button("Plan ekle", systemImage: "plus.circle") { isAdding = true }
        } header: {
            Text("Birikim planları")
        } footer: {
            if plans.isEmpty {
                Text("\"Her ayın 15'inde 2 gram altın\" gibi bir kural koy; gün gelince hatırlatılır, alım o günün fiyatıyla hazır olur.")
            }
        }
        .sheet(isPresented: $isAdding) { PlanEditor(editing: nil) }
    }
}

enum PlanText {
    static func title(_ rule: SavingsPlanRule, locale: Locale) -> String {
        let what: String
        switch rule.target {
        case let .quantity(value):
            what = "\(rule.asset.formatQuantity(value, locale: locale)) \(rule.asset.unitLabel) \(rule.asset.displayName())"
        case let .amount(value):
            what = String(localized: "\(Money(value, .TRY).formatted(locale: locale, fractionDigits: 0)) · \(rule.asset.displayName())")
        }
        return what
    }

    static func trigger(_ rule: SavingsPlanRule) -> String {
        switch rule.trigger {
        case .salary: return String(localized: "Her maaşta")
        case let .schedule(frequency):
            switch frequency {
            case let .monthly(day, _): return String(localized: "Her ayın \(day). günü")
            case let .weekly(weekday):
                let name = Calendar.current.standaloneWeekdaySymbols[(weekday - 1) % 7]
                return String(localized: "Her hafta · \(name)")
            case let .yearly(month, day):
                let name = Calendar.current.standaloneMonthSymbols[(month - 1) % 12]
                return String(localized: "Her yıl · \(day) \(name)")
            }
        }
    }

    /// "12 vadenin 10'unda aldın" yerine ek almayan biçim: "Alım: 10 / 12 vade".
    static func adherence(_ progress: SavingsPlanProgress) -> String? {
        guard progress.dueCount > 0 else { return nil }
        return String(localized: "Alım: \(progress.keptCount) / \(progress.dueCount) vade")
    }
}

private struct PlanRow: View {
    let plan: SavingsPlan
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    var body: some View {
        if let rule = plan.rule {
            let progress = try? PlanStore(context: context).progress(of: plan)
            HStack(spacing: 12) {
                AssetBadge(asset: rule.asset)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: PlanText.title(rule, locale: locale)).font(.headline)
                    HStack(spacing: 4) {
                        Text(verbatim: PlanText.trigger(rule))
                        if let progress, let text = PlanText.adherence(progress) { Text(verbatim: "· \(text)") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if !plan.isActive {
                        Text("Duraklatıldı").font(.footnote).foregroundStyle(.orange)
                    } else if let next = progress?.nextDue {
                        Text("Sıradaki \(next.formatted(.dateTime.day().month(.wide)))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

struct PlanDetailView: View {
    let plan: SavingsPlan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    @Query private var trades: [AssetTrade]
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @State private var isEditing = false
    @State private var isBuying = false
    @State private var confirmsDeletion = false

    var body: some View {
        let store = PlanStore(context: context)
        let rule = plan.rule
        let progress = try? store.progress(of: plan)
        List {
            if let rule {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: PlanText.title(rule, locale: locale)).font(.title3.weight(.semibold))
                        Text(verbatim: PlanText.trigger(rule)).foregroundStyle(.secondary)
                        if let goal = goals.first(where: { $0.id == rule.goalID }) {
                            Label { Text(verbatim: goal.name) } icon: { Image(systemName: "target") }
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Şimdi al", systemImage: "cart") { isBuying = true }
                }

                if let progress {
                    Section {
                        if let text = PlanText.adherence(progress) {
                            LabeledContent("Uyum", value: text)
                        }
                        if let next = progress.nextDue {
                            LabeledContent("Sıradaki", value: next.formatted(.dateTime.day().month(.wide).year()))
                        }
                        LabeledContent("Biriken") {
                            Text(verbatim: "\(rule.asset.formatQuantity(progress.quantity, locale: locale)) \(rule.asset.unitLabel)")
                        }
                        if let average = progress.averageCost {
                            LabeledContent("Ortalama maliyet", value: "\(rule.asset.formatPrice(average, locale: locale)) ₺")
                        }
                        if let bid = board.quote(rule.asset)?.price(.bid) {
                            LabeledContent("Bugün bozdurma fiyatı", value: "\(rule.asset.formatPrice(bid, locale: locale)) ₺")
                        }
                    } header: {
                        Text("Gidiş")
                    } footer: {
                        Text("Plan başladığından beri bu varlıktan yaptığın alımlar sayılır; vadeden 3 gün önce yapılan alım o vadeye yazılır. Atlanan vade yalnız sayılır.")
                    }

                    if let comparison = comparison(rule, progress) {
                        Section {
                            LabeledContent("Bugünkü değeri", value: money(comparison.value))
                            LabeledContent("Aynı parayla dolar", value: money(comparison.usd))
                        } header: {
                            Text("Karşılaştırma")
                        } footer: {
                            Text(comparison.value >= comparison.usd
                                 ? "Bu plan, aynı paraları alım günlerinde dolara koymaktan \(money(comparison.value - comparison.usd)) daha iyi gitti."
                                 : "Aynı paraları alım günlerinde dolara koysaydın bugün \(money(comparison.usd - comparison.value)) daha fazlası olurdu.")
                        }
                    }
                }
            }

            Section {
                Toggle("Hatırlatma", isOn: Binding(get: { plan.isActive }, set: { active in
                    try? store.setActive(plan, active)
                    Reminders.schedulePlans((try? store.plans()) ?? [])
                }))
                Button("Planı sil", role: .destructive) { confirmsDeletion = true }
            } footer: {
                Text("Plan silinince yaptığın alımlar kalır.")
            }
        }
        .navigationTitle("Birikim planı")
        .toolbar {
            ToolbarItem { Button("Düzenle") { isEditing = true } }
        }
        .sheet(isPresented: $isEditing) { PlanEditor(editing: plan) }
        .sheet(isPresented: $isBuying) {
            if let rule {
                TradeEditor(mode: .create(rule.asset),
                            preset: .init(target: rule.target, goalID: rule.goalID, note: String(localized: "Birikim planı")))
            }
        }
        .confirmationDialog("Plan silinsin mi?", isPresented: $confirmsDeletion) {
            Button("Planı sil", role: .destructive) {
                Reminders.cancelPlan(plan.id)
                try? store.delete(plan)
                dismiss()
            }
        }
    }

    private func comparison(_ rule: SavingsPlanRule, _ progress: SavingsPlanProgress) -> (value: Decimal, usd: Decimal)? {
        guard progress.quantity > 0, let bid = board.quote(rule.asset)?.price(.bid), rule.asset != .fx(.USD),
              let usdNow = board.quote(.fx(.USD))?.price(.bid),
              let usd = progress.usdAlternative(usdTRYNow: usdNow) else { return nil }
        return (progress.value(at: bid), usd)
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }
}

struct PlanEditor: View {
    let editing: SavingsPlan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]

    private enum Kind: Hashable { case quantity, amount }
    private enum When: Hashable { case monthly, salary }
    private static let assets: [AssetCode] = [.gold(.gram24), .gold(.quarter), .gold(.half), .gold(.full), .gold(.republic),
                                              .gold(.bracelet22), .fx(.USD), .fx(.EUR)]

    @State private var asset: AssetCode = .gold(.gram24)
    @State private var kind: Kind = .quantity
    @State private var valueText = ""
    @State private var when: When = .monthly
    @State private var day = 15
    @State private var goalID: UUID?
    @State private var didLoad = false

    private var value: Decimal? { AmountParser(locale: locale).parse(valueText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Varlık", selection: $asset) {
                        ForEach(Self.assets, id: \.self) { Text(verbatim: $0.displayName()).tag($0) }
                    }
                    Picker("Ne kadar", selection: $kind) {
                        Text("Miktar").tag(Kind.quantity)
                        Text("TL tutarı").tag(Kind.amount)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField(kind == .quantity ? "Miktar" : "Tutar", text: $valueText)
                            .monospacedDigit()
                            .accessibilityIdentifier("plan.value")
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: kind == .quantity ? asset.unitLabel : "₺").foregroundStyle(.secondary)
                    }
                } footer: {
                    if kind == .amount {
                        Text("Miktar, alım günündeki satış fiyatından hesaplanır; adetli altında aşağı yuvarlanır.")
                    }
                }
                Section {
                    Picker("Ne zaman", selection: $when) {
                        Text("Her ay").tag(When.monthly)
                        Text("Maaş gelince").tag(When.salary)
                    }
                    .pickerStyle(.segmented)
                    if when == .monthly {
                        Picker("Gün", selection: $day) {
                            ForEach(1...28, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                        }
                    }
                } footer: {
                    Text(when == .monthly
                         ? "O gün sabah 09:00'da hatırlatılır."
                         : "Maaş kategorisinde gelir kaydedince \"Birikime ayır\" sayfası bu planla açılır.")
                }
                if !goals.isEmpty {
                    Section {
                        Picker("Hedef", selection: $goalID) {
                            Text("Yok").tag(UUID?.none)
                            ForEach(goals) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Yeni plan" : "Planı düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(value == nil)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let rule = editing?.rule else { return }
        asset = rule.asset
        goalID = rule.goalID
        switch rule.target {
        case let .quantity(value): kind = .quantity; valueText = plain(value)
        case let .amount(value): kind = .amount; valueText = plain(value)
        }
        switch rule.trigger {
        case .salary: when = .salary
        case let .schedule(.monthly(value, _)): when = .monthly; day = min(value, 28)
        case .schedule: when = .monthly
        }
    }

    private func plain(_ value: Decimal) -> String {
        var text = value.formattedNumber(locale: locale, fractionDigits: 0...4)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty { text = text.replacingOccurrences(of: grouping, with: "") }
        return text
    }

    private func save() {
        guard let value else { return }
        let rule = SavingsPlanRule(id: editing?.id ?? UUID(), asset: asset,
                                   target: kind == .quantity ? .quantity(value) : .amount(value),
                                   trigger: when == .salary ? .salary : .schedule(.monthly(day: day)),
                                   start: editing?.start ?? Calendar.current.startOfDay(for: .now), goalID: goalID)
        let store = PlanStore(context: context)
        _ = try? store.save(rule, editing: editing)
        Reminders.requestAuthorizationIfNeeded()
        Reminders.schedulePlans((try? store.plans()) ?? [])
        dismiss()
    }
}
