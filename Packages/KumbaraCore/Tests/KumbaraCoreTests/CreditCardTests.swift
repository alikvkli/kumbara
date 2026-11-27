import Foundation
import Testing
@testable import KumbaraCore

@Suite("Kredi kartı: ekstre ve taksit (specs/08 §3)")
struct CreditCardTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }

    @Test("AC-L8-1: kesim 15 → 15 Kasım Kasım dönemine, 16 Kasım Aralık dönemine")
    func periods() {
        let nov15 = StatementPeriod.containing(d(2026, 11, 15, hour: 23), statementDay: 15, calendar: calendar)
        #expect(nov15.start == d(2026, 10, 16) && nov15.closing == d(2026, 11, 15))
        #expect(nov15.due == d(2026, 11, 25))
        let nov16 = StatementPeriod.containing(d(2026, 11, 16, hour: 1), statementDay: 15, dueDay: 5, calendar: calendar)
        #expect(nov16.start == d(2026, 11, 16) && nov16.closing == d(2026, 12, 15))
        #expect(nov16.due == d(2027, 1, 5))
        // Kesim 31: Şubat'ta ayın son günü.
        let feb = StatementPeriod.containing(d(2027, 2, 10), statementDay: 31, calendar: calendar)
        #expect(feb.start == d(2027, 2, 1) && feb.closing == d(2027, 2, 28))
        #expect(feb.previous(statementDay: 31, dueDay: nil, calendar: calendar).closing == d(2027, 1, 31))
    }

    @Test("AC-L9-1: ₺1.000 / 3 = 333,34 + 333,33 + 333,33; toplam tam")
    func split() {
        let parts = Installments.split(1000, count: 3)
        #expect(parts == [Decimal(string: "333.34")!, Decimal(string: "333.33")!, Decimal(string: "333.33")!])
        #expect(parts.reduce(0, +) == 1000)
        #expect(Installments.split(Decimal(string: "12000")!, count: 12).allSatisfy { $0 == 1000 })
        #expect(Installments.split(Decimal(string: "99.99")!, count: 1) == [Decimal(string: "99.99")!])
        let odd = Installments.split(Decimal(string: "100")!, count: 7)
        #expect(odd.reduce(0, +) == 100 && odd[0] == Decimal(string: "14.32")!)
    }

    @Test("AC-L9-2: kesim 15, 20 Kasım alımı → taksitler 15 Aralık, 15 Ocak, 15 Şubat ekstrelerinde")
    func installmentDates() {
        let dates = Installments.dates(purchase: d(2026, 11, 20, hour: 14), count: 3, calendar: calendar)
        let closings = dates.map { StatementPeriod.containing($0, statementDay: 15, calendar: calendar).closing }
        #expect(closings == [d(2026, 12, 15), d(2027, 1, 15), d(2027, 2, 15)])
        // 31 Ocak alımı: Şubat'ta 28'i.
        let end = Installments.dates(purchase: d(2027, 1, 31, hour: 10), count: 2, calendar: calendar)
        #expect(calendar.component(.day, from: end[1]) == 28)
    }

    @Test("Kart özeti: bu dönem, son ekstre, ödeme düşer, gelecek taksitler")
    func statement() {
        let card = UUID(), bank = UUID()
        func e(_ amount: Decimal, _ date: Date, kind: TransactionKind = .expense, status: TransactionStatus = .posted,
               to: UUID? = nil, account: UUID? = nil) -> LedgerEntry {
            LedgerEntry(date: date, amount: Money(amount, .TRY), kind: kind, status: status,
                        accountID: account ?? card, toAccountID: to)
        }
        let entries = [
            e(1200, d(2026, 10, 20, hour: 12)), e(800, d(2026, 11, 10, hour: 12)),      // son dönem: 16 Eki–15 Kas
            e(100, d(2026, 11, 12, hour: 12), kind: .income),                           // iade
            e(500, d(2026, 11, 20, hour: 12)),                                          // bu dönem
            e(1000, d(2026, 11, 22, hour: 12), kind: .transfer, to: card, account: bank), // ödeme
            e(333, d(2026, 12, 20, hour: 12), status: .planned), e(333, d(2027, 1, 20, hour: 12), status: .planned),
        ]
        let s = CardStatement(entries: entries, cardID: card, currency: .TRY, statementDay: 15, dueDay: 25,
                              now: d(2026, 11, 27, hour: 12), calendar: calendar)
        #expect(s.lastStatement.amount == 1900)
        #expect(s.currentSpending.amount == 500)
        #expect(s.paidSinceClosing.amount == 1000)
        #expect(s.remainingDue.amount == 900)
        #expect(s.last.due == d(2026, 11, 25))
        #expect(s.upcomingInstallments.amount == 666)
    }
}
