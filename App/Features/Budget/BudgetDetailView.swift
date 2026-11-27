import Charts
import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bir bütçenin ayrıntısı: ay içinde birikimli harcama, plan çizgisi ve limit; bu ayın harcamaları;
/// limiti ayarlamak için son 3 ayın gerçekleşenleri (specs/08 §1.4).
struct BudgetDetailView: View {
    let budgetID: UUID
    let month: LedgerMonth

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    @Query private var budgets: [Budget]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @State private var editing: BudgetEditor.Target?
    @State private var editingTransaction: LedgerTransaction?

    private var store: BudgetStore { BudgetStore(context: context) }
    private var budget: Budget? { budgets.first { $0.id == budgetID } }

    var body: some View {
        if let budget, let status = try? store.statuses(for: month, calendar: calendar, rate: rate).first(where: { $0.id == budgetID }) {
            content(budget: budget, status: status)
        } else {
            ContentUnavailableView("Bu ay için bütçe yok", systemImage: "chart.pie")
        }
    }

    private func money(_ value: Money) -> String { value.formatted(locale: locale, fractionDigits: 0) }

    private func content(budget: Budget, status: BudgetStatus) -> some View {
        let index = (try? store.categoryIndex()) ?? CategoryIndex(parent: [:], expense: [])
        let interval = month.interval(in: calendar)
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
        let series = BudgetMath.dailyCumulative(budget.spec, entries: transactions.map(\.entry), categories: index,
                                                month: month, through: .now, calendar: calendar, rate: rate)
        let monthTransactions = transactions.filter { transaction in
            guard transaction.status == .posted, transaction.kind != .transfer,
                  transaction.date >= interval.start, transaction.date < interval.end else { return false }
            if let target = status.categoryID {
                return transaction.category.map { index.isWithin($0.id, target) } ?? false
            }
            return transaction.kind == .expense
        }
        let recent = (try? store.recentSpending(for: budget.isOverall ? nil : budget.category, before: month, calendar: calendar)) ?? []
        let recentMonths = [month.previous.previous.previous, month.previous.previous, month.previous]

        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: money(status.level == .over ? status.spent - status.limit : status.remaining))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(status.level == .over ? Color.red : Color.primary)
                    Text(status.level == .over ? "aşıldı · limit \(money(status.limit))" : "kaldı · limit \(money(status.limit))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PaceBar(status: status, height: 10)
                    HStack {
                        if status.isCurrentMonth && status.level != .over {
                            Text("günde \(money(status.perDay)) · \(status.remainingDays) gün")
                        }
                        Spacer()
                        if status.isCurrentMonth { PaceText(status: status) }
                    }
                    .font(.subheadline)
                }
                .monospacedDigit()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            Section {
                SpendingChart(series: series, days: days, limit: status.limit.amount, tint: status.tint,
                              projected: status.isCurrentMonth ? status.projected?.amount : nil)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            } footer: {
                HStack(spacing: 16) {
                    LegendKey(color: status.tint, dashed: false, title: Text("Harcama"))
                    LegendKey(color: .secondary, dashed: true, title: Text("Plan"))
                }
            }

            Section {
                if monthTransactions.isEmpty {
                    Text("Bu ay harcama yok").foregroundStyle(.secondary)
                } else {
                    ForEach(monthTransactions.prefix(50)) { transaction in
                        Button { editingTransaction = transaction } label: { TransactionRow(transaction: transaction) }
                            .tint(.primary)
                    }
                }
            } header: {
                Text("Bu ay")
            }

            if recent.contains(where: { $0 > 0 }) {
                Section {
                    ForEach(Array(zip(recentMonths, recent)), id: \.0) { pair in
                        LabeledContent {
                            Text(verbatim: money(Money(pair.1, .TRY)))
                                .monospacedDigit()
                                .foregroundStyle(pair.1 > status.limit.amount ? Color.orange : Color.primary)
                        } label: {
                            Text(pair.0.interval(in: calendar).start, format: .dateTime.month(.wide))
                        }
                    }
                } header: {
                    Text("Son 3 ay")
                } footer: {
                    if let suggestion = BudgetMath.suggestedLimit(monthlySpending: recent) {
                        Text("Ortalamaya göre önerilen limit \(money(Money(suggestion, .TRY))).")
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: budget.isOverall ? String(localized: "Genel bütçe") : budget.category?.path ?? ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Düzenle") {
                    if budget.isOverall {
                        editing = .overall
                    } else if let category = budget.category {
                        editing = .category(category)
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            BudgetEditor(target: target, month: month)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditor(mode: .edit(transaction))
        }
    }

    private func rate(_ currency: CurrencyCode, _ date: Date) -> Decimal? {
        board.quote(.fx(currency))?.mid
    }
}

/// Birikimli harcama (basamak), plan çizgisi (0 → limit) ve limit; ay sonu tahmini kesikli uzanır.
private struct SpendingChart: View {
    let series: [(day: Int, total: Decimal)]
    let days: Int
    let limit: Decimal
    let tint: Color
    let projected: Decimal?

    private func double(_ value: Decimal) -> Double { (value as NSDecimalNumber).doubleValue }

    /// Üstte boşluk kalmasın: limit, harcama ve tahminin en büyüğü + %8 pay.
    private var yMax: Double {
        let peak = [limit, series.last?.total ?? 0, projected ?? 0].max() ?? limit
        return max(double(peak) * 1.08, 1)
    }

    var body: some View {
        Chart {
            LineMark(x: .value("Gün", 0), y: .value("Tutar", 0.0), series: .value("Seri", "plan"))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            LineMark(x: .value("Gün", days), y: .value("Tutar", double(limit)), series: .value("Seri", "plan"))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            RuleMark(y: .value("Limit", double(limit)))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(series, id: \.day) { point in
                AreaMark(x: .value("Gün", point.day), y: .value("Tutar", double(point.total)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(tint.opacity(0.12))
                LineMark(x: .value("Gün", point.day), y: .value("Tutar", double(point.total)), series: .value("Seri", "spent"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let projected, let last = series.last {
                LineMark(x: .value("Gün", last.day), y: .value("Tutar", double(last.total)), series: .value("Seri", "projection"))
                    .foregroundStyle(tint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                LineMark(x: .value("Gün", days), y: .value("Tutar", double(projected)), series: .value("Seri", "projection"))
                    .foregroundStyle(tint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
        }
        .chartXScale(domain: 0...days)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: [1, 10, 20, days]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .accessibilityLabel(Text("Ay içinde birikimli harcama ve plan çizgisi"))
    }
}

private struct LegendKey: View {
    let color: Color
    let dashed: Bool
    let title: Text

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 16, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
            .frame(width: 16, height: 8)
            title
        }
        .font(.caption)
        .accessibilityHidden(true)
    }
}
