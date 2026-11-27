import Foundation
import Testing
@testable import KumbaraCore

@Suite("Alabilir miyim? (specs/10 §3)")
struct PurchasePlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("₺12.000, 6 taksit, kesim 20'si, alım 22 Kasım: Kasım'a ₺2.000; ilk taksit Aralık ekstresinde (AC-I3-1)")
    func installments() throws {
        let context = PurchasePlanner.Context(today: date(2026, 11, 22), remaining: 9_000, hasBudget: true, monthlySaving: nil)
        let card = PurchasePlanner.Card(statementDay: 20, dueDay: 30)
        let scenarios = PurchasePlanner.scenarios(amount: 12_000, counts: [1, 6], context: context, card: card, calendar: calendar)
        let cash = try #require(scenarios.first)
        #expect(cash.thisMonth == 12_000)
        #expect(cash.shortfall == 3_000)
        #expect(cash.perDayAfter == 0)
        let six = try #require(scenarios.last)
        #expect(six.installment == 2_000)
        #expect(six.thisMonth == 2_000)
        #expect(six.schedule.count == 6)
        #expect(six.schedule.last?.month == LedgerMonth(year: 2027, month: 4))
        #expect(six.remainingAfter == 7_000)
        // 22 Kasım, 20 Kasım kesiminden sonra: 20 Aralık ekstresi, son ödeme 30 Aralık.
        #expect(calendar.startOfDay(for: try #require(six.firstDue)) == calendar.startOfDay(for: date(2026, 12, 30)))
        // 9 gün kaldı (22–30 Kasım): ₺9.000 → ₺1.000/gün; sonra ₺7.000 → ₺778.
        #expect(six.perDayBefore == 1_000)
        #expect(six.perDayAfter == 778)
    }

    @Test("Kart limiti yetmezse işaretlenir")
    func limit() {
        let context = PurchasePlanner.Context(today: date(2026, 11, 22), remaining: 9_000, hasBudget: true, monthlySaving: nil)
        let card = PurchasePlanner.Card(statementDay: 20, dueDay: 30, availableLimit: 10_000)
        let scenarios = PurchasePlanner.scenarios(amount: 12_000, counts: [3], context: context, card: card, calendar: calendar)
        #expect(scenarios.first?.exceedsLimit == true)
    }

    @Test("Hedef gecikmesi: ayda ₺10.000 birikim, ₺45.000 kalan, ₺12.000 alım → 5 aydan 6 aya")
    func goalDelay() throws {
        let impact = try #require(PurchasePlanner.goalImpact(amount: 12_000, goal: .init(name: "Düğün", remaining: 45_000),
                                                             monthlySaving: 10_000))
        #expect(impact.monthsBefore == 5)
        #expect(impact.monthsAfter == 6)
        #expect(impact.delay == 1)
        #expect(PurchasePlanner.goalImpact(amount: 12_000, goal: .init(name: "Ev", remaining: 45_000), monthlySaving: -500) == nil)
    }

    @Test("Birikim hızı için 3 ay veri gerekir (K6)")
    func savingRate() {
        let entries = [8, 9, 10].flatMap { month in
            [LedgerEntry(date: date(2026, month, 1), amount: Money(60_000, .TRY), kind: .income),
             LedgerEntry(date: date(2026, month, 5), amount: Money(Decimal(45_000 + month * 1_000), .TRY), kind: .expense)]
        }
        #expect(PurchasePlanner.monthlySaving(entries: entries, before: LedgerMonth(year: 2026, month: 11), calendar: calendar) == 6_000)
        #expect(PurchasePlanner.monthlySaving(entries: entries, before: LedgerMonth(year: 2026, month: 10), calendar: calendar) == nil)
    }
}
