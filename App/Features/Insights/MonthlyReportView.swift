import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

extension LedgerMonth: @retroactive Identifiable {
    public var id: Int { year * 100 + month }
}

extension LedgerMonth {
    func title(calendar: Calendar) -> String {
        interval(in: calendar).start.formatted(.dateTime.month(.wide).year())
    }

    func name(calendar: Calendar) -> String {
        interval(in: calendar).start.formatted(.dateTime.month(.wide))
    }

    /// UserDefaults anahtarı için "2026-10".
    var key: String { "\(year)-\(month)" }
}

/// Raporun başındaki tek cümle (specs/10 §1). Değişkenden sonra ek yok (specs/06 §11):
/// "Kasım ayında", "Market kategorisinde".
enum ReportText {
    static func headline(_ report: MonthlyReport, categories: [UUID: LedgerCategory], showsAmounts: Bool = true,
                         calendar: Calendar, locale: Locale) -> String {
        let month = report.month.name(calendar: calendar)
        func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }
        func percent(_ value: Decimal) -> String { abs(value).formattedPercent(locale: locale, fractionDigits: 0) }

        switch report.headline {
        case let .overspent(by):
            return showsAmounts
                ? String(localized: "\(month) ayında gelirinden \(money(by)) fazla harcadın.")
                : String(localized: "\(month) ayında gelirinden fazla harcadın.")
        case let .steady(expense, hasPrevious):
            switch (showsAmounts, hasPrevious) {
            case (true, true): return String(localized: "\(month) ayında \(money(expense)) harcadın, önceki ayla hemen hemen aynı.")
            case (true, false): return String(localized: "\(month) ayında \(money(expense)) harcadın.")
            case (false, true): return String(localized: "\(month) ayında önceki ay kadar harcadın.")
            case (false, false): return String(localized: "\(month) ayının özeti.")
            }
        case let .changed(expense, ratio, driver):
            let up = ratio > 0
            var sentence: String
            if showsAmounts {
                sentence = up
                    ? String(localized: "\(month) ayında \(money(expense)) harcadın, önceki aydan \(percent(ratio)) fazla")
                    : String(localized: "\(month) ayında \(money(expense)) harcadın, önceki aydan \(percent(ratio)) az")
            } else {
                sentence = up
                    ? String(localized: "\(month) ayında önceki aydan \(percent(ratio)) fazla harcadın")
                    : String(localized: "\(month) ayında önceki aydan \(percent(ratio)) az harcadın")
            }
            if let driver {
                let name = driver.categoryID.flatMap { categories[$0]?.name } ?? String(localized: "Kategorisiz")
                sentence += up
                    ? String(localized: "; artış çoğunlukla \(name) kategorisinde.")
                    : String(localized: "; düşüş çoğunlukla \(name) kategorisinde.")
            } else {
                sentence += "."
            }
            return sentence
        }
    }

    static func savings(_ savings: MonthlyReport.Savings, locale: Locale) -> String? {
        guard let priceReturn = savings.priceReturn else { return nil }
        let change = abs(priceReturn).formattedPercent(locale: locale, fractionDigits: 1)
        var sentence = priceReturn >= 0
            ? String(localized: "Birikimin fiyat olarak \(change) değer kazandı")
            : String(localized: "Birikimin fiyat olarak \(change) değer kaybetti")
        if let inflation = savings.inflation {
            let cpi = inflation.formattedPercent(locale: locale, fractionDigits: 1)
            sentence += priceReturn >= inflation
                ? String(localized: "; aynı ay enflasyon \(cpi), yani enflasyonun önünde.")
                : String(localized: "; aynı ay enflasyon \(cpi), yani enflasyonun gerisinde.")
        } else {
            sentence += "."
        }
        return sentence
    }
}

/// Kapanan ayın tek sayfalık raporu (REQ-I1, specs/10 §1). Yalnız verisi olan bölümler görünür.
struct MonthlyReportView: View {
    let month: LedgerMonth
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var transactions: [LedgerTransaction]
    @State private var isSharing = false

    var body: some View {
        let store = InsightStore(context: context)
        let report = (try? store.report(for: month, now: .now, calendar: calendar))
        let ids = (report?.categoryChanges.map(\.categoryID) ?? []) + (report?.overBudget.map(\.categoryID) ?? [])
            + (report?.topExpenses.map(\.categoryID) ?? [])
        let categories = (try? store.categories(ids)) ?? [:]

        Group {
            if let report, report.hasContent {
                content(report, categories: categories)
            } else {
                ContentUnavailableView("Bu ay için kayıt yok", systemImage: "doc.text",
                                       description: Text("Rapor, ayda en az bir gider olunca oluşur."))
            }
        }
        .navigationTitle(month.title(calendar: calendar))
        .toolbar {
            ToolbarItem {
                if let report, report.hasContent {
                    Button("Paylaş", systemImage: "square.and.arrow.up") { isSharing = true }
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let report {
                ReportShareSheet(report: report, categories: categories)
            }
        }
    }

    private func content(_ report: MonthlyReport, categories: [UUID: LedgerCategory]) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(ReportText.headline(report, categories: categories, calendar: calendar, locale: locale))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top) {
                        figure("Gelir", report.income)
                        figure("Gider", report.expense)
                        figure("Kalan", report.net)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 12, trailing: 4))
            }

            if report.previousExpense != nil || report.averageExpense != nil {
                Section {
                    if let previous = report.previousExpense {
                        comparison("Önceki ay", previous, change: report.change)
                    }
                    if let average = report.averageExpense, report.averageMonths > 1 {
                        comparison("Son \(report.averageMonths) ayın ortalaması", average, change: report.changeFromAverage)
                    }
                } header: {
                    Text("Gider karşılaştırması")
                }
            }

            if let budget = report.budget {
                Section("Bütçe") {
                    LabeledContent {
                        Text(verbatim: "\(money(budget.spent)) / \(money(budget.limit))").monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aylık bütçe")
                            if budget.spent > budget.limit {
                                Text("\(money(budget.overrun)) aşıldı").font(.footnote).foregroundStyle(.red)
                            } else {
                                Text("Kullanılan \(budget.usage.formattedPercent(locale: locale, fractionDigits: 0)) · kalan \(money(budget.limit - budget.spent))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(report.overBudget, id: \.categoryID) { line in
                        let category = line.categoryID.flatMap { categories[$0] }
                        LabeledContent {
                            Text("\(money(line.overrun)) aşıldı").foregroundStyle(.red).monospacedDigit()
                        } label: {
                            CategoryLabel(category: category)
                        }
                    }
                }
            }

            if !report.categoryChanges.isEmpty {
                Section {
                    ForEach(report.categoryChanges, id: \.categoryID) { change in
                        CategoryChangeRow(change: change, category: change.categoryID.flatMap { categories[$0] })
                    }
                } header: {
                    Text("En çok değişenler")
                } footer: {
                    Text("Önceki aya göre; ₺500'den küçük farklar sayılmaz.")
                }
            }

            if !report.topExpenses.isEmpty {
                Section("En büyük harcamalar") {
                    ForEach(report.topExpenses) { entry in
                        let category = entry.categoryID.flatMap { categories[$0] }
                        LabeledContent {
                            Text(verbatim: entry.amount.formatted(locale: locale)).monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: entry.merchant ?? category?.name ?? String(localized: "Gider"))
                                Text(entry.date.formatted(.dateTime.day().month(.wide)))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let visit = report.topMerchant {
                        LabeledContent {
                            Text(verbatim: money(visit.total)).monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("En sık gidilen: \(visit.name)")
                                Text("\(visit.count) kez").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let savings = report.savings {
                Section {
                    LabeledContent("Ay başı", value: money(savings.startValue))
                    LabeledContent("Ay sonu", value: money(savings.endValue))
                    if savings.contributions != 0 {
                        LabeledContent(savings.contributions > 0 ? LocalizedStringKey("Eklediğin") : LocalizedStringKey("Çektiğin"),
                                       value: money(abs(savings.contributions)))
                    }
                    LabeledContent("Fiyat etkisi") {
                        Text(verbatim: Money(savings.priceEffect, .TRY).formatted(locale: locale, sign: .always, fractionDigits: 0))
                            .foregroundStyle(savings.priceEffect >= 0 ? Color.green : Color.red)
                    }
                } header: {
                    Text("Birikim")
                } footer: {
                    if let sentence = ReportText.savings(savings, locale: locale) {
                        Text(sentence + " " + String(localized: "Eklediğin para fiyat etkisine katılmaz. Enflasyon: TÜİK TÜFE."))
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }

    private func figure(_ title: LocalizedStringKey, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: money(value))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func comparison(_ title: LocalizedStringKey, _ value: Decimal, change: Decimal?) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: money(value)).monospacedDigit()
                if let change {
                    ChangeText(change: change).font(.footnote)
                }
            }
        } label: {
            Text(title)
        }
    }
}

/// "%4 fazla" / "%3 az": bu ayın gideri karşılaştırılan tutara göre.
struct ChangeText: View {
    let change: Decimal
    @Environment(\.locale) private var locale

    var body: some View {
        let percent = abs(change).formattedPercent(locale: locale, fractionDigits: 0)
        if change > 0 {
            Text("bu ay \(percent) fazla").foregroundStyle(.secondary)
        } else if change < 0 {
            Text("bu ay \(percent) az").foregroundStyle(.secondary)
        } else {
            Text("aynı").foregroundStyle(.secondary)
        }
    }
}

private struct CategoryLabel: View {
    let category: LedgerCategory?

    var body: some View {
        HStack {
            CategoryBadge(systemImage: category?.resolvedSymbol ?? "circle.dashed", color: category?.color.color ?? .secondary)
            if let category { Text(verbatim: category.name) } else { Text("Kategorisiz") }
        }
    }
}

private struct CategoryChangeRow: View {
    let change: MonthlyReport.CategoryChange
    let category: LedgerCategory?
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: Money(change.difference, .TRY).formatted(locale: locale, sign: .always, fractionDigits: 0))
                    .monospacedDigit()
                if let ratio = change.ratio {
                    Text(verbatim: ratio.formattedPercent(locale: locale, fractionDigits: 0, sign: .always))
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("önceki ay yoktu").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                CategoryLabel(category: category)
                Text(verbatim: "\(Money(change.previous, .TRY).formatted(locale: locale, fractionDigits: 0)) → \(Money(change.current, .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Özet › Aylık raporlar.
struct ReportsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var transactions: [LedgerTransaction]

    var body: some View {
        let store = InsightStore(context: context)
        let months = (try? store.reportMonths(now: .now, calendar: calendar)) ?? []
        Group {
            if months.isEmpty {
                ContentUnavailableView("Henüz rapor yok", systemImage: "doc.text",
                                       description: Text("İlk ay kapanınca raporu burada görürsün."))
            } else {
                List(months) { month in
                    NavigationLink { MonthlyReportView(month: month) } label: {
                        ReportListRow(month: month)
                    }
                }
            }
        }
        .navigationTitle("Aylık raporlar")
    }
}

private struct ReportListRow: View {
    let month: LedgerMonth
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = MonthlySummary(entries: (try? LedgerStore(context: context).entries(in: month, calendar: calendar)) ?? [],
                                     month: month, currency: .TRY, calendar: calendar)
        LabeledContent {
            Text(verbatim: summary.expense.formatted(locale: locale, fractionDigits: 0)).monospacedDigit()
        } label: {
            Text(verbatim: month.title(calendar: calendar))
        }
    }
}

/// Özet'in başındaki "Ekim raporu hazır" kartı.
struct ReportBanner: View {
    let month: LedgerMonth
    let report: MonthlyReport
    let open: () -> Void
    let close: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let ids = report.categoryChanges.map(\.categoryID)
        let categories = (try? InsightStore(context: context).categories(ids)) ?? [:]
        HStack(alignment: .top, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(month.name(calendar: calendar)) raporu hazır").font(.headline)
                        Text(ReportText.headline(report, categories: categories, calendar: calendar, locale: locale))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Kapat", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
