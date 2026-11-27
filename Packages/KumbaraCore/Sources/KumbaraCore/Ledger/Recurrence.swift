import Foundation

/// Tekrar sıklığı (specs/08 §2.1). Ayın olmayan günü (31 Şubat) ayın son gününe düşer;
/// tatil/hafta sonu kaydırması yoktur.
public enum RecurrenceFrequency: Hashable, Sendable {
    /// Her `interval` ayda bir, ayın `day`. günü (1…31).
    case monthly(day: Int, interval: Int = 1)
    /// Her hafta, `weekday` (1 = Pazar … 7 = Cumartesi, `Calendar` ile aynı).
    case weekly(weekday: Int)
    /// Her yıl `month`/`day`.
    case yearly(month: Int, day: Int)

    /// Kanonik metin: `m:31:1`, `w:2`, `y:3:15`.
    public var canonical: String {
        switch self {
        case .monthly(let day, let interval): "m:\(day):\(interval)"
        case .weekly(let weekday): "w:\(weekday)"
        case .yearly(let month, let day): "y:\(month):\(day)"
        }
    }

    public init?(canonical: String) {
        let parts = canonical.split(separator: ":").map(String.init)
        guard let tag = parts.first else { return nil }
        let numbers = parts.dropFirst().compactMap { Int($0) }
        switch (tag, numbers.count) {
        case ("m", 2) where (1...31).contains(numbers[0]) && numbers[1] >= 1:
            self = .monthly(day: numbers[0], interval: numbers[1])
        case ("w", 1) where (1...7).contains(numbers[0]):
            self = .weekly(weekday: numbers[0])
        case ("y", 2) where (1...12).contains(numbers[0]) && (1...31).contains(numbers[1]):
            self = .yearly(month: numbers[0], day: numbers[1])
        default:
            return nil
        }
    }

    /// Başlangıç tarihinden türetilen varsayılan: aynı gün, her ay.
    public static func monthly(like date: Date, calendar: Calendar) -> RecurrenceFrequency {
        .monthly(day: calendar.component(.day, from: date))
    }
}

/// Bir tekrar kuralının vade hesabı (specs/08 §2.2). Saf; taslağı Data katmanı üretir.
public struct RecurrenceSchedule: Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    /// İlk vadenin aranacağı gün (dahil).
    public var start: Date
    /// Bu günden sonra vade yok (dahil).
    public var end: Date?
    /// En fazla bu kadar vade (ör. 12 taksit gibi sınırlı abonelik).
    public var maxCount: Int?

    public init(frequency: RecurrenceFrequency, start: Date, end: Date? = nil, maxCount: Int? = nil) {
        self.frequency = frequency
        self.start = start
        self.end = end
        self.maxCount = maxCount
    }

    /// `start`tan itibaren sıradaki vadeler; her biri günün başlangıcı.
    public func occurrences(calendar: Calendar, limit: Int = 500) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let last = end.map { calendar.startOfDay(for: $0) }
        let cap = min(limit, maxCount ?? limit)
        var guardCounter = 0
        while result.count < cap, guardCounter < limit * 2 {
            guardCounter += 1
            guard let next = nextDue(onOrAfter: cursor, calendar: calendar) else { break }
            if let last, next > last { break }
            result.append(next)
            guard let after = calendar.date(byAdding: .day, value: 1, to: next) else { break }
            cursor = after
        }
        return result
    }

    /// `through` gününe kadar (dahil) olan ve `after` gününden sonraki vadeler: üretilecek taslaklar.
    /// `after == nil`: hiç taslak üretilmemiş.
    public func due(after: Date?, through now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let floor = after.map { calendar.startOfDay(for: $0) }
        return occurrences(calendar: calendar).prefix { $0 <= today }.filter { floor == nil || $0 > floor! }
    }

    /// Bugünden sonraki ilk vade (hatırlatma için).
    public func nextDue(after now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        return occurrences(calendar: calendar).first { $0 > today }
    }

    private func nextDue(onOrAfter day: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .monthly(let wanted, let interval):
            let startMonth = LedgerMonth(containing: start, calendar: calendar)
            var month = LedgerMonth(containing: day, calendar: calendar)
            // `interval` ayda bir: başlangıç ayından itibaren sayılır.
            for _ in 0..<(interval * 24) {
                let offset = (month.year - startMonth.year) * 12 + (month.month - startMonth.month)
                if offset >= 0, offset % interval == 0, let date = Self.clamped(day: wanted, in: month, calendar: calendar), date >= day {
                    return date
                }
                month = month.next
            }
            return nil
        case .weekly(let weekday):
            for step in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: step, to: day) else { continue }
                if calendar.component(.weekday, from: date) == weekday { return date }
            }
            return nil
        case .yearly(let wantedMonth, let wantedDay):
            let year = calendar.component(.year, from: day)
            for candidateYear in year...(year + 1) {
                if let date = Self.clamped(day: wantedDay, in: LedgerMonth(year: candidateYear, month: wantedMonth), calendar: calendar),
                   date >= day {
                    return date
                }
            }
            return nil
        }
    }

    /// Ayın `day`. günü; ay daha kısaysa son günü.
    static func clamped(day: Int, in month: LedgerMonth, calendar: Calendar) -> Date? {
        let interval = month.interval(in: calendar)
        let length = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 28
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: min(day, length)))
    }
}
