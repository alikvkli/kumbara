import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçeler (REQ-B1, B2; specs/08 §1). Rakam kahramandır: genel bütçenin kalanı üstte, kategori
/// satırları altta. Renk yalnız anlam taşır: normal vurgu, %80+ turuncu, aşım kırmızı (C6).
struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    // Gözlem için: işlem ya da bütçe değişince ekran yeniden hesaplanır.
    @Query private var transactions: [LedgerTransaction]
    @Query private var budgetModels: [Budget]
    @State private var selectedMonth: LedgerMonth?
    @State private var editing: BudgetEditor.Target?

    private var month: LedgerMonth { selectedMonth ?? LedgerMonth(containing: .now, calendar: calendar) }
    private var store: BudgetStore { BudgetStore(context: context) }

    var body: some View {
        let statuses = (try? store.statuses(for: month, calendar: calendar, rate: rate)) ?? []
        let overall = statuses.first { $0.categoryID == nil }
        let categories = statuses.filter { $0.categoryID != nil }
        let suggestions = categories.isEmpty ? ((try? store.suggestions(before: month, calendar: calendar)) ?? []) : []

        Group {
            if budgetModels.isEmpty && suggestions.isEmpty {
                ContentUnavailableView {
                    Label("Bütçe yok", systemImage: "chart.pie")
                } description: {
                    Text("Kategori bazında aylık limit belirle; %80 ve %100'de haber vereyim.")
                } actions: {
                    Button("Bütçe ekle") { editing = .new }
                        .primaryActionStyle()
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            MonthMenu(month: month, selection: $selectedMonth)
                            if let overall {
                                OverallBudgetHeader(status: overall, month: month)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = .overall }
                            } else {
                                Button("Aylık genel bütçe belirle") { editing = .overall }
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    }

                    if !categories.isEmpty {
                        Section {
                            ForEach(categories) { status in
                                let model = budgetModels.first { $0.id == status.id }
                                Button { if let category = model?.category { editing = .category(category) } } label: {
                                    BudgetRow(status: status, category: model?.category)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Sil", role: .destructive) { if let model { try? store.delete(model) } }
                                }
                            }
                            // Araç çubuğunda zaten "yeni işlem" (+) var; ikinci bir + karışır (specs/06 §9).
                            Button("Bütçe ekle", systemImage: "plus.circle") { editing = .new }
                        } header: {
                            Text("Kategoriler")
                        } footer: {
                            if statuses.contains(where: \.hasUnconvertedEntries) {
                                Text("Kuru bulunamayan döviz harcamaları bütçeye sayılmadı.")
                            }
                        }
                    }

                    if !suggestions.isEmpty {
                        Section {
                            ForEach(suggestions, id: \.category.id) { item in
                                SuggestionRow(category: item.category, limit: item.limit) {
                                    _ = try? store.setLimit(item.limit, for: item.category, from: month)
                                    BudgetMonitor.shared.requestAuthorizationIfNeeded()
                                }
                            }
                            if suggestions.count > 1 {
                                Button("Hepsini ekle") {
                                    for item in suggestions { _ = try? store.setLimit(item.limit, for: item.category, from: month) }
                                    BudgetMonitor.shared.requestAuthorizationIfNeeded()
                                }
                            }
                        } header: {
                            Text("Önerilen bütçeler")
                        } footer: {
                            Text("Son 3 ayda bu kategorilere ortalama harcadığın tutar, yukarı yuvarlanmış.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bütçe")
        .sheet(item: $editing) { target in
            BudgetEditor(target: target, month: month)
        }
    }

    /// Döviz giderleri güncel kurla TRY'ye çevrilir (specs/08 §1.2).
    private func rate(_ currency: CurrencyCode, _ date: Date) -> Decimal? {
        board.quote(.fx(currency))?.mid
    }
}

private extension BudgetStatus {
    var tint: Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .over: .red
        }
    }

    var progress: Double { (min(max(ratio, 0), 1) as NSDecimalNumber).doubleValue }
}

/// Genel bütçe: kalan tutar kahraman, altında limit, ilerleme ve günlük hak.
private struct OverallBudgetHeader: View {
    let status: BudgetStatus
    let month: LedgerMonth
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        let allowance = DailyAllowance(remaining: status.remaining, month: month, today: .now, calendar: calendar)
        VStack(alignment: .leading, spacing: 6) {
            if status.level == .over {
                HeroAmount(money: status.spent - status.limit)
                Text("bütçe aşıldı · \(status.spent.formatted(locale: locale, fractionDigits: 0)) / \(status.limit.formatted(locale: locale, fractionDigits: 0))")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                HeroAmount(money: status.remaining)
                Text("kaldı · \(status.spent.formatted(locale: locale, fractionDigits: 0)) / \(status.limit.formatted(locale: locale, fractionDigits: 0))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: status.progress)
                .tint(status.tint)
            if let allowance, status.level != .over {
                Text("\(allowance.remainingDays) gün kaldı · günlük \(allowance.perDay.formatted(locale: locale, fractionDigits: 0))")
                    .font(.subheadline)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

private struct BudgetRow: View {
    let status: BudgetStatus
    let category: LedgerCategory?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CategoryBadge(systemImage: category?.resolvedSymbol ?? "circle.dashed", color: category?.color.color ?? .secondary)
                Text(verbatim: category?.path ?? "—")
                Spacer()
                Text(verbatim: "\(status.spent.formatted(locale: locale, fractionDigits: 0)) / \(status.limit.formatted(locale: locale, fractionDigits: 0))")
                    .monospacedDigit()
            }
            ProgressView(value: status.progress)
                .tint(status.tint)
            note
                .font(.footnote)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var note: some View {
        switch status.level {
        case .over:
            Text("\((status.spent - status.limit).formatted(locale: locale, fractionDigits: 0)) aşıldı")
                .foregroundStyle(.red)
        case .warning:
            Text("%\(percent(status.ratio)) · kalan \(status.remaining.formatted(locale: locale, fractionDigits: 0))")
                .foregroundStyle(.orange)
        case .normal where status.isAheadOfPace:
            Text("Hızlı gidiyor · bütçe %\(percent(status.ratio)), ay %\(percent(status.elapsed))")
                .foregroundStyle(.secondary)
        case .normal:
            Text("kalan \(status.remaining.formatted(locale: locale, fractionDigits: 0))")
                .foregroundStyle(.secondary)
        }
    }

    private func percent(_ value: Decimal) -> String {
        "\(Int(truncating: (value * 100).rounded(scale: 0) as NSDecimalNumber))"
    }
}

private struct SuggestionRow: View {
    let category: LedgerCategory
    let limit: Decimal
    let add: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            CategoryBadge(systemImage: category.resolvedSymbol, color: category.color.color)
            Text(verbatim: category.name)
            Spacer()
            Text(verbatim: Money(limit, .TRY).formatted(locale: locale, fractionDigits: 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Ekle", action: add)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
