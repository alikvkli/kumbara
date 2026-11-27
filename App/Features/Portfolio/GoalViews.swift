import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Birikim hedefleri (REQ-P9, specs/09 §6): Birikim sekmesinin üstünde, ayrıntıda atanmış alımlar.
struct GoalsSection: View {
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var trades: [AssetTrade]
    @State private var isAdding = false

    var body: some View {
        Section {
            ForEach(goals) { goal in
                NavigationLink {
                    GoalDetailView(goal: goal)
                } label: {
                    GoalRow(goal: goal, trades: trades.filter { $0.goalID == goal.id })
                }
            }
            Button("Hedef ekle", systemImage: "plus.circle") { isAdding = true }
        } header: {
            Text("Hedefler")
        } footer: {
            if goals.isEmpty {
                Text("\"Düğün için 20 çeyrek\" ya da \"Ev için ₺500.000\" gibi bir hedef koy; alım kaydederken hangi hedef için olduğunu seç.")
            }
        }
        .sheet(isPresented: $isAdding) { GoalEditor(editing: nil) }
    }
}

/// Hedefin ilerlemesi, bugünkü fiyatlarla.
@MainActor
private func goalProgress(of goal: Goal, trades: [AssetTrade], board: PriceBoard, priceKind: PriceKind) -> GoalProgress? {
    guard let value = goal.goal else { return nil }
    let assigned = trades.compactMap(\.trade)
    var prices: [AssetCode: Decimal] = [:]
    for asset in Set(assigned.map(\.asset)) {
        if let quote = board.quote(asset) { prices[asset] = quote.price(priceKind) }
    }
    return GoalMath.progress(of: value, trades: assigned, prices: prices, now: .now, calendar: .current)
}

private struct GoalRow: View {
    let goal: Goal
    let trades: [AssetTrade]
    @Environment(PriceBoard.self) private var board
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid

    var body: some View {
        if let value = goal.goal, let progress = goalProgress(of: goal, trades: trades, board: board, priceKind: priceKind) {
            HStack(spacing: 14) {
                GoalRing(fraction: progress.fraction, isReached: progress.isReached)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: goal.name).font(.headline)
                    Text(verbatim: GoalText.figures(value, progress, locale: locale))
                        .font(.subheadline)
                        .monospacedDigit()
                    if let note = GoalText.pace(value, progress, locale: locale) {
                        Text(verbatim: note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// İlerleme halkası. Hedefe ulaşılınca dolu ve onay işaretli; renk vurgu (anlamı ilerleme).
struct GoalRing: View {
    let fraction: Double
    let isReached: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isReached {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.tint)
            } else {
                Text(verbatim: Decimal(fraction).formattedPercent(fractionDigits: 0))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(Text(isReached ? "Hedefe ulaşıldı" : "İlerleme"))
    }
}

enum GoalText {
    /// "8 / 20 adet" ya da "₺105.000 / ₺500.000".
    static func figures(_ goal: SavingsGoal, _ progress: GoalProgress, locale: Locale) -> String {
        switch goal.target {
        case let .quantity(asset, _):
            "\(asset.formatQuantity(progress.current, locale: locale)) / \(asset.formatQuantity(progress.target, locale: locale)) \(asset.unitLabel)"
        case .amount:
            "\(Money(progress.current, .TRY).formatted(locale: locale, fractionDigits: 0)) / \(Money(progress.target, .TRY).formatted(locale: locale, fractionDigits: 0))"
        }
    }

    /// "Ayda 2 adet ayırırsan Eylül'e yetişir" · "12 adet kaldı" · "Hedefe ulaşıldı".
    static func pace(_ goal: SavingsGoal, _ progress: GoalProgress, locale: Locale) -> String? {
        if progress.isReached { return String(localized: "Hedefe ulaşıldı") }
        let remaining: String
        let perMonth: String?
        switch goal.target {
        case let .quantity(asset, _):
            remaining = "\(asset.formatQuantity(progress.remaining, locale: locale)) \(asset.unitLabel)"
            perMonth = progress.perMonth.map { value in
                var value = value, rounded = Decimal()
                NSDecimalRound(&rounded, &value, asset.unit == .piece ? 0 : 2, .up)
                return "\(asset.formatQuantity(rounded, locale: locale)) \(asset.unitLabel)"
            }
        case .amount:
            remaining = Money(progress.remaining, .TRY).formatted(locale: locale, fractionDigits: 0)
            perMonth = progress.perMonth.map { Money($0, .TRY).formatted(locale: locale, fractionDigits: 0) }
        }
        if let perMonth, let deadline = goal.deadline {
            let month = deadline.formatted(.dateTime.month(.wide).year())
            return String(localized: "Ayda \(perMonth) ayırırsan \(month) hedefine yetişir")
        }
        return String(localized: "\(remaining) kaldı")
    }
}

/// Hedef ayrıntısı: ilerleme, atanmış alımlar, atanmamış aynı varlık önerisi.
struct GoalDetailView: View {
    let goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid
    @Query(sort: \AssetTrade.date, order: .reverse) private var trades: [AssetTrade]
    @State private var isEditing = false
    @State private var confirmsDeletion = false

    var body: some View {
        let assigned = trades.filter { $0.goalID == goal.id }
        let store = GoalStore(context: context)
        List {
            if let value = goal.goal, let progress = goalProgress(of: goal, trades: assigned, board: board, priceKind: priceKind) {
                Section {
                    HStack(spacing: 18) {
                        GoalRing(fraction: progress.fraction, isReached: progress.isReached).frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: GoalText.figures(value, progress, locale: locale))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            if let pace = GoalText.pace(value, progress, locale: locale) {
                                Text(verbatim: pace).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if progress.hasMissingPrices {
                                Text("Bazı varlıkların fiyatı yok; toplam eksik.").font(.footnote).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
            }

            if let free = try? store.unassigned(for: goal), free.quantity > 0, case let .quantity(asset, _)? = goal.goal?.target {
                Section {
                    Button {
                        try? store.assign(free.trades, to: goal)
                    } label: {
                        Label("Elinde hedefe atanmamış \(asset.formatQuantity(free.quantity, locale: locale)) \(asset.unitLabel) daha var, ekle",
                              systemImage: "plus.circle")
                    }
                }
            }

            Section {
                if assigned.isEmpty {
                    Text("Alım kaydederken \"Hedef\" alanından bu hedefi seç.").foregroundStyle(.secondary)
                }
                ForEach(assigned) { record in
                    if let trade = record.trade {
                        HStack {
                            AssetBadge(asset: trade.asset)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "\(trade.asset.formatQuantity(trade.quantity, locale: locale)) \(trade.asset.unitLabel) \(trade.asset.displayName())")
                                Text(trade.date, format: .dateTime.day().month().year()).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(verbatim: Money(trade.grossCost, .TRY).formatted(locale: locale, fractionDigits: 0))
                                .monospacedDigit()
                                .foregroundStyle(trade.side == .sell ? Color.secondary : Color.primary)
                        }
                        .swipeActions {
                            Button("Hedeften çıkar") { try? store.assign([record], to: nil) }
                        }
                    }
                }
            } header: {
                Text("Bu hedef için")
            }

            Section {
                Button("Hedefi sil", role: .destructive) { confirmsDeletion = true }
            } footer: {
                Text("Alımlar silinmez, yalnız hedeften çıkar.")
            }
        }
        .navigationTitle(Text(verbatim: goal.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Düzenle") { isEditing = true } }
        }
        .sheet(isPresented: $isEditing) { GoalEditor(editing: goal) }
        .confirmationDialog("Hedef silinsin mi?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                try? store.delete(goal)
                dismiss()
            }
        }
    }
}

/// Hedef ekle / düzenle.
struct GoalEditor: View {
    let editing: Goal?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private enum Kind: Hashable { case quantity, amount }
    private static let assets: [AssetCode] = [.gold(.quarter), .gold(.gram24), .gold(.half), .gold(.full), .gold(.republic),
                                              .gold(.bracelet22), .fx(.USD), .fx(.EUR)]

    @State private var name = ""
    @State private var kind: Kind = .quantity
    @State private var asset: AssetCode = .gold(.quarter)
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var didLoad = false

    private var target: Decimal? {
        AmountParser(locale: locale).parse(targetText).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad (ör. Düğün)", text: $name)
                    Picker("Hedef", selection: $kind) {
                        Text("Varlık miktarı").tag(Kind.quantity)
                        Text("TL tutarı").tag(Kind.amount)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if kind == .quantity {
                        Picker("Varlık", selection: $asset) {
                            ForEach(Self.assets, id: \.self) { Text(verbatim: $0.displayName()).tag($0) }
                        }
                    }
                    HStack {
                        TextField(kind == .quantity ? "Miktar" : "Tutar", text: $targetText)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: kind == .quantity ? asset.unitLabel : "₺").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(kind == .quantity
                         ? "İlerleme, bu hedefe atadığın alımların miktarıdır."
                         : "İlerleme, bu hedefe atadığın alımların bugünkü bozdurma değeridir.")
                }
                Section {
                    Toggle("Hedef tarihi", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Tarih", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    if hasDeadline { Text("Ayda ne kadar ayırman gerektiğini söylerim.") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Yeni hedef" : "Hedefi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .primaryActionStyle()
                        .disabled(target == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let value = editing?.goal else { return }
        name = value.name
        switch value.target {
        case let .quantity(code, quantity):
            kind = .quantity
            asset = code
            targetText = quantity.formattedNumber(locale: locale, fractionDigits: 0...2)
        case let .amount(amount):
            kind = .amount
            targetText = amount.formattedNumber(locale: locale, fractionDigits: 0...2)
        }
        if let date = value.deadline {
            hasDeadline = true
            deadline = date
        }
        if let grouping = locale.groupingSeparator, !grouping.isEmpty {
            targetText = targetText.replacingOccurrences(of: grouping, with: "")
        }
    }

    private func save() {
        guard let target else { return }
        let value = SavingsGoal(id: editing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces),
                                target: kind == .quantity ? .quantity(asset, target) : .amount(target),
                                deadline: hasDeadline ? deadline : nil)
        _ = try? GoalStore(context: context).save(value, editing: editing)
        dismiss()
    }
}
