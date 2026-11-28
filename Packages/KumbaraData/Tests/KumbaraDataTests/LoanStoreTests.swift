import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("Kredi deposu (specs/13)")
struct LoanStoreTests {
    private let containers = ContainerBag()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12))! }

    private var terms: LoanTerms {
        LoanTerms(kind: .personal, principal: 100_000, monthlyRate: Decimal(string: "0.0349")!, termMonths: 12,
                  firstDue: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!)
    }

    @Test("Ödendi: hesaptan gider, bütçeye girer; geri al gideri siler; önceden ödenenler kayıtsız (AC-I10-4)")
    func payAndUndo() throws {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        let ledger = LedgerStore(context: context)
        let cash = try #require(try ledger.defaultAccount())
        let store = LoanStore(context: context)
        let loan = try store.save(name: "İhtiyaç kredisi", terms: terms, paidCount: 2, accountID: cash.id, categoryID: nil)
        #expect(store.nextInstallment(of: loan, calendar: calendar)?.number == 3)

        let transaction = try #require(try store.markPaid(loan, account: cash, date: now, calendar: calendar))
        #expect(transaction.kind == .expense)
        #expect(transaction.amount == Money(Decimal(string: "10989.84")!, .TRY))
        #expect(transaction.merchantKey == "")
        #expect(loan.paidCount == 3)
        #expect(cash.balance == Money(Decimal(string: "-10989.84")!, .TRY))
        let month = LedgerMonth(containing: now, calendar: calendar)
        #expect(try ledger.summary(for: month, currency: .TRY, calendar: calendar).expense.amount == Decimal(string: "10989.84")!)

        // Kayıtsız işaretleme, sonra iki kez geri al: ilki yalnız sayıyı, ikincisi gideri de geri alır.
        #expect(try store.markPaid(loan, account: nil, date: now, calendar: calendar) == nil)
        #expect(loan.paidCount == 4)
        try store.undoLastPayment(loan)
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 1)
        try store.undoLastPayment(loan)
        #expect(loan.paidCount == 2)
        #expect(try context.fetchCount(FetchDescriptor<LedgerTransaction>()) == 0)
        // Uygulamadan önce ödenenler: kayıt yok, sayı düşer.
        try store.undoLastPayment(loan)
        #expect(loan.paidCount == 1)
    }

    @Test("Erken kapama gider yazar ve krediyi kapatır; geri alınabilir")
    func closeAndReopen() throws {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        let cash = try #require(try LedgerStore(context: context).defaultAccount())
        let store = LoanStore(context: context)
        let loan = try store.save(name: "Taşıt", terms: terms, paidCount: 3, accountID: cash.id, categoryID: nil)
        let payoff = try #require(store.payoff(of: loan, on: now, calendar: calendar))
        #expect(payoff.remainingPrincipal == Decimal(string: "79749.90")!)
        try store.close(loan, amount: payoff.total, account: cash, date: now)
        #expect(loan.isClosed)
        #expect(try store.loans(includeClosed: false).isEmpty)
        #expect(cash.balance == Money(-payoff.total, .TRY))
        #expect(try store.upcoming(from: now, through: now.addingTimeInterval(86_400 * 60), calendar: calendar).isEmpty)
        try store.reopen(loan)
        #expect(!loan.isClosed)
        #expect(cash.balance.isZero)
    }

    @Test("Örnek kredi takvimde ve yedekte")
    func demoCalendarAndBackup() throws {
        let context = try containers.make()
        try LedgerSeeder.seedIfNeeded(context, locale: Locale(identifier: "tr_TR"))
        try DemoData.load(into: context, now: now, calendar: calendar)
        let loan = try #require(try LoanStore(context: context).loans().first)
        #expect(loan.paidCount == 5)
        let items = try InsightStore(context: context).upcomingPayments(from: now, days: 31, now: now, calendar: calendar)
        let december5 = calendar.date(from: DateComponents(year: 2026, month: 12, day: 5))!
        #expect(items.contains { $0.source == .loan(loan.id) && $0.date == december5 })

        let data = try ExchangeStore(context: context).backupJSON(now: now)
        let other = try containers.make()
        try ExchangeStore(context: other).restore(data, mode: .replace)
        let restored = try #require(try LoanStore(context: other).loans().first)
        #expect(restored.id == loan.id)
        #expect(restored.terms == loan.terms)
        #expect(restored.paidCount == 5)
    }
}
