import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("BudgetStore (specs/08 §1)")
struct BudgetStoreTests {
    let container: ModelContainer
    let ledger: LedgerStore
    let budgets: BudgetStore
    var calendar = Calendar(identifier: .gregorian)
    let november = LedgerMonth(year: 2026, month: 11)

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        ledger = LedgerStore(context: container.mainContext)
        budgets = BudgetStore(context: container.mainContext)
        try LedgerSeeder.seedIfNeeded(container.mainContext, locale: Locale(identifier: "tr_TR"))
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    }

    private func category(_ key: String) throws -> LedgerCategory {
        try #require(try ledger.category(seedKey: key))
    }

    private func spend(_ amount: Decimal, _ key: String, month: Int = 11, day: Int = 10) throws {
        let cash = try #require(try ledger.defaultAccount())
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        try ledger.save(TransactionDraft(amount: amount, date: date, account: cash.ref, category: try category(key).ref))
    }

    @Test("Üst kategori bütçesi alt kategori harcamalarını sayar; limit değişikliği o aydan itibaren")
    func statusAndHistory() throws {
        let market = try category("market")
        try budgets.setLimit(4000, for: market, from: november)
        try spend(2500, "market.food")
        try spend(800, "market.household")
        try spend(300, "dining.cafe")

        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let status = try #require(try budgets.statuses(for: november, today: today, calendar: calendar).first)
        #expect(status.spent.amount == 3300)
        #expect(status.level == .warning)

        try budgets.setLimit(4500, for: market, from: LedgerMonth(year: 2026, month: 12))
        #expect(try budgets.budgets().count == 1)
        #expect(try budgets.statuses(for: november, today: today, calendar: calendar).first?.limit.amount == 4000)
        #expect(try budgets.statuses(for: LedgerMonth(year: 2026, month: 12), today: today, calendar: calendar).first?.limit.amount == 4500)
    }

    @Test("Genel bütçe ayrı tutulur; kategori silinince bütçesi de silinir")
    func overallAndCascade() throws {
        try budgets.setLimit(20_000, for: nil, from: november)
        let cafe = try category("dining.cafe")
        try budgets.setLimit(500, for: cafe, from: november)
        #expect(try budgets.budgets().filter(\.isOverall).count == 1)
        container.mainContext.delete(cafe)
        try container.mainContext.save()
        #expect(try budgets.budgets().count == 1)
    }

    @Test("Bildirim defteri bir kez kaydeder")
    func notificationLog() throws {
        let key = BudgetStore.notificationKey(budget: UUID(), month: november, threshold: 80)
        #expect(try !budgets.wasNotified(key))
        try budgets.markNotified(key)
        try budgets.markNotified(key)
        #expect(try budgets.wasNotified(key))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NotificationLog>()) == 1)
    }

    @Test("Öneri: son 3 ayın ortalaması, bütçesi olanlar hariç")
    func suggestions() throws {
        try spend(3870, "market.food", month: 8)
        try spend(3950, "market.food", month: 9)
        try spend(3880, "market.food", month: 10)
        try spend(600, "dining.cafe", month: 10)
        let first = try budgets.suggestions(before: november, calendar: calendar)
        #expect(first.map(\.category.seedKey) == ["market", "dining"])
        #expect(first.first?.limit == 3900)

        try budgets.setLimit(3900, for: try category("market"), from: november)
        #expect(try budgets.suggestions(before: november, calendar: calendar).map(\.category.seedKey) == ["dining"])
    }
}
