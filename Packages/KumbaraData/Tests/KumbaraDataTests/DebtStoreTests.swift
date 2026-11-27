import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("Alacak / borç deposu (specs/10 §4)")
struct DebtStoreTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        context = container.mainContext
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
    }

    @Test("₺900 yemek 3 kişiye: bütçeye ₺300; Ayşe ₺300 ödeyince bütçe değişmez, hesap +₺300 (AC-I4-1)")
    func splitAndSettle() throws {
        let ledger = LedgerStore(context: context)
        let cash = try #require(try ledger.defaultAccount())
        let dining = try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.seedKey == "dining" })
        let now = Date.now
        let dinner = try ledger.save(TransactionDraft(kind: .expense, amount: 900, date: now, account: cash.ref,
                                                      category: dining.ref, merchant: "Köfteci"))
        let store = DebtStore(context: context)
        let ayse = try store.addPerson(name: "Ayşe")
        let mehmet = try store.addPerson(name: "Mehmet")
        #expect(try store.addPerson(name: "ayşe").id == ayse.id)
        try store.split(dinner, shares: [(ayse, 300), (mehmet, 300)])

        let month = LedgerMonth(containing: now, calendar: .current)
        #expect(try ledger.summary(for: month, currency: .TRY, calendar: .current).expense == Money(300, .TRY))
        #expect(cash.balance == Money(-900, .TRY))
        #expect(try store.balances()[ayse.id] == 300)

        try store.record(.settlement, person: ayse, amount: 300, account: cash)
        #expect(try ledger.summary(for: month, currency: .TRY, calendar: .current).expense == Money(300, .TRY))
        #expect(cash.balance == Money(-600, .TRY))
        #expect(try store.balances()[ayse.id] == 0)
        #expect(try store.balances()[mehmet.id] == 300)

        // Gider silinince alacak da düşer.
        try ledger.delete(dinner)
        #expect(try store.balances()[mehmet.id] == nil)
    }

    @Test("Elden borç: verilen hesaptan çıkar, bütçeye girmez; kayıt silinince transfer de silinir")
    func lend() throws {
        let ledger = LedgerStore(context: context)
        let cash = try #require(try ledger.defaultAccount())
        let store = DebtStore(context: context)
        let person = try store.addPerson(name: "Can")
        let record = try store.record(.lent, person: person, amount: 1_000, account: cash)
        #expect(cash.balance == Money(-1_000, .TRY))
        let month = LedgerMonth(containing: .now, calendar: .current)
        #expect(try ledger.summary(for: month, currency: .TRY, calendar: .current).expense.isZero)
        #expect(try store.balances()[person.id] == 1_000)
        try store.delete(record)
        #expect(cash.balance == Money(0, .TRY))
        #expect(try store.balances()[person.id] == nil)
    }

    @Test("Paylar gider tutarını aşamaz")
    func sharesLimit() throws {
        let ledger = LedgerStore(context: context)
        let cash = try #require(try ledger.defaultAccount())
        let expense = try ledger.save(TransactionDraft(kind: .expense, amount: 500, date: .now, account: cash.ref))
        let store = DebtStore(context: context)
        let person = try store.addPerson(name: "Deniz")
        #expect(throws: DebtStore.DebtError.sharesExceedTotal) { try store.split(expense, shares: [(person, 500)]) }
    }
}
