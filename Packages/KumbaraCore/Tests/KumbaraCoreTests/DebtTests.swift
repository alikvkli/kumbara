import Foundation
import Testing
@testable import KumbaraCore

@Suite("Alacak / borç (specs/10 §4)")
struct DebtTests {
    @Test("₺900 yemek, 3 kişi eşit: bütçeye ₺300; Ayşe ve Mehmet'ten ₺300'er; Ayşe ödeyince bakiye 0 (AC-I4-1)")
    func splitDinner() {
        let shares = DebtMath.equalShares(total: 900, others: 2)
        #expect(shares.mine == 300)
        #expect(shares.each == 300)
        let entry = LedgerEntry(date: .now, amount: Money(900, .TRY), kind: .expense, sharedAmount: 600)
        #expect(entry.ownAmount == Money(300, .TRY))
        let month = LedgerMonth(containing: .now, calendar: .current)
        let summary = MonthlySummary(entries: [entry], month: month, currency: .TRY, calendar: .current)
        #expect(summary.expense == Money(300, .TRY))
        // Hesaptan tamamı çıkar.
        let account = UUID()
        var paid = entry
        paid.accountID = account
        #expect(AccountBalance.compute(accountID: account, opening: Money(1_000, .TRY), entries: [paid]) == Money(100, .TRY))

        let ayse = UUID(), mehmet = UUID()
        var entries = [DebtEntry(personID: ayse, kind: .split, amount: 300, date: .now),
                       DebtEntry(personID: mehmet, kind: .split, amount: 300, date: .now)]
        #expect(DebtMath.totals(DebtMath.balances(entries)).receivable == 600)
        entries.append(DebtEntry(personID: ayse, kind: .settlement,
                                 amount: DebtMath.settlement(amount: 300, balance: 300), date: .now))
        let balances = DebtMath.balances(entries)
        #expect(balances[ayse] == 0)
        #expect(balances[mehmet] == 300)
    }

    @Test("Kuruş farkı sende kalır; verilen ve alınan borç")
    func roundingAndLoans() {
        let shares = DebtMath.equalShares(total: 1_000, others: 2)
        #expect(shares.each == Decimal(string: "333.33"))
        #expect(shares.mine == Decimal(string: "333.34"))
        let person = UUID()
        let entries = [DebtEntry(personID: person, kind: .lent, amount: 1_000, date: .now),
                       DebtEntry(personID: person, kind: .borrowed, amount: -1_500, date: .now)]
        let balance = DebtMath.balances(entries)[person]!
        #expect(balance == -500)
        #expect(DebtMath.totals([person: balance]).payable == 500)
        // Ben ödeyince borcum azalır (+).
        #expect(DebtMath.settlement(amount: 500, balance: balance) == 500)
        #expect(DebtMath.share(of: 900, percent: 40) == 360)
    }
}
