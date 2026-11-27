import Foundation

/// Takvim ayı (yerel takvime göre).
public struct LedgerMonth: Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month))
        self.year = year
        self.month = month
    }

    public init(containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year!, month: parts.month!)
    }

    public func interval(in calendar: Calendar) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    public var previous: LedgerMonth {
        month == 1 ? LedgerMonth(year: year - 1, month: 12) : LedgerMonth(year: year, month: month - 1)
    }

    public var next: LedgerMonth {
        month == 12 ? LedgerMonth(year: year + 1, month: 1) : LedgerMonth(year: year, month: month + 1)
    }

    public static func < (lhs: LedgerMonth, rhs: LedgerMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// Bir ayın gelir/gider özeti, tek para birimi için (REQ-B3).
///
/// Kurallar: yalnız `posted` kayıtlar (C5), transferler hariç (REQ-L3),
/// yalnız `currency` cinsinden kayıtlar — diğer para birimleri `otherCurrencies`'de ayrıca sayılır
/// (kurla çevrim M2'de gelir).
public struct MonthlySummary: Hashable, Sendable {
    public struct CategoryTotal: Hashable, Sendable {
        public var categoryID: UUID?
        public var total: Money
        /// Toplam gidere oranı (0…1).
        public var share: Decimal
    }

    public var month: LedgerMonth
    public var currency: CurrencyCode
    public var income: Money
    public var expense: Money
    public var net: Money { income - expense }
    /// Gider kategorileri, büyükten küçüğe. Kategorisiz giderler `categoryID == nil`.
    public var expenseByCategory: [CategoryTotal]
    public var entryCount: Int
    /// Bu ayda başka para birimiyle kayıt varsa o birimler.
    public var otherCurrencies: Set<CurrencyCode>

    public init(entries: some Sequence<LedgerEntry>, month: LedgerMonth, currency: CurrencyCode, calendar: Calendar) {
        let interval = month.interval(in: calendar)
        var income = Money.zero(currency)
        var expense = Money.zero(currency)
        var byCategory: [UUID?: Money] = [:]
        var count = 0
        var others: Set<CurrencyCode> = []

        for entry in entries where entry.status == .posted && entry.kind != .transfer
            && entry.date >= interval.start && entry.date < interval.end {
            guard entry.amount.currency == currency else {
                others.insert(entry.amount.currency)
                continue
            }
            count += 1
            if entry.kind == .income {
                income += entry.amount
            } else {
                expense += entry.amount
                byCategory[entry.categoryID, default: .zero(currency)] += entry.amount
            }
        }

        self.month = month
        self.currency = currency
        self.income = income
        self.expense = expense
        self.entryCount = count
        self.otherCurrencies = others
        self.expenseByCategory = byCategory
            .map { id, total in
                CategoryTotal(categoryID: id, total: total,
                              share: expense.isZero ? 0 : total.amount / expense.amount)
            }
            .sorted { lhs, rhs in
                lhs.total.amount != rhs.total.amount
                    ? lhs.total.amount > rhs.total.amount
                    : (lhs.categoryID?.uuidString ?? "") < (rhs.categoryID?.uuidString ?? "")
            }
    }

    /// Önceki aya göre gider farkı oranı; önceki ay gideri yoksa `nil`.
    public func expenseChange(from previous: MonthlySummary) -> Decimal? {
        guard !previous.expense.isZero else { return nil }
        return (expense.amount - previous.expense.amount) / previous.expense.amount
    }
}

/// "Bu ay günlük ne harcayabilirim" (REQ-B4).
///
/// `remaining` (bütçe kalanı; bütçe yoksa ayın net tutarı) bugün dahil kalan güne bölünür.
/// Kalan ≤ 0 ise sıfır. `today` ay dışındaysa `nil`.
public struct DailyAllowance: Hashable, Sendable {
    public var remainingDays: Int
    public var perDay: Money

    public init?(remaining: Money, month: LedgerMonth, today: Date, calendar: Calendar) {
        let interval = month.interval(in: calendar)
        guard today >= interval.start, today < interval.end else { return nil }
        let startOfToday = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: startOfToday, to: interval.end).day ?? 1
        remainingDays = max(days, 1)
        perDay = remaining.isNegative || remaining.isZero
            ? .zero(remaining.currency)
            : remaining / Decimal(remainingDays)
    }
}
