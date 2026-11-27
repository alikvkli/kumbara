import Foundation
import Testing
@testable import KumbaraCore

@Suite("Ödeme takvimi (specs/10 §5)")
struct PaymentCalendarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Kira 1'i, kart 7'si, Netflix tahmini 9'u: 1 Aralık'ta 7 gün = kira + kart (AC-I5-1)")
    func sevenDays() {
        let cal = calendar
        let rent = PaymentCalendar.recurring(
            id: UUID(), title: "Kira", amount: 18_000, isIncome: false,
            schedule: RecurrenceSchedule(frequency: .monthly(day: 1), start: day(2026, 1, 1)),
            lastDue: day(2026, 11, 1), from: day(2026, 12, 1), through: day(2026, 12, 31), calendar: cal)
        let card = UpcomingPayment(id: "card", date: day(2026, 12, 7), amount: 3_400, title: "Kart", source: .card(UUID()))
        let netflix = SubscriptionDetector.Subscription(
            merchantKey: "netflix", name: "Netflix", cadence: .monthly,
            payments: [.init(date: day(2026, 11, 9), amount: 229, merchantKey: "netflix", merchantName: "Netflix")],
            previousAmount: nil, nextDue: day(2026, 12, 9), isMissed: false, isTracked: false)
        let estimates = PaymentCalendar.subscriptions([netflix], from: day(2026, 12, 1), through: day(2026, 12, 31), calendar: cal)
        #expect(estimates.count == 1)
        #expect(estimates.first?.isEstimate == true)

        let all = rent + [card] + estimates
        let week = PaymentCalendar.window(all, from: day(2026, 12, 1), days: 7, calendar: cal)
        #expect(week.items.map(\.title) == ["Kira", "Kart"])
        #expect(week.outgoing == 21_400)
        let month = PaymentCalendar.window(all, from: day(2026, 12, 1), days: 30, calendar: cal)
        #expect(month.items.map(\.title) == ["Kira", "Kart", "Netflix"])
    }

    @Test("Taslağı üretilmiş vade tekrar gösterilmez; gelir sayacı ve bakiye")
    func incomeAndBalance() throws {
        let cal = calendar
        let salary = PaymentCalendar.recurring(
            id: UUID(), title: "Maaş", amount: 60_000, isIncome: true,
            schedule: RecurrenceSchedule(frequency: .monthly(day: 1), start: day(2026, 1, 1)),
            lastDue: day(2026, 12, 1), from: day(2026, 11, 27), through: day(2027, 1, 31), calendar: cal)
        #expect(salary.map(\.date) == [day(2027, 1, 1)])
        let rent = UpcomingPayment(id: "rent", date: day(2026, 12, 3), amount: 18_000, title: "Kira", source: .recurring(UUID()))
        let next = try #require(PaymentCalendar.nextIncome(salary + [rent], from: day(2026, 11, 27), calendar: cal))
        #expect(next.days == 35)
        let balance = PaymentCalendar.balance(starting: 10_000, items: salary + [rent])
        #expect(balance.lowest == -8_000)
        #expect(balance.lowestDate == day(2026, 12, 3))
        #expect(balance.end == 52_000)
    }

    @Test("Kart: ödenmiş ekstre kalem değil; süren dönem 'şu ana kadar'")
    func cardItems() {
        let cal = calendar
        let cardID = UUID()
        let entries = [
            LedgerEntry(date: day(2026, 11, 10), amount: Money(1_000, .TRY), kind: .expense, accountID: cardID),
            LedgerEntry(date: day(2026, 11, 20), amount: Money(500, .TRY), kind: .expense, accountID: cardID),
            LedgerEntry(date: day(2026, 11, 22), amount: Money(1_000, .TRY), kind: .transfer, toAccountID: cardID),
        ]
        let statement = CardStatement(entries: entries, cardID: cardID, currency: .TRY, statementDay: 15, dueDay: 25,
                                      now: day(2026, 11, 27), calendar: cal)
        let items = PaymentCalendar.card(id: cardID, name: "Kart", statement: statement, from: day(2026, 11, 27),
                                         through: day(2027, 1, 31), calendar: cal)
        #expect(items.count == 1)
        #expect(items.first?.isPartial == true)
        #expect(items.first?.amount == 500)
        #expect(items.first?.date == day(2026, 12, 25))
    }
}
