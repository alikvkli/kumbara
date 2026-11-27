import Foundation

/// Aylık limit geçmişi (specs/08 §1.1): değişiklik o aydan itibaren geçerlidir, geçmiş aylar kendi
/// limitini korur. Kanonik metin olarak saklanır: `"2026-11=4000;2027-01=4500"`.
public struct BudgetLimitHistory: Hashable, Sendable {
    public private(set) var entries: [(month: LedgerMonth, limit: Decimal)]

    public init() { entries = [] }

    public init?(canonical: String) {
        var result: [(LedgerMonth, Decimal)] = []
        for part in canonical.split(separator: ";") where !part.isEmpty {
            let pair = part.split(separator: "=")
            guard pair.count == 2 else { return nil }
            let ym = pair[0].split(separator: "-").compactMap { Int($0) }
            guard ym.count == 2, (1...12).contains(ym[1]), let limit = Decimal(canonical: String(pair[1])) else { return nil }
            result.append((LedgerMonth(year: ym[0], month: ym[1]), limit))
        }
        entries = result.sorted { $0.0 < $1.0 }
    }

    public var canonical: String {
        entries.map { String(format: "%04d-%02d=", $0.month.year, $0.month.month) + $0.limit.canonicalString }
            .joined(separator: ";")
    }

    /// O ay geçerli limit; bütçe o aydan sonra başladıysa `nil`.
    public func limit(for month: LedgerMonth) -> Decimal? {
        entries.last { $0.month <= month }?.limit
    }

    /// `month`tan itibaren `limit`. Sonraki aylara girilmiş değişiklikler korunur.
    public mutating func set(_ limit: Decimal, from month: LedgerMonth) {
        entries.removeAll { $0.month == month }
        entries.append((month, limit))
        entries.sort { $0.month < $1.month }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.canonical == rhs.canonical }
    public func hash(into hasher: inout Hasher) { hasher.combine(canonical) }
}

/// Kategori ağacı özeti: bütçe hesabının bilmesi gerekenler.
public struct CategoryIndex: Sendable {
    /// alt → üst
    public var parent: [UUID: UUID]
    /// Gider kategorileri (gider kategorisindeki gelir = iade).
    public var expense: Set<UUID>

    public init(parent: [UUID: UUID], expense: Set<UUID>) {
        self.parent = parent
        self.expense = expense
    }

    /// `id` kendisi ya da `ancestor`'ın altında mı.
    func isWithin(_ id: UUID, _ ancestor: UUID) -> Bool {
        var current: UUID? = id
        var depth = 0
        while let value = current, depth < 16 {
            if value == ancestor { return true }
            current = parent[value]
            depth += 1
        }
        return false
    }
}

public struct BudgetSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// `nil` = genel bütçe (tüm giderler).
    public var categoryID: UUID?
    public var history: BudgetLimitHistory

    public init(id: UUID = UUID(), categoryID: UUID?, history: BudgetLimitHistory) {
        self.id = id
        self.categoryID = categoryID
        self.history = history
    }
}

public struct BudgetStatus: Hashable, Sendable, Identifiable {
    public enum Level: Int, Comparable, Sendable {
        case normal, warning, over
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: UUID
    public var categoryID: UUID?
    public var limit: Money
    public var spent: Money
    /// Ayın geçen kısmı (0…1); geçmiş ay 1, gelecek ay 0.
    public var elapsed: Decimal
    /// Başka para biriminde olup kuru bulunamadığı için sayılamayan kayıt var mı.
    public var hasUnconvertedEntries: Bool

    public var remaining: Money { limit - spent }
    public var ratio: Decimal { limit.isZero ? 0 : spent.amount / limit.amount }
    public var level: Level { ratio >= 1 ? .over : ratio >= BudgetMath.warningThreshold ? .warning : .normal }
    /// Harcama ayın gidişinden %10'dan fazla öndeyse (ve henüz aşılmadıysa) "hızlı gidiyor".
    public var isAheadOfPace: Bool { ratio < 1 && elapsed < 1 && ratio > elapsed + Decimal(string: "0.10")! }
}

public enum BudgetMath {
    public static let warningThreshold = Decimal(string: "0.8")!
    /// Bildirim eşikleri (REQ-B2).
    public static let thresholds: [Int] = [80, 100]

    /// Ayın bütçe durumları. `rate`: işlem para biriminden TRY'ye, işlem gününün kuru (yoksa `nil`).
    public static func statuses(
        _ budgets: [BudgetSpec], entries: [LedgerEntry], categories: CategoryIndex,
        month: LedgerMonth, today: Date, calendar: Calendar,
        rate: (CurrencyCode, Date) -> Decimal? = { _, _ in nil }
    ) -> [BudgetStatus] {
        let interval = month.interval(in: calendar)
        let inMonth = entries.filter {
            $0.status == .posted && $0.kind != .transfer && $0.date >= interval.start && $0.date < interval.end
        }
        let elapsed = elapsedFraction(month: month, today: today, calendar: calendar)

        return budgets.compactMap { budget in
            guard let limit = budget.history.limit(for: month) else { return nil }
            var spent = Decimal(0)
            var unconverted = false
            for entry in inMonth {
                if let target = budget.categoryID {
                    guard let categoryID = entry.categoryID, categories.isWithin(categoryID, target) else { continue }
                } else {
                    // Genel bütçe: tüm giderler (kategorisizler dahil) ve gider kategorisindeki iadeler.
                    guard entry.kind == .expense || entry.categoryID.map(categories.expense.contains) == true else { continue }
                }
                // Gider kategorisindeki gelir iadedir: harcamadan düşer.
                let sign: Decimal = entry.kind == .expense ? 1 : -1
                if entry.amount.currency == .TRY {
                    spent += sign * entry.amount.amount
                } else if let rate = rate(entry.amount.currency, entry.date) {
                    spent += sign * entry.amount.amount * rate
                } else {
                    unconverted = true
                }
            }
            return BudgetStatus(id: budget.id, categoryID: budget.categoryID, limit: Money(limit, .TRY),
                                spent: Money(max(spent, 0).rounded(scale: 2), .TRY), elapsed: elapsed,
                                hasUnconvertedEntries: unconverted)
        }
        .sorted { lhs, rhs in
            if (lhs.categoryID == nil) != (rhs.categoryID == nil) { return lhs.categoryID == nil }
            return lhs.ratio != rhs.ratio ? lhs.ratio > rhs.ratio : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Bugün dahil geçen gün / ayın gün sayısı.
    public static func elapsedFraction(month: LedgerMonth, today: Date, calendar: Calendar) -> Decimal {
        let interval = month.interval(in: calendar)
        if today >= interval.end { return 1 }
        if today < interval.start { return 0 }
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
        let passed = (calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: today)).day ?? 0) + 1
        return Decimal(passed) / Decimal(max(days, 1))
    }

    /// Ulaşılmış eşikler (bildirim için; her biri ayda bir kez gönderilir).
    public static func reachedThresholds(_ status: BudgetStatus) -> [Int] {
        thresholds.filter { status.ratio * 100 >= Decimal($0) }
    }

    /// Son aylardaki harcamadan önerilen limit (specs/08 §1.4): sıfır olmayan ayların ortalaması,
    /// yukarı yuvarlanmış (₺1.000 altı 50'ye, ₺10.000 altı 100'e, üstü 500'e). Veri yoksa `nil`.
    public static func suggestedLimit(monthlySpending: [Decimal]) -> Decimal? {
        let months = monthlySpending.filter { $0 > 0 }
        guard !months.isEmpty else { return nil }
        let average = months.reduce(0, +) / Decimal(months.count)
        let step: Decimal = average < 1000 ? 50 : average < 10_000 ? 100 : 500
        var units = average / step
        var whole = Decimal()
        NSDecimalRound(&whole, &units, 0, .up)
        return whole * step
    }
}
