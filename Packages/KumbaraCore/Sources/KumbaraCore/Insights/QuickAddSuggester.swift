import Foundation

/// Hızlı ekleme önerisi (REQ-I6, specs/10 §6): yeni gider açılınca alışkanlığa uyan 1–3 satıcı.
///
/// Yalnız cihazdaki geçmişten (son 90 gün); konum kullanılmaz (K3). Bir geçmiş kayıt "uyar": aynı gün
/// türünde (hafta içi / hafta sonu) ve saati ±60 dk içindeyse. En az 4 uyan kayıt olmadan öneri yok.
public enum QuickAddSuggester {
    public struct Suggestion: Hashable, Sendable, Identifiable {
        public var id: String { merchantKey }
        public var merchantKey: String
        public var merchant: String
        public var amount: Decimal
        public var categoryID: UUID?
        public var accountID: UUID?
        /// Uyan geçmiş kayıt sayısı.
        public var matches: Int
    }

    static let lookbackDays = 90
    static let windowMinutes = 60
    static let minimumMatches = 4

    public static func suggestions(entries: [LedgerEntry], now: Date, calendar: Calendar,
                                   dismissedKeys: Set<String> = [], limit: Int = 3) -> [Suggestion] {
        guard let since = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return [] }
        let isWeekend = calendar.isDateInWeekend(now)
        let nowMinute = minuteOfDay(now, calendar: calendar)

        var groups: [String: [LedgerEntry]] = [:]
        for entry in entries where entry.status == .posted && entry.kind == .expense && entry.amount.currency == .TRY
            && entry.date >= since && entry.date <= now {
            guard let name = entry.merchant, case let key = MerchantKey.normalize(name), !key.isEmpty,
                  !dismissedKeys.contains(key) else { continue }
            groups[key, default: []].append(entry)
        }

        var scored: [(suggestion: Suggestion, score: Double)] = []
        for (key, group) in groups {
            let matching = group.filter { entry in
                guard calendar.isDateInWeekend(entry.date) == isWeekend else { return false }
                let difference = abs(minuteOfDay(entry.date, calendar: calendar) - nowMinute)
                return min(difference, 24 * 60 - difference) <= windowMinutes
            }
            guard matching.count >= minimumMatches else { continue }
            let sorted = matching.sorted { $0.date < $1.date }
            let recentThree = sorted.suffix(3).map(\.amount.amount)
            let amount = recentThree.count == 3 && Set(recentThree).count == 1 ? recentThree[0] : median(sorted.map(\.amount.amount))
            let last = sorted.last!
            // Yakınlık: son 30 gündeki uyanlar iki kat sayılır.
            let recent = matching.filter { now.timeIntervalSince($0.date) <= 30 * 86_400 }.count
            let score = Double(matching.count) + Double(recent)
            scored.append((Suggestion(merchantKey: key, merchant: last.merchant ?? key, amount: amount,
                                      categoryID: last.categoryID, accountID: last.accountID, matches: matching.count), score))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.suggestion.merchantKey < $1.suggestion.merchantKey }
            .prefix(limit)
            .map(\.suggestion)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
