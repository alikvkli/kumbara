import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("Hedef deposu (specs/09 §6)")
struct GoalStoreTests {
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    private func demo() throws -> ModelContext {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        return context
    }

    @Test("Örnek veri: düğün hedefinde 8 / 20 çeyrek, ev hedefi gram altının bugünkü değeri")
    func demoGoals() throws {
        let store = GoalStore(context: try demo())
        let goals = try store.goals()
        #expect(goals.map(\.name) == ["Düğün", "Ev peşinatı"])
        let wedding = try #require(try store.progress(of: goals[0], prices: [:], now: now, calendar: calendar))
        #expect(wedding.current == 8)
        #expect(wedding.remaining == 12)
        #expect(wedding.monthsLeft == 11)
        let home = try #require(try store.progress(of: goals[1], prices: [.gold(.gram24): 6_000], now: now, calendar: calendar))
        #expect(home.current == Decimal(string: "17.5")! * 6_000)
        #expect(!home.hasMissingPrices)
    }

    @Test("Hedef silinince alımlar kalır, bağ kopar")
    func deleteKeepsTrades() throws {
        let context = try demo()
        let store = GoalStore(context: context)
        let trades = try context.fetchCount(FetchDescriptor<AssetTrade>())
        try store.delete(try store.goals()[0])
        #expect(try context.fetchCount(FetchDescriptor<AssetTrade>()) == trades)
        #expect(try context.fetch(FetchDescriptor<AssetTrade>()).filter { $0.asset == .gold(.quarter) }.allSatisfy { $0.goalID == nil })
    }

    @Test("Atanmamış çeyrek önerisi")
    func unassigned() throws {
        let context = try demo()
        let store = GoalStore(context: context)
        let wedding = try store.goals()[0]
        let quarters = try context.fetch(FetchDescriptor<AssetTrade>()).filter { $0.asset == .gold(.quarter) }
        try store.assign([quarters[0]], to: nil)
        let free = try store.unassigned(for: wedding)
        #expect(free.trades.count == 1)
        #expect(free.quantity == 4)
        #expect(try store.progress(of: wedding, prices: [:], now: now, calendar: calendar)?.current == 4)
    }
}
