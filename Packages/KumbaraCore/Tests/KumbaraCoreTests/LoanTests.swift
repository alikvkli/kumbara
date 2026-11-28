import Foundation
import Testing
@testable import KumbaraCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

@Suite("Kredi (specs/13)")
struct LoanTests {
    /// ₺100.000, aylık %3,49, KKDF + BSMV %30, 12 ay.
    private let personal = LoanTerms(kind: .personal, principal: 100_000, monthlyRate: dec("0.0349"), termMonths: 12,
                                     firstDue: date(2026, 1, 15))

    @Test("Taksit vergi dahil efektif oranla: ₺10.989,84 (AC-I10-1)")
    func payment() {
        #expect(personal.taxRate == dec("0.30"))
        #expect(personal.installment == dec("10989.84"))
        #expect(LoanTerms(kind: .housing, principal: 2_000_000, monthlyRate: dec("0.0279"), termMonths: 120,
                          firstDue: date(2026, 1, 1)).installment == dec("57932.14"))
        #expect(LoanMath.payment(principal: 12_000, effectiveRate: 0, term: 12) == 1_000)
    }

    @Test("Ödeme planı: faiz, vergi, anapara; son taksit kalanı kapatır")
    func schedule() throws {
        let rows = LoanMath.schedule(personal, calendar: calendar)
        #expect(rows.count == 12)
        let first = try #require(rows.first)
        #expect(first.interest == 3_490)
        #expect(first.tax == 1_047)
        #expect(first.principal == dec("6452.84"))
        #expect(first.balanceAfter == dec("93547.16"))
        #expect(rows[1].interest == dec("3264.80"))
        let last = try #require(rows.last)
        #expect(last.payment == dec("10989.89"))
        #expect(last.balanceAfter == 0)
        let totals = LoanMath.totals(rows)
        #expect(totals.paid == dec("131878.13"))
        #expect(totals.interest == dec("24521.63"))
        #expect(totals.tax == dec("7356.50"))
    }

    @Test("Vadeler her ay aynı gün; kısa ayda ayın son günü, kayma yok")
    func dueDates() {
        let terms = LoanTerms(kind: .personal, principal: 1_000, monthlyRate: dec("0.03"), termMonths: 3,
                              firstDue: date(2026, 1, 31))
        let rows = LoanMath.schedule(terms, calendar: calendar)
        #expect(rows.map(\.due) == [date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31)])
    }

    @Test("Taksitten faiz oranı bulunur (AC-I10-2)")
    func solveRate() {
        #expect(LoanMath.solveRate(principal: 100_000, payment: dec("10989.84"), term: 12, taxRate: dec("0.30")) == dec("0.0349"))
        #expect(LoanMath.solveRate(principal: 2_000_000, payment: dec("57932.14"), term: 120, taxRate: 0) == dec("0.0279"))
        #expect(LoanMath.solveRate(principal: 12_000, payment: 1_000, term: 12, taxRate: dec("0.30")) == 0)
        #expect(LoanMath.solveRate(principal: 12_000, payment: 900, term: 12, taxRate: dec("0.30")) == nil)
    }

    @Test("Erken kapama: kalan anapara + işlemiş faiz ve vergisi; ihtiyaç kredisinde tazminat yok (AC-I10-3)")
    func payoffPersonal() throws {
        // 3 taksit ödendi; 3. vadeden (15 Mart) 15 gün sonra.
        let payoff = try #require(LoanMath.payoff(personal, paidCount: 3, on: date(2026, 3, 30), calendar: calendar))
        #expect(payoff.remainingPrincipal == dec("79749.90"))
        #expect(payoff.accruedInterest == dec("1391.64"))
        #expect(payoff.accruedTax == dec("417.49"))
        #expect(payoff.fee == 0)
        #expect(payoff.total == dec("81559.03"))
        #expect(payoff.scheduledRemaining == dec("98908.61"))
        #expect(payoff.saved == dec("17349.58"))
        #expect(payoff.remainingInstallments == 9)
        #expect(LoanMath.payoff(personal, paidCount: 12, on: date(2027, 1, 1), calendar: calendar) == nil)
    }

    @Test("Sabit faizli konut: kalan vade > 36 ay %2, ≤ 36 ay %1; değişken faizde yok")
    func payoffHousing() throws {
        var housing = LoanTerms(kind: .housing, principal: 2_000_000, monthlyRate: dec("0.0279"), termMonths: 120,
                                firstDue: date(2026, 1, 1))
        let early = try #require(LoanMath.payoff(housing, paidCount: 12, on: date(2026, 12, 1), calendar: calendar))
        #expect(early.remainingPrincipal == dec("1970099.08"))
        #expect(early.accruedInterest == 0)
        #expect(early.fee == dec("39401.98"))
        #expect(early.saved == dec("4247169.46"))
        let lastDue = LoanMath.dueDate(housing, number: 96, calendar: calendar)
        let late = try #require(LoanMath.payoff(housing, paidCount: 96, on: lastDue, calendar: calendar))
        #expect(late.remainingInstallments == 24)
        #expect(late.fee == dec("10036.80"))
        housing.isVariableRate = true
        #expect(LoanMath.payoff(housing, paidCount: 12, on: date(2026, 12, 1), calendar: calendar)?.fee == 0)
    }

    @Test("Takvime yalnız ödenmemiş taksitler pencere içinde düşer")
    func calendarItems() {
        let id = UUID()
        let items = PaymentCalendar.loan(id: id, title: "İhtiyaç kredisi", terms: personal, paidCount: 2,
                                         from: date(2026, 2, 20), through: date(2026, 5, 1), calendar: calendar)
        #expect(items.map(\.date) == [date(2026, 3, 15), date(2026, 4, 15)])
        #expect(items.allSatisfy { $0.amount == dec("10989.84") && $0.source == .loan(id) && !$0.isIncome })
        let none = PaymentCalendar.loan(id: id, title: "x", terms: personal, paidCount: 4,
                                        from: date(2026, 2, 20), through: date(2026, 4, 1), calendar: calendar)
        #expect(none.isEmpty)
    }
}
