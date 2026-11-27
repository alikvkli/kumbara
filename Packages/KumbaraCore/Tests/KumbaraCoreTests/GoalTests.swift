import Foundation
import Testing
@testable import KumbaraCore

@Suite("Hedefler (specs/09 §6)")
struct GoalTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func buy(_ asset: AssetCode, _ quantity: Decimal, at price: Decimal = 10_000) -> Trade {
        Trade(asset: asset, side: .buy, quantity: quantity, unitPrice: price, date: date(2026, 6, 1))
    }

    @Test("20 çeyrek hedefi, atanmış 8 çeyrek → %40, 12 kaldı (AC-P9-1)")
    func quantityGoal() {
        let goal = SavingsGoal(name: "Düğün", target: .quantity(.gold(.quarter), 20))
        let trades = [buy(.gold(.quarter), 5), buy(.gold(.quarter), 3)]
        let progress = GoalMath.progress(of: goal, trades: trades, prices: [:], now: date(2026, 11, 27), calendar: calendar)
        #expect(progress.current == 8)
        #expect(progress.remaining == 12)
        #expect(abs(progress.fraction - 0.4) < 0.0001)
        #expect(progress.perMonth == nil)
    }

    @Test("Satış hedeften düşer; başka varlık miktar hedefini etkilemez")
    func sellsReduceProgress() {
        let goal = SavingsGoal(name: "Düğün", target: .quantity(.gold(.quarter), 20))
        let sell = Trade(asset: .gold(.quarter), side: .sell, quantity: 2, unitPrice: 10_000, date: date(2026, 9, 1))
        let progress = GoalMath.progress(of: goal, trades: [buy(.gold(.quarter), 5), sell, buy(.gold(.gram24), 10)],
                                         prices: [:], now: date(2026, 11, 27), calendar: calendar)
        #expect(progress.current == 3)
    }

    @Test("TL hedefi bugünkü değerle; fiyatı olmayan varlık eksik diye işaretlenir")
    func amountGoal() {
        let goal = SavingsGoal(name: "Ev", target: .amount(500_000), deadline: date(2027, 10, 15))
        let trades = [buy(.gold(.gram24), 10, at: 5_000), buy(.fx(.USD), 1_000, at: 40), buy(.crypto("bitcoin"), 1)]
        let progress = GoalMath.progress(of: goal, trades: trades,
                                         prices: [.gold(.gram24): 6_000, .fx(.USD): 50],
                                         now: date(2026, 11, 27), calendar: calendar)
        #expect(progress.current == 110_000)
        #expect(progress.hasMissingPrices)
        #expect(progress.monthsLeft == 12)  // Kasım 2026 … Ekim 2027
        #expect(progress.perMonth == 32_500)
    }

    @Test("Geçmiş tarih: kalan ay 1, kalan tutarın tamamı bu ay")
    func pastDeadline() {
        #expect(GoalMath.monthsLeft(until: date(2026, 3, 1), now: date(2026, 11, 27), calendar: calendar) == 1)
        #expect(GoalMath.monthsLeft(until: date(2026, 11, 30), now: date(2026, 11, 27), calendar: calendar) == 1)
    }

    @Test("Atanmamış miktar önerisi")
    func unassigned() {
        let assigned = buy(.gold(.quarter), 8)
        let free = buy(.gold(.quarter), 6)
        #expect(GoalMath.unassignedQuantity(of: .gold(.quarter), allTrades: [assigned, free, buy(.gold(.gram24), 3)],
                                            assignedTradeIDs: [assigned.id]) == 6)
    }

    @Test("Gelirden ayırma: yüzde ve alınabilecek miktar aşağı yuvarlanır")
    func split() {
        #expect(SavingsSplit.amount(of: 62_000, percent: 15) == 9_300)
        #expect(SavingsSplit.quantity(for: 9_300, unitPrice: 6_120, wholeUnits: false) == Decimal(string: "1.51")!)
        #expect(SavingsSplit.quantity(for: 9_300, unitPrice: 10_158, wholeUnits: true) == 0)
        #expect(SavingsSplit.quantity(for: 25_000, unitPrice: 10_158, wholeUnits: true) == 2)
    }
}
