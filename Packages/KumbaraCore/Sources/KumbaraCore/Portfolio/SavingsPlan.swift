import Foundation

/// Düzenli alım planı (REQ-I7, specs/10 §7): "Her ayın 15'inde 2 gram altın", "her maaşta ₺5.000'lik çeyrek".
/// Plan kayıt üretmez; vadesinde hatırlatır ve alım formunu doldurur (C5).
public struct SavingsPlanRule: Hashable, Sendable, Identifiable {
    public enum Target: Hashable, Sendable {
        case quantity(Decimal)
        /// TL tutarı; miktar o günkü satış fiyatından hesaplanır.
        case amount(Decimal)
    }

    public enum Trigger: Hashable, Sendable {
        case schedule(RecurrenceFrequency)
        /// Maaş kategorisinde gelir onaylanınca.
        case salary
    }

    public var id: UUID
    public var asset: AssetCode
    public var target: Target
    public var trigger: Trigger
    public var start: Date
    public var goalID: UUID?

    public init(id: UUID = UUID(), asset: AssetCode, target: Target, trigger: Trigger, start: Date, goalID: UUID? = nil) {
        self.id = id
        self.asset = asset
        self.target = target
        self.trigger = trigger
        self.start = start
        self.goalID = goalID
    }

    /// Kanonik metin: `q:2`, `a:5000`; tetik `s:m:15:1`, `salary`.
    public var targetCanonical: String {
        switch target {
        case let .quantity(value): "q:\(value.canonicalString)"
        case let .amount(value): "a:\(value.canonicalString)"
        }
    }

    public var triggerCanonical: String {
        switch trigger {
        case let .schedule(frequency): "s:\(frequency.canonical)"
        case .salary: "salary"
        }
    }

    public static func target(canonical: String) -> Target? {
        let parts = canonical.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let value = Decimal(canonical: parts[1]), value > 0 else { return nil }
        switch parts[0] {
        case "q": return .quantity(value)
        case "a": return .amount(value)
        default: return nil
        }
    }

    public static func trigger(canonical: String) -> Trigger? {
        if canonical == "salary" { return .salary }
        guard canonical.hasPrefix("s:"), let frequency = RecurrenceFrequency(canonical: String(canonical.dropFirst(2))) else { return nil }
        return .schedule(frequency)
    }

    /// Takvimli planın vadeleri (`start` dahil). Maaş tetiklisinde vade, maaş günleridir (dışarıdan verilir).
    public var schedule: RecurrenceSchedule? {
        guard case let .schedule(frequency) = trigger else { return nil }
        return RecurrenceSchedule(frequency: frequency, start: start)
    }

    /// O günkü fiyatla alınacak miktar. Adetli varlıkta aşağı yuvarlanır (yarım çeyrek alınmaz); gramda 2 basamak.
    public func quantity(at unitPrice: Decimal) -> Decimal? {
        switch target {
        case let .quantity(value): return value
        case let .amount(value):
            guard unitPrice > 0 else { return nil }
            var raw = value / unitPrice
            var rounded = Decimal()
            NSDecimalRound(&rounded, &raw, asset.unit == .piece ? 0 : 2, .down)
            return rounded > 0 ? rounded : nil
        }
    }
}

/// Planın gidişi (specs/10 §7): uyum, ortalama maliyet, dürüst karşılaştırma.
public struct SavingsPlanProgress: Hashable, Sendable {
    /// Bugüne kadarki vadeler (bugün dahil).
    public var dueCount: Int
    /// Alım yapılmış vadeler.
    public var keptCount: Int
    /// Planın başlangıcından beri bu varlığın alımları.
    public var buys: [Trade]
    public var quantity: Decimal { buys.reduce(0) { $0 + $1.quantity } }
    public var spent: Decimal { buys.reduce(0) { $0 + $1.grossCost } }
    public var averageCost: Decimal? { quantity > 0 ? spent / quantity : nil }
    /// Sıradaki vade (takvimli planda).
    public var nextDue: Date?

    /// Alımlar bugün bozdurulsa.
    public func value(at bid: Decimal) -> Decimal { quantity * bid }

    /// Aynı paralar alım günlerinde dolara konsaydı bugün (kur eksikse `nil`).
    public func usdAlternative(usdTRYNow: Decimal) -> Decimal? {
        RealReturn.usdBenchmark(trades: buys, usdTRYNow: usdTRYNow)
    }
}

public enum SavingsPlanMath {
    /// Bir vade "tutuldu" sayılır: vadeden 3 gün önce ile sıradaki vadeden önceki gün arasında bu varlıktan alım
    /// varsa. Atlanan vade ceza değildir; yalnız sayılır.
    public static func progress(of plan: SavingsPlanRule, trades: [Trade], salaryDates: [Date] = [], now: Date,
                                calendar: Calendar) -> SavingsPlanProgress {
        let start = calendar.startOfDay(for: plan.start)
        let today = calendar.startOfDay(for: now)
        let buys = trades
            .filter { $0.asset == plan.asset && $0.side == .buy && calendar.startOfDay(for: $0.date) >= calendar.date(byAdding: .day, value: -3, to: start)! }
            .sorted { $0.date < $1.date }

        let dues: [Date]
        var next: Date?
        if let schedule = plan.schedule {
            let all = schedule.occurrences(calendar: calendar, limit: 400)
            dues = all.filter { $0 <= today }
            next = all.first { $0 > today }
        } else {
            dues = salaryDates.map { calendar.startOfDay(for: $0) }.filter { $0 >= start && $0 <= today }.sorted()
        }

        var kept = 0
        for (index, due) in dues.enumerated() {
            let from = calendar.date(byAdding: .day, value: -3, to: due)!
            // Sıradaki vadenin penceresi 3 gün önce açılır; bir alım iki vadeye birden sayılmaz.
            let following = index + 1 < dues.count ? dues[index + 1] : next
            let until = following.map { calendar.date(byAdding: .day, value: -3, to: $0)! }
                ?? calendar.date(byAdding: .day, value: 1, to: today)!
            if buys.contains(where: { let day = calendar.startOfDay(for: $0.date); return day >= from && day < until }) {
                kept += 1
            }
        }
        return SavingsPlanProgress(dueCount: dues.count, keptCount: kept, buys: buys, nextDue: next)
    }
}
