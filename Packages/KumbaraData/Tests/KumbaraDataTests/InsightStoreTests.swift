import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("İçgörü deposu (specs/10 §1, §2)")
struct InsightStoreTests {
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

    @Test("Örnek veri: Netflix zamlı, Spotify bu ay görünmedi; taksit abonelik sayılmaz")
    func demoSubscriptions() throws {
        let store = InsightStore(context: try demo())
        let found = try store.subscriptions(now: now, calendar: calendar)
        #expect(Set(found.map(\.merchantKey)) == ["netflix", "spotify"])
        let netflix = try #require(found.first { $0.merchantKey == "netflix" })
        #expect(netflix.previousAmount == Decimal(canonical: "189.99"))
        #expect(netflix.lastAmount == Decimal(canonical: "229.99"))
        #expect(found.first { $0.merchantKey == "spotify" }?.isMissed == true)
    }

    @Test("'Abonelik değil' denen satıcı listeden çıkar")
    func dismiss() throws {
        let store = InsightStore(context: try demo())
        try store.dismissSubscription("spotify")
        #expect(try store.subscriptions(now: now, calendar: calendar).map(\.merchantKey) == ["netflix"])
    }

    @Test("Rapor ayları içinde bulunulan ayı içermez; Ekim raporu Eylül ile karşılaştırılır")
    func reports() throws {
        let store = InsightStore(context: try demo())
        let months = try store.reportMonths(now: now, calendar: calendar)
        #expect(months == [LedgerMonth(year: 2026, month: 10), LedgerMonth(year: 2026, month: 9), LedgerMonth(year: 2026, month: 8)])
        let october = try store.report(for: months[0], now: now, calendar: calendar)
        #expect(october.hasContent)
        #expect(october.previousExpense != nil)
        #expect(october.change != nil)
        #expect(october.budget != nil)
        #expect(october.savings != nil)
    }
}

@MainActor
@Suite("Ödeme takvimi deposu (specs/10 §5)")
struct PaymentCalendarStoreTests {
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    @Test("Örnek veri: kira ve maaş 1 Aralık'ta, kart dönemi 'şu ana kadar'; kartlı abonelik ayrı kalem değil")
    func demoCalendar() throws {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        let items = try InsightStore(context: context).upcomingPayments(from: now, days: 31, now: now, calendar: calendar)
        let december1 = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        #expect(items.contains { $0.isIncome && $0.date == december1 })
        #expect(items.contains { !$0.isIncome && $0.date == december1 && $0.amount == 22_500 })
        #expect(items.contains { $0.isPartial })
        #expect(!items.contains { $0.title == "Netflix" })
        #expect(!items.contains { $0.title == "MacFit" })
        let next = try #require(PaymentCalendar.nextIncome(items, from: now, calendar: calendar))
        #expect(next.days == 4)
    }
}

@MainActor
@Suite("Birikim planı deposu (specs/10 §7)")
struct PlanStoreTests {
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    @Test("Örnek plan: son alım vadeye sayılır; yedekten geri gelir")
    func demoPlanAndBackup() throws {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        let store = PlanStore(context: context)
        let plan = try #require(try store.plans().first)
        let progress = try #require(try store.progress(of: plan, now: now, calendar: calendar))
        #expect(progress.dueCount >= 2)
        #expect(progress.keptCount >= 1)
        #expect(progress.nextDue != nil)
        #expect(try store.salaryDates().count == 3)

        let data = try ExchangeStore(context: context).backupJSON(now: now)
        let other = try containers.make()
        try ExchangeStore(context: other).restore(data, mode: .replace)
        let restored = try PlanStore(context: other).plans()
        #expect(restored.map(\.id) == [plan.id])
        #expect(restored.first?.rule == plan.rule)
    }
}
