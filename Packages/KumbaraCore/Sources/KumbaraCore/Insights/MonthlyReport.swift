import Foundation

/// Kapanan ayın tek sayfalık raporu (REQ-I1, specs/10 §1).
///
/// Yalnız verisi olan bölümler doldurulur; ekran boş bölümü göstermez. Gider dağılımı, çağıranın
/// verdiği kategori kimlikleriyle yapılır (Özet gibi üst kategoriye toplanmış olarak verilmeli).
public struct MonthlyReport: Hashable, Sendable {
    public struct CategoryChange: Hashable, Sendable {
        public var categoryID: UUID?
        public var current: Decimal
        public var previous: Decimal
        public var difference: Decimal { current - previous }
        /// Önceki ay sıfırsa `nil`.
        public var ratio: Decimal? { previous > 0 ? difference / previous : nil }
    }

    public struct MerchantVisit: Hashable, Sendable {
        public var name: String
        public var count: Int
        public var total: Decimal
    }

    /// Bütçe satırı: `categoryID == nil` genel bütçe.
    public struct BudgetLine: Hashable, Sendable {
        public var categoryID: UUID?
        public var limit: Decimal
        public var spent: Decimal
        public init(categoryID: UUID?, limit: Decimal, spent: Decimal) {
            self.categoryID = categoryID
            self.limit = limit
            self.spent = spent
        }
        public var usage: Decimal { limit > 0 ? spent / limit : 0 }
        public var overrun: Decimal { max(spent - limit, 0) }
    }

    /// Birikimin ay içindeki değişimi, eklenen para ve fiyat etkisi ayrı.
    public struct Savings: Hashable, Sendable {
        public var startValue: Decimal
        public var endValue: Decimal
        /// Ay içindeki alımlar eksi satışlar (ödenen / alınan tutar).
        public var contributions: Decimal
        public var priceEffect: Decimal { endValue - startValue - contributions }
        /// Aynı ayın TÜFE değişimi (veri varsa).
        public var inflation: Decimal?
        /// Fiyat etkisinin başlangıç değerine oranı.
        public var priceReturn: Decimal? { startValue > 0 ? priceEffect / startValue : nil }

        public init(startValue: Decimal, endValue: Decimal, contributions: Decimal, inflation: Decimal?) {
            self.startValue = startValue
            self.endValue = endValue
            self.contributions = contributions
            self.inflation = inflation
        }

        /// Ay başı ve ay sonu değeri kayıtlı fiyatlardan (o güne kadarki son fiyat). Ay içinde ve
        /// öncesinde birikim yoksa `nil`. `now` ay içindeyse ay sonu yerine `now` kullanılır.
        public static func compute(trades: [Trade], prices: [AssetCode: [(date: Date, price: Decimal)]],
                                   month: LedgerMonth, now: Date, calendar: Calendar,
                                   cpi: RealReturn.CPITable? = nil) -> Savings? {
            let interval = month.interval(in: calendar)
            let startDay = interval.start.addingTimeInterval(-1)
            let endDay = min(interval.end, now).addingTimeInterval(-1)
            let inMonth = trades.filter { $0.date >= interval.start && $0.date < interval.end }
            let start = PortfolioHistory.series(trades: trades, prices: prices, days: [startDay]).first?.value ?? 0
            guard let end = PortfolioHistory.series(trades: trades, prices: prices, days: [endDay]).first?.value,
                  start > 0 || !inMonth.isEmpty else { return nil }
            let contributions = inMonth.reduce(Decimal(0)) {
                $0 + ($1.side == .buy ? $1.grossCost : -($1.quantity * $1.unitPrice - $1.fee))
            }
            return Savings(startValue: start, endValue: end, contributions: contributions,
                           inflation: cpi.flatMap { MonthlyReport.inflation(for: month, cpi: $0) })
        }
    }

    /// Başa yazılan tek cümle; metni uygulama kurar.
    public enum Headline: Hashable, Sendable {
        /// Önceki aya göre belirgin değişim, ve değişimin çoğunun geldiği kategori (aynı yöndeyse).
        case changed(expense: Decimal, ratio: Decimal, driver: CategoryChange?)
        /// Önceki ayla neredeyse aynı (±%3) ya da önceki ay verisi yok.
        case steady(expense: Decimal, hasPrevious: Bool)
        /// Gider geliri geçti.
        case overspent(by: Decimal)
    }

    public var month: LedgerMonth
    public var income: Decimal
    public var expense: Decimal
    public var net: Decimal { income - expense }
    public var previousExpense: Decimal?
    /// Önceki aya göre gider değişimi.
    public var change: Decimal?
    /// Önceki (en çok) üç ayın ortalama gideri; o aylarda hiç gider yoksa `nil`.
    public var averageExpense: Decimal?
    public var averageMonths: Int
    public var changeFromAverage: Decimal? {
        guard let averageExpense, averageExpense > 0 else { return nil }
        return (expense - averageExpense) / averageExpense
    }
    /// Mutlak farkı en büyük üç kategori (₺500'den küçük farklar hariç).
    public var categoryChanges: [CategoryChange]
    public var topExpenses: [LedgerEntry]
    public var topMerchant: MerchantVisit?
    public var budget: BudgetLine?
    /// Limiti aşan kategori bütçeleri, en çok aşan önce.
    public var overBudget: [BudgetLine]
    public var savings: Savings?
    public var headline: Headline
    /// Raporu dolduracak kadar kayıt var mı (en az bir gider).
    public var hasContent: Bool { expense > 0 }

    static let minimumCategoryDifference: Decimal = 500
    static let steadyBand: Decimal = 0.03

    public init(entries: [LedgerEntry], month: LedgerMonth, currency: CurrencyCode = .TRY, calendar: Calendar,
                budgets: [BudgetLine] = [], savings: Savings? = nil) {
        let current = MonthlySummary(entries: entries, month: month, currency: currency, calendar: calendar)
        let previous = MonthlySummary(entries: entries, month: month.previous, currency: currency, calendar: calendar)
        self.month = month
        income = current.income.amount
        expense = current.expense.amount
        let hasPrevious = previous.entryCount > 0
        previousExpense = hasPrevious ? previous.expense.amount : nil
        change = hasPrevious ? current.expenseChange(from: previous) : nil

        var pastMonths: [Decimal] = []
        var cursor = month.previous
        for _ in 0..<3 {
            let summary = MonthlySummary(entries: entries, month: cursor, currency: currency, calendar: calendar)
            if summary.expense.amount > 0 { pastMonths.append(summary.expense.amount) }
            cursor = cursor.previous
        }
        averageMonths = pastMonths.count
        averageExpense = pastMonths.isEmpty ? nil : pastMonths.reduce(0, +) / Decimal(pastMonths.count)

        // Kategori farkları
        let now = Dictionary(current.expenseByCategory.map { ($0.categoryID, $0.total.amount) }, uniquingKeysWith: +)
        let before = Dictionary(previous.expenseByCategory.map { ($0.categoryID, $0.total.amount) }, uniquingKeysWith: +)
        let changes = Set(now.keys).union(before.keys).map {
            CategoryChange(categoryID: $0, current: now[$0] ?? 0, previous: before[$0] ?? 0)
        }
        categoryChanges = hasPrevious
            ? changes
                .filter { abs($0.difference) >= Self.minimumCategoryDifference }
                .sorted { lhs, rhs in
                    abs(lhs.difference) != abs(rhs.difference)
                        ? abs(lhs.difference) > abs(rhs.difference)
                        : (lhs.categoryID?.uuidString ?? "") < (rhs.categoryID?.uuidString ?? "")
                }
                .prefix(3).map { $0 }
            : []

        // En büyük harcamalar ve en sık satıcı
        let interval = month.interval(in: calendar)
        let monthExpenses = entries.filter {
            $0.status == .posted && $0.kind == .expense && $0.amount.currency == currency
                && $0.date >= interval.start && $0.date < interval.end
        }
        topExpenses = monthExpenses
            .sorted { $0.amount.amount != $1.amount.amount ? $0.amount.amount > $1.amount.amount : $0.date < $1.date }
            .prefix(3).map { $0 }
        var visits: [String: MerchantVisit] = [:]
        for entry in monthExpenses {
            guard let name = entry.merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            let key = MerchantKey.normalize(name)
            guard !key.isEmpty else { continue }
            var visit = visits[key] ?? MerchantVisit(name: name, count: 0, total: 0)
            visit.count += 1
            visit.total += entry.amount.amount
            visits[key] = visit
        }
        topMerchant = visits.values
            .filter { $0.count >= 2 }
            .max { ($0.count, $0.total) < ($1.count, $1.total) }

        budget = budgets.first { $0.categoryID == nil }
        overBudget = budgets.filter { $0.categoryID != nil && $0.spent > $0.limit }.sorted { $0.overrun > $1.overrun }
        self.savings = savings

        // Başlık
        if income > 0, expense > income {
            headline = .overspent(by: expense - income)
        } else if let change, abs(change) >= Self.steadyBand {
            let up = change > 0
            let driver = categoryChanges.first { up ? $0.difference > 0 : $0.difference < 0 }
            headline = .changed(expense: expense, ratio: change, driver: driver)
        } else {
            headline = .steady(expense: expense, hasPrevious: hasPrevious)
        }
    }

    /// Ayın TÜFE değişimi: (bu ay / önceki ay) − 1. Biri eksikse `nil`.
    public static func inflation(for month: LedgerMonth, cpi: RealReturn.CPITable) -> Decimal? {
        guard let now = cpi.index[month], let before = cpi.index[month.previous], before > 0 else { return nil }
        return now / before - 1
    }
}
