import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("RecurringStore (specs/08 §2)")
struct RecurringStoreTests {
    let container: ModelContainer
    let ledger: LedgerStore
    let recurring: RecurringStore
    var calendar = Calendar(identifier: .gregorian)

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        ledger = LedgerStore(context: container.mainContext)
        recurring = RecurringStore(context: container.mainContext)
        try LedgerSeeder.seedIfNeeded(container.mainContext, locale: Locale(identifier: "tr_TR"))
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    }

    func d(_ m: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: day, hour: hour))!
    }

    private func rent() throws -> LedgerTransaction {
        let cash = try #require(try ledger.defaultAccount())
        let rent = try #require(try ledger.category(seedKey: "housing.rent"))
        return try ledger.save(TransactionDraft(amount: 18_000, date: d(8, 1), account: cash.ref, category: rent.ref,
                                                merchant: "Ev sahibi"))
    }

    @Test("AC-L7-2: 3 ay sonra açılınca 3 taslak; ikinci açılışta yeni taslak yok")
    func catchUp() throws {
        let rule = try recurring.makeRule(from: try rent(), frequency: .monthly(day: 1), calendar: calendar)
        #expect(rule.lastDue == calendar.startOfDay(for: d(8, 1)))

        let created = try recurring.generateDrafts(now: d(11, 27), calendar: calendar)
        #expect(created.count == 3)
        #expect(created.allSatisfy { $0.status == .draft && $0.origin == .recurring && $0.amount.amount == 18_000 })
        #expect(try recurring.generateDrafts(now: d(11, 27, hour: 20), calendar: calendar).isEmpty)
        #expect(try recurring.pendingDrafts().count == 3)

        // Taslaklar bakiyeye ve aylık özete sayılmaz (C5).
        let november = try ledger.summary(for: LedgerMonth(year: 2026, month: 11), currency: .TRY, calendar: calendar)
        #expect(november.expense.isZero)
    }

    @Test("Onayla kesinleştirir, atla siler ve geri gelmez; kural silinince taslakları gider")
    func approveSkipDelete() throws {
        let rule = try recurring.makeRule(from: try rent(), frequency: .monthly(day: 1), calendar: calendar)
        let drafts = try recurring.generateDrafts(now: d(10, 2), calendar: calendar)
        #expect(drafts.count == 2)

        try recurring.approve(drafts[0], amount: 18_500)
        #expect(drafts[0].status == .posted)
        #expect(rule.amount == 18_500)  // sabit tutarlı kural yeni tutarı öğrenir
        try recurring.skip(drafts[1])
        #expect(try recurring.generateDrafts(now: d(10, 3), calendar: calendar).isEmpty)

        _ = try recurring.generateDrafts(now: d(11, 2), calendar: calendar)
        #expect(try recurring.pendingDrafts().count == 1)
        try recurring.delete(rule)
        #expect(try recurring.pendingDrafts().isEmpty)
        #expect(try recurring.rules().isEmpty)
        #expect(drafts[0].status == .posted)  // kesinleşmiş kayıt kalır
    }

    @Test("Duraklatılmış kural taslak üretmez")
    func paused() throws {
        let rule = try recurring.makeRule(from: try rent(), frequency: .monthly(day: 1), calendar: calendar)
        rule.isPaused = true
        #expect(try recurring.generateDrafts(now: d(11, 27), calendar: calendar).isEmpty)
    }
}
