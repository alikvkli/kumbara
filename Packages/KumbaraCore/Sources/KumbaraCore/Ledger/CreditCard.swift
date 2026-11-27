import Foundation

/// Kredi kartı ekstre dönemi (REQ-L8, specs/08 §3.1).
/// Dönem = önceki kesimin ertesi günü … kesim günü (dahil). Kesim günü ayda yoksa ayın son günü.
public struct StatementPeriod: Hashable, Sendable {
    /// Dönemin ilk günü (günün başlangıcı).
    public var start: Date
    /// Kesim günü (günün başlangıcı); dönem bu günün sonunda kapanır.
    public var closing: Date
    /// Son ödeme günü.
    public var due: Date

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day <= closing
    }

    /// `date`i içeren dönem. `dueDay` yoksa kesimden 10 gün sonra.
    public static func containing(_ date: Date, statementDay: Int, dueDay: Int? = nil, calendar: Calendar) -> StatementPeriod {
        let day = calendar.startOfDay(for: date)
        let month = LedgerMonth(containing: day, calendar: calendar)
        let thisClosing = closing(in: month, statementDay: statementDay, calendar: calendar)
        let closingDate = day <= thisClosing ? thisClosing : closing(in: month.next, statementDay: statementDay, calendar: calendar)
        let previousClosing = closing(in: LedgerMonth(containing: closingDate, calendar: calendar).previous,
                                      statementDay: statementDay, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: 1, to: previousClosing)!
        return StatementPeriod(start: start, closing: closingDate, due: dueDate(after: closingDate, dueDay: dueDay, calendar: calendar))
    }

    public func previous(statementDay: Int, dueDay: Int?, calendar: Calendar) -> StatementPeriod {
        StatementPeriod.containing(calendar.date(byAdding: .day, value: -1, to: start)!, statementDay: statementDay,
                                   dueDay: dueDay, calendar: calendar)
    }

    static func closing(in month: LedgerMonth, statementDay: Int, calendar: Calendar) -> Date {
        RecurrenceSchedule.clamped(day: statementDay, in: month, calendar: calendar)!
    }

    /// Kesimden sonraki ilk `dueDay` (ayda yoksa son gün); `dueDay` yoksa kesim + 10 gün.
    static func dueDate(after closing: Date, dueDay: Int?, calendar: Calendar) -> Date {
        guard let dueDay else { return calendar.date(byAdding: .day, value: 10, to: closing)! }
        let month = LedgerMonth(containing: closing, calendar: calendar)
        let sameMonth = RecurrenceSchedule.clamped(day: dueDay, in: month, calendar: calendar)!
        return sameMonth > closing ? sameMonth : RecurrenceSchedule.clamped(day: dueDay, in: month.next, calendar: calendar)!
    }
}

/// Kart ekranı özeti (specs/08 §3.1). Tutarlar kartın para biriminde, pozitif büyüklük.
public struct CardStatement: Hashable, Sendable {
    public var current: StatementPeriod
    public var last: StatementPeriod
    /// Açık dönemin harcaması (iadeler düşülmüş).
    public var currentSpending: Money
    /// Son kesilen ekstrenin tutarı.
    public var lastStatement: Money
    /// Son kesimden bu yana karta yapılan ödemeler (transfer).
    public var paidSinceClosing: Money
    /// Gelecek dönemlere planlanmış taksitlerin toplamı.
    public var upcomingInstallments: Money

    /// Son ekstreden kalan borç.
    public var remainingDue: Money {
        let value = lastStatement.amount - paidSinceClosing.amount
        return Money(max(value, 0), lastStatement.currency)
    }

    public init(entries: [LedgerEntry], cardID: UUID, currency: CurrencyCode, statementDay: Int, dueDay: Int?,
                now: Date, calendar: Calendar) {
        let current = StatementPeriod.containing(now, statementDay: statementDay, dueDay: dueDay, calendar: calendar)
        let last = current.previous(statementDay: statementDay, dueDay: dueDay, calendar: calendar)
        func spending(in period: StatementPeriod) -> Decimal {
            entries.reduce(Decimal(0)) { sum, entry in
                guard entry.status == .posted, entry.accountID == cardID, entry.kind != .transfer,
                      period.contains(entry.date, calendar: calendar) else { return sum }
                return sum + (entry.kind == .expense ? entry.amount.amount : -entry.amount.amount)
            }
        }
        let paid = entries.reduce(Decimal(0)) { sum, entry in
            guard entry.status == .posted, entry.kind == .transfer, entry.toAccountID == cardID,
                  calendar.startOfDay(for: entry.date) > last.closing else { return sum }
            return sum + entry.amount.amount
        }
        let upcoming = entries.reduce(Decimal(0)) { sum, entry in
            entry.status == .planned && entry.accountID == cardID ? sum + entry.amount.amount : sum
        }
        self.current = current
        self.last = last
        self.currentSpending = Money(max(spending(in: current), 0), currency)
        self.lastStatement = Money(max(spending(in: last), 0), currency)
        self.paidSinceClosing = Money(paid, currency)
        self.upcomingInstallments = Money(upcoming, currency)
    }
}

/// Taksit planı (REQ-L9, specs/08 §3.2).
public enum Installments {
    /// `total / count`; kuruş farkı ilk taksite (₺1.000 / 3 = 333,34 + 333,33 + 333,33).
    public static func split(_ total: Decimal, count: Int) -> [Decimal] {
        guard count > 1 else { return [total] }
        var base = total / Decimal(count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &base, 2, .down)
        let first = total - rounded * Decimal(count - 1)
        return [first] + Array(repeating: rounded, count: count - 1)
    }

    /// Taksit `k` (0'dan) alım gününden `k` ay sonra; ayda o gün yoksa ayın son günü. Böylece her taksit
    /// bir sonraki ekstre dönemine düşer (kesim 15, alım 20 Kasım → 15 Aralık ekstresi, 15 Ocak, …).
    public static func dates(purchase: Date, count: Int, calendar: Calendar) -> [Date] {
        let day = calendar.component(.day, from: purchase)
        let time = calendar.dateComponents([.hour, .minute], from: purchase)
        let month = LedgerMonth(containing: purchase, calendar: calendar)
        return (0..<max(count, 1)).map { k in
            var target = month
            for _ in 0..<k { target = target.next }
            let date = RecurrenceSchedule.clamped(day: day, in: target, calendar: calendar)!
            return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: date) ?? date
        }
    }

    /// Kartlarda sunulan taksit seçenekleri.
    public static let choices = [1, 2, 3, 4, 5, 6, 9, 12, 18, 24, 36]
}
