import Foundation
import KumbaraCore
import SwiftData
import Testing
@testable import KumbaraData

@MainActor
@Suite("InstallmentStore (specs/08 §3)")
struct InstallmentStoreTests {
    let container: ModelContainer
    let ledger: LedgerStore
    let installments: InstallmentStore
    let card: LedgerAccount
    var calendar = Calendar(identifier: .gregorian)

    init() throws {
        container = try KumbaraContainer.make(inMemory: true)
        ledger = LedgerStore(context: container.mainContext)
        installments = InstallmentStore(context: container.mainContext)
        try LedgerSeeder.seedIfNeeded(container.mainContext, locale: Locale(identifier: "tr_TR"))
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        card = LedgerAccount(name: "Kart", kind: .card, currency: .TRY, sortIndex: 1)
        card.statementDay = 15
        container.mainContext.insert(card)
        try container.mainContext.save()
    }

    func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: day, hour: 14))!
    }

    @Test("₺1.000 / 3 taksit: ilki kesin, diğerleri planlı; bütçeye yalnız o ayın taksiti; tarihi gelince kesinleşir")
    func plan() throws {
        let category = try #require(try ledger.category(seedKey: "clothing"))
        let parts = try installments.save(TransactionDraft(amount: 1000, date: d(2026, 11, 20), account: card.ref,
                                                           category: category.ref, merchant: "Zara"),
                                          count: 3, now: d(2026, 11, 20), calendar: calendar)
        #expect(parts.map(\.amount.amount) == [Decimal(string: "333.34")!, Decimal(string: "333.33")!, Decimal(string: "333.33")!])
        #expect(parts.map(\.status) == [.posted, .planned, .planned])
        #expect(parts.map { $0.installmentIndex ?? 0 } == [1, 2, 3])
        #expect(Set(parts.compactMap(\.installmentPlanID)).count == 1)

        let november = try ledger.summary(for: LedgerMonth(year: 2026, month: 11), currency: .TRY, calendar: calendar)
        #expect(november.expense.amount == Decimal(string: "333.34"))
        #expect(card.balance.amount == Decimal(string: "-333.34"))

        #expect(try installments.postDue(now: d(2026, 12, 21)) == 1)
        #expect(parts[1].status == .posted)

        let statement = try #require(try installments.statement(for: card, now: d(2026, 12, 21), calendar: calendar))
        #expect(statement.lastStatement.amount == Decimal(string: "333.34"))  // 16 Kas–15 Ara
        #expect(statement.currentSpending.amount == Decimal(string: "333.33")) // 20 Ara taksiti
        #expect(statement.upcomingInstallments.amount == Decimal(string: "333.33"))

        try installments.cancelRemaining(of: try #require(parts[0].installmentPlanID))
        #expect(installments.upcomingInstallments(for: card).isEmpty)
        #expect(parts[0].status == .posted && parts[1].status == .posted)
    }
}
