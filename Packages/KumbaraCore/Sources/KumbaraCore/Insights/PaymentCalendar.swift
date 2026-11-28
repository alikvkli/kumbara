import Foundation

/// Gelecekteki bilinen ödemeler (REQ-I5, specs/10 §5). Kayıt oluşturmaz; yalnız gösterir.
///
/// Çift sayım kuralı: kartla ödenen tekrarlar ve abonelikler kart ekstresinin içindedir; çağıran
/// taraf bunları ayrı kalem olarak vermez, kart son ödemesi tek kalem olarak gelir.
public struct UpcomingPayment: Hashable, Sendable, Identifiable {
    public enum Source: Hashable, Sendable {
        case recurring(UUID)
        case card(UUID)
        case subscription(String)
        case person(UUID)
        case plan(UUID)
        case loan(UUID)
    }

    public var id: String
    /// Günün başlangıcı.
    public var date: Date
    /// Pozitif büyüklük.
    public var amount: Decimal
    public var isIncome: Bool
    public var title: String
    public var source: Source
    /// Abonelik tahmini gibi geçmişten çıkarılan kalem.
    public var isEstimate: Bool
    /// Dönemi süren kart ekstresi: tutar "şu ana kadar".
    public var isPartial: Bool

    public init(id: String, date: Date, amount: Decimal, isIncome: Bool = false, title: String, source: Source,
                isEstimate: Bool = false, isPartial: Bool = false) {
        self.id = id
        self.date = date
        self.amount = amount
        self.isIncome = isIncome
        self.title = title
        self.source = source
        self.isEstimate = isEstimate
        self.isPartial = isPartial
    }
}

public enum PaymentCalendar {
    /// Bir tekrar kuralının `from` (dahil) … `through` (dahil) arasındaki vadeleri. `lastDue`: taslağı
    /// zaten üretilmiş son vade (o ve öncesi tekrar gösterilmez; taslak "onay bekliyor" listesindedir).
    public static func recurring(id: UUID, title: String, amount: Decimal, isIncome: Bool, schedule: RecurrenceSchedule,
                                 lastDue: Date?, from: Date, through: Date, calendar: Calendar) -> [UpcomingPayment] {
        guard amount > 0 else { return [] }
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        let floor = lastDue.map { calendar.startOfDay(for: $0) }
        return schedule.occurrences(calendar: calendar)
            .prefix { $0 <= end }
            .filter { $0 >= start && (floor == nil || $0 > floor!) }
            .map { day in
                UpcomingPayment(id: "recurring:\(id.uuidString):\(day.timeIntervalSince1970)", date: day, amount: amount,
                                isIncome: isIncome, title: title, source: .recurring(id))
            }
    }

    /// Kart son ödemeleri: kesilmiş ekstreden kalan borç (son ödeme günü bugün ya da sonra ise) ve
    /// süren dönemin şu ana kadarki harcaması (bir sonraki son ödeme gününde).
    public static func card(id: UUID, name: String, statement: CardStatement, from: Date, through: Date,
                            calendar: Calendar) -> [UpcomingPayment] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        var result: [UpcomingPayment] = []
        let lastDue = calendar.startOfDay(for: statement.last.due)
        if statement.remainingDue.amount > 0, lastDue >= start, lastDue <= end {
            result.append(UpcomingPayment(id: "card:\(id.uuidString):last", date: lastDue, amount: statement.remainingDue.amount,
                                          title: name, source: .card(id)))
        }
        let currentDue = calendar.startOfDay(for: statement.current.due)
        if statement.currentSpending.amount > 0, currentDue >= start, currentDue <= end {
            result.append(UpcomingPayment(id: "card:\(id.uuidString):current", date: currentDue,
                                          amount: statement.currentSpending.amount, title: name, source: .card(id),
                                          isPartial: true))
        }
        return result
    }

    /// Aboneliklerin tahmini vadeleri; görünmeyen (kaçırılmış) ve kurala bağlı olanlar hariç.
    public static func subscriptions(_ subscriptions: [SubscriptionDetector.Subscription], from: Date, through: Date,
                                     calendar: Calendar) -> [UpcomingPayment] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        var result: [UpcomingPayment] = []
        for subscription in subscriptions where !subscription.isMissed && !subscription.isTracked {
            var due = calendar.startOfDay(for: subscription.nextDue)
            var step = 1
            while due <= end, step < 40 {
                if due >= start {
                    result.append(UpcomingPayment(id: "subscription:\(subscription.merchantKey):\(due.timeIntervalSince1970)",
                                                  date: due, amount: subscription.lastAmount, title: subscription.name,
                                                  source: .subscription(subscription.merchantKey), isEstimate: true))
                }
                guard let next = calendar.date(byAdding: subscription.cadence == .monthly ? .month : .year, value: step,
                                               to: calendar.startOfDay(for: subscription.nextDue)) else { break }
                due = next
                step += 1
            }
        }
        return result
    }

    /// Kredinin ödenmemiş taksitleri (specs/13). İlk `paidCount` taksit ödenmiş sayılır; gecikmiş taksit
    /// kredi ekranında gösterilir, takvimde kendi gününde kalır.
    public static func loan(id: UUID, title: String, terms: LoanTerms, paidCount: Int, from: Date, through: Date,
                            calendar: Calendar) -> [UpcomingPayment] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        return LoanMath.schedule(terms, calendar: calendar)
            .dropFirst(max(paidCount, 0))
            .filter { $0.due >= start && $0.due <= end }
            .map { row in
                UpcomingPayment(id: "loan:\(id.uuidString):\(row.number)", date: row.due, amount: row.payment,
                                title: title, source: .loan(id))
            }
    }

    /// Belirli bir pencerenin özeti.
    public struct Window: Hashable, Sendable {
        public var items: [UpcomingPayment]
        public var outgoing: Decimal
        public var incoming: Decimal
    }

    public static func window(_ items: [UpcomingPayment], from: Date, days: Int, calendar: Calendar) -> Window {
        let start = calendar.startOfDay(for: from)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let inside = sorted(items.filter { $0.date >= start && $0.date < end })
        return Window(items: inside,
                      outgoing: inside.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                      incoming: inside.filter(\.isIncome).reduce(0) { $0 + $1.amount })
    }

    /// Tarih, sonra gelir önce, sonra büyük tutar önce.
    public static func sorted(_ items: [UpcomingPayment]) -> [UpcomingPayment] {
        items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.isIncome != rhs.isIncome { return lhs.isIncome }
            return lhs.amount != rhs.amount ? lhs.amount > rhs.amount : lhs.id < rhs.id
        }
    }

    /// Bugünden sonraki ilk gelir (ör. maaş); kaç gün kaldığıyla.
    public static func nextIncome(_ items: [UpcomingPayment], from: Date, calendar: Calendar) -> (payment: UpcomingPayment, days: Int)? {
        let start = calendar.startOfDay(for: from)
        guard let income = sorted(items).first(where: { $0.isIncome && $0.date >= start }) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: income.date).day ?? 0
        return (income, days)
    }

    /// Başlangıç bakiyesine pencere içindeki gelir ve giderler sırayla uygulanır; en düşük nokta ve son.
    public static func balance(starting: Decimal, items: [UpcomingPayment]) -> (lowest: Decimal, end: Decimal, lowestDate: Date?) {
        var balance = starting
        var lowest = starting
        var lowestDate: Date?
        for item in sorted(items) {
            balance += item.isIncome ? item.amount : -item.amount
            if balance < lowest {
                lowest = balance
                lowestDate = item.date
            }
        }
        return (lowest, balance, lowestDate)
    }
}
