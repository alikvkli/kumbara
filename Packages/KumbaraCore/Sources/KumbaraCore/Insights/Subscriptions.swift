import Foundation

/// Abonelik algılama (REQ-I2, specs/10 §2).
///
/// Aynı satıcıya düzenli aralıkla (aylık 28–35 gün, yıllık 360–370 gün) yapılan, tutarı birbirine yakın
/// en az üç ödeme bir abonelik sayılır. Zincir en son ödemeden geriye doğru kurulur; aradaki her ödeme
/// bir öncekine göre ±%15 içinde kalmalı ya da tek seferlik bir fiyat artışı (en çok +%50) olmalı.
/// Taksitler, transferler, gelirler ve kesinleşmemiş kayıtlar çağıran tarafından dışarıda bırakılır.
public enum SubscriptionDetector {
    public struct Payment: Hashable, Sendable {
        public var date: Date
        public var amount: Decimal
        /// `MerchantKey.normalize` sonucu.
        public var merchantKey: String
        public var merchantName: String
        /// Ödeme bir tekrarlayan kuraldan geldiyse.
        public var isRecurring: Bool

        public init(date: Date, amount: Decimal, merchantKey: String, merchantName: String, isRecurring: Bool = false) {
            self.date = date
            self.amount = amount
            self.merchantKey = merchantKey
            self.merchantName = merchantName
            self.isRecurring = isRecurring
        }
    }

    public enum Cadence: String, Sendable, Hashable {
        case monthly, yearly

        var days: ClosedRange<Int> { self == .monthly ? 28...35 : 360...370 }
        var component: Calendar.Component { self == .monthly ? .month : .year }
    }

    public struct Subscription: Hashable, Sendable, Identifiable {
        public var id: String { merchantKey }
        public var merchantKey: String
        public var name: String
        public var cadence: Cadence
        /// Zincirdeki ödemeler, eskiden yeniye.
        public var payments: [Payment]
        public var lastAmount: Decimal { payments.last?.amount ?? 0 }
        /// Son ödeme bir öncekinden en az %3 fazlaysa önceki tutar.
        public var previousAmount: Decimal?
        public var priceIncrease: Decimal? {
            guard let previousAmount, previousAmount > 0 else { return nil }
            return (lastAmount - previousAmount) / previousAmount
        }
        /// Bir sonraki beklenen ödeme günü.
        public var nextDue: Date
        /// Beklenen gün 10 günden fazla geçti ve ödeme yok.
        public var isMissed: Bool
        /// Bir tekrarlayan kural bu ödemeyi zaten takip ediyor.
        public var isTracked: Bool

        /// Yıllıklar 12'ye bölünür.
        public var monthlyCost: Decimal { cadence == .monthly ? lastAmount : lastAmount / 12 }
    }

    static let minimumPayments = 3
    static let tolerance: Decimal = 0.15
    static let maximumStepUp: Decimal = 0.5
    static let increaseThreshold: Decimal = 0.03
    static let missedAfterDays = 10
    /// Beklenen günden bu kadar sonra hâlâ ödeme yoksa abonelik bitmiş sayılır, listelenmez.
    static let staleAfterDays = 40

    public static func detect(_ payments: [Payment], now: Date, calendar: Calendar,
                              trackedKeys: Set<String> = [], dismissedKeys: Set<String> = []) -> [Subscription] {
        let groups = Dictionary(grouping: payments.filter { !$0.merchantKey.isEmpty && $0.amount > 0 }, by: \.merchantKey)
        var result: [Subscription] = []
        for (key, group) in groups where !dismissedKeys.contains(key) {
            let sorted = group.sorted { $0.date < $1.date }
            guard sorted.count >= minimumPayments else { continue }
            for cadence in [Cadence.monthly, .yearly] {
                let chain = chain(sorted, cadence: cadence, calendar: calendar)
                guard chain.count >= minimumPayments, let last = chain.last,
                      let nextDue = calendar.date(byAdding: cadence.component, value: 1, to: last.date) else { continue }
                let overdue = calendar.dateComponents([.day], from: calendar.startOfDay(for: nextDue),
                                                      to: calendar.startOfDay(for: now)).day ?? 0
                guard overdue <= staleAfterDays else { break }
                let previous = chain[chain.count - 2].amount
                let increased = previous > 0 && (last.amount - previous) / previous >= increaseThreshold
                result.append(Subscription(
                    merchantKey: key, name: last.merchantName, cadence: cadence, payments: chain,
                    previousAmount: increased ? previous : nil, nextDue: nextDue,
                    isMissed: overdue > missedAfterDays,
                    isTracked: trackedKeys.contains(key) || chain.contains(where: \.isRecurring)))
                break
            }
        }
        return result.sorted { lhs, rhs in
            lhs.monthlyCost != rhs.monthlyCost ? lhs.monthlyCost > rhs.monthlyCost : lhs.merchantKey < rhs.merchantKey
        }
    }

    /// En son ödemeden geriye, kesintisiz ardışık ödemeler.
    static func chain(_ sorted: [Payment], cadence: Cadence, calendar: Calendar) -> [Payment] {
        guard var current = sorted.last else { return [] }
        var chain = [current]
        var steppedUp = false
        for earlier in sorted.dropLast().reversed() {
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier.date),
                                              to: calendar.startOfDay(for: current.date)).day ?? 0
            guard cadence.days.contains(gap), earlier.amount > 0 else { break }
            let change = (current.amount - earlier.amount) / earlier.amount
            if abs(change) <= tolerance {
                // Benzer tutar.
            } else if change > 0, change <= maximumStepUp, !steppedUp {
                steppedUp = true
            } else {
                break
            }
            chain.insert(earlier, at: 0)
            current = earlier
        }
        return chain
    }

    /// Listelenen (kaçırılmamış) aboneliklerin aylık toplamı.
    public static func monthlyTotal(_ subscriptions: [Subscription]) -> Decimal {
        subscriptions.filter { !$0.isMissed }.reduce(0) { $0 + $1.monthlyCost }
    }
}
