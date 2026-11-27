import Foundation

/// "Alabilir miyim?" (REQ-I3, specs/10 §3). Kayıt oluşturmaz; bir alımın bütçeye, karta ve hedeflere
/// etkisini senaryolar hâlinde hesaplar. Taksit kuralları 08 §3.2 ile aynıdır: ilk taksit alım ayına,
/// sonrakiler birer ay arayla düşer (`Installments`).
public enum PurchasePlanner {
    public struct Context: Hashable, Sendable {
        public var today: Date
        /// Bu ay kalan (genel bütçenin kalanı ya da ayın neti).
        public var remaining: Decimal
        /// Genel bütçe var mı (metin için).
        public var hasBudget: Bool
        /// Son tam aylardaki ortalama net birikim (gelir − gider); en az 3 ay veri yoksa `nil` (K6).
        public var monthlySaving: Decimal?

        public init(today: Date, remaining: Decimal, hasBudget: Bool, monthlySaving: Decimal?) {
            self.today = today
            self.remaining = remaining
            self.hasBudget = hasBudget
            self.monthlySaving = monthlySaving
        }
    }

    public struct Card: Hashable, Sendable {
        public var statementDay: Int
        public var dueDay: Int?
        /// Tanımlıysa kalan limit (bugünkü borç düşülmüş).
        public var availableLimit: Decimal?

        public init(statementDay: Int, dueDay: Int?, availableLimit: Decimal? = nil) {
            self.statementDay = statementDay
            self.dueDay = dueDay
            self.availableLimit = availableLimit
        }
    }

    public struct Goal: Hashable, Sendable {
        public var name: String
        /// TL cinsinden kalan.
        public var remaining: Decimal

        public init(name: String, remaining: Decimal) {
            self.name = name
            self.remaining = remaining
        }
    }

    public struct Scenario: Hashable, Sendable, Identifiable {
        public var id: Int { count }
        /// 1 = peşin.
        public var count: Int
        public var installment: Decimal
        public struct Share: Hashable, Sendable {
            public var month: LedgerMonth
            public var amount: Decimal
        }
        /// Hangi ayın bütçesine ne kadar girer.
        public var schedule: [Share]
        public var thisMonth: Decimal
        /// Bu alımdan sonra bu ay kalan (eksi olabilir).
        public var remainingAfter: Decimal
        /// Bugün dahil kalan güne bölünmüş günlük hak; önce / sonra.
        public var perDayBefore: Decimal
        public var perDayAfter: Decimal
        /// Kartla: ilk taksitin düştüğü ekstrenin son ödeme günü.
        public var firstDue: Date?
        /// Kart limiti yetmiyor.
        public var exceedsLimit: Bool

        public var shortfall: Decimal { max(-remainingAfter, 0) }
    }

    public struct GoalImpact: Hashable, Sendable {
        public var name: String
        public var monthsBefore: Int
        public var monthsAfter: Int
        public var delay: Int { monthsAfter - monthsBefore }
    }

    public static func scenarios(amount: Decimal, counts: [Int], context: Context, card: Card?,
                                 calendar: Calendar) -> [Scenario] {
        guard amount > 0 else { return [] }
        let month = LedgerMonth(containing: context.today, calendar: calendar)
        let interval = month.interval(in: calendar)
        let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: context.today), to: interval.end).day ?? 1, 1)
        func perDay(_ value: Decimal) -> Decimal { value > 0 ? (value / Decimal(days)).rounded(scale: 0) : 0 }

        return counts.filter { $0 >= 1 }.map { count in
            let parts = Installments.split(amount, count: count)
            let dates = Installments.dates(purchase: context.today, count: count, calendar: calendar)
            var byMonth: [LedgerMonth: Decimal] = [:]
            for (part, date) in zip(parts, dates) { byMonth[LedgerMonth(containing: date, calendar: calendar), default: 0] += part }
            let schedule = byMonth.sorted { $0.key < $1.key }.map { Scenario.Share(month: $0.key, amount: $0.value) }
            let thisMonth = byMonth[month] ?? 0
            let after = context.remaining - thisMonth
            let firstDue = card.map {
                StatementPeriod.containing(dates[0], statementDay: $0.statementDay, dueDay: $0.dueDay, calendar: calendar).due
            }
            return Scenario(count: count, installment: parts.last ?? amount, schedule: schedule, thisMonth: thisMonth,
                            remainingAfter: after, perDayBefore: perDay(context.remaining), perDayAfter: perDay(after),
                            firstDue: firstDue, exceedsLimit: card?.availableLimit.map { amount > $0 } ?? false)
        }
    }

    /// Birikim hızı bu tutar kadar düşerse hedefe kaç ay daha geç varılır. Hız yoksa ya da ≤ 0 ise `nil`.
    public static func goalImpact(amount: Decimal, goal: Goal, monthlySaving: Decimal?) -> GoalImpact? {
        guard let rate = monthlySaving, rate > 0, goal.remaining > 0 else { return nil }
        func months(_ value: Decimal) -> Int {
            var quotient = value / rate
            var rounded = Decimal()
            NSDecimalRound(&rounded, &quotient, 0, .up)
            return NSDecimalNumber(decimal: rounded).intValue
        }
        return GoalImpact(name: goal.name, monthsBefore: months(goal.remaining), monthsAfter: months(goal.remaining + amount))
    }

    /// Son tam aylardaki ortalama net birikim; gideri ya da geliri olan en az 3 ay gerekir (K6).
    public static func monthlySaving(entries: [LedgerEntry], before month: LedgerMonth, currency: CurrencyCode = .TRY,
                                     calendar: Calendar, months: Int = 3) -> Decimal? {
        var nets: [Decimal] = []
        var cursor = month.previous
        for _ in 0..<months {
            let summary = MonthlySummary(entries: entries, month: cursor, currency: currency, calendar: calendar)
            if summary.entryCount > 0 { nets.append(summary.net.amount) }
            cursor = cursor.previous
        }
        guard nets.count >= months else { return nil }
        return nets.reduce(0, +) / Decimal(nets.count)
    }
}
