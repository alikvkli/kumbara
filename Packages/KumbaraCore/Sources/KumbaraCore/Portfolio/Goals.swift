import Foundation

/// Birikim hedefi (REQ-P9, specs/09 §6): "Düğün için 20 çeyrek", "Ev için ₺500.000".
public struct SavingsGoal: Hashable, Sendable, Identifiable {
    public enum Target: Hashable, Sendable {
        /// Varlık miktarı; ilerleme hedefe atanmış alımların net miktarıdır.
        case quantity(AssetCode, Decimal)
        /// TL tutarı; ilerleme atanmış alımların bugünkü değeridir.
        case amount(Decimal)
    }

    public var id: UUID
    public var name: String
    public var target: Target
    public var deadline: Date?

    public init(id: UUID = UUID(), name: String, target: Target, deadline: Date? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.deadline = deadline
    }
}

public struct GoalProgress: Hashable, Sendable {
    /// Hedefin birimi cinsinden (miktar ya da TL).
    public var current: Decimal
    public var target: Decimal
    /// Tarihli hedefte, bugünden hedef tarihe kadar kalan takvim ayı (bu ay dahil, en az 1).
    public var monthsLeft: Int?
    /// TL hedefinde fiyatı bilinmeyen varlık varsa ilerleme eksik hesaplanmıştır (dürüst arayüz, C6).
    public var hasMissingPrices: Bool

    public var remaining: Decimal { max(target - current, 0) }
    public var isReached: Bool { current >= target }
    /// 0…1 arası (aşılırsa 1).
    public var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max((current / target as NSDecimalNumber).doubleValue, 0), 1)
    }
    /// Hedefe yetişmek için ayda ne kadar ayrılmalı.
    public var perMonth: Decimal? {
        guard let monthsLeft, !isReached else { return nil }
        return remaining / Decimal(monthsLeft)
    }
}

public enum GoalMath {
    /// - Parameters:
    ///   - trades: Hedefe atanmış alım ve satışlar.
    ///   - prices: Varlık başına bugünkü fiyat (genelde bozdurma, D6).
    public static func progress(of goal: SavingsGoal, trades: [Trade], prices: [AssetCode: Decimal],
                                now: Date, calendar: Calendar) -> GoalProgress {
        let net = netQuantities(trades)
        let current: Decimal
        let target: Decimal
        var missing = false
        switch goal.target {
        case let .quantity(asset, quantity):
            current = max(net[asset] ?? 0, 0)
            target = quantity
        case let .amount(amount):
            var value = Decimal(0)
            for (asset, quantity) in net where quantity > 0 {
                if let price = prices[asset] { value += quantity * price } else { missing = true }
            }
            current = value
            target = amount
        }
        return GoalProgress(current: current, target: target,
                            monthsLeft: goal.deadline.map { monthsLeft(until: $0, now: now, calendar: calendar) },
                            hasMissingPrices: missing)
    }

    /// Bu ay dahil hedef ayına kadar kaç ay var; geçmiş tarih için 1 (hemen).
    public static func monthsLeft(until deadline: Date, now: Date, calendar: Calendar) -> Int {
        let from = calendar.dateComponents([.year, .month], from: now)
        let to = calendar.dateComponents([.year, .month], from: deadline)
        let months = ((to.year ?? 0) - (from.year ?? 0)) * 12 + ((to.month ?? 0) - (from.month ?? 0)) + 1
        return max(months, 1)
    }

    /// Miktar hedefinde, aynı varlıktan hedefe atanmamış elde tutulan miktar
    /// ("Elinde atanmamış 6 çeyrek daha var, ekle?").
    public static func unassignedQuantity(of asset: AssetCode, allTrades: [Trade], assignedTradeIDs: Set<UUID>) -> Decimal {
        let unassigned = allTrades.filter { $0.asset == asset && !assignedTradeIDs.contains($0.id) }
        return max(netQuantities(unassigned)[asset] ?? 0, 0)
    }

    static func netQuantities(_ trades: [Trade]) -> [AssetCode: Decimal] {
        var result: [AssetCode: Decimal] = [:]
        for trade in trades {
            result[trade.asset, default: 0] += trade.side == .buy ? trade.quantity : -trade.quantity
        }
        return result
    }
}

/// Gelirden birikime ayırma önerisi (REQ-P10, specs/09 §6).
public enum SavingsSplit {
    /// Gelirin yüzdesi, kuruşa yuvarlanmış.
    public static func amount(of income: Decimal, percent: Decimal) -> Decimal {
        var value = income * percent / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }

    /// Ayrılan tutarla bugünkü satış fiyatından alınabilecek miktar. Gram için 2 basamak, adetli
    /// varlıkta (çeyrek, tam…) tam sayı, aşağı yuvarlanır: kullanıcı ödeyebileceğinden fazlasını görmez.
    public static func quantity(for amount: Decimal, unitPrice: Decimal, wholeUnits: Bool) -> Decimal {
        guard unitPrice > 0 else { return 0 }
        var value = amount / unitPrice
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, wholeUnits ? 0 : 2, .down)
        return rounded
    }
}
