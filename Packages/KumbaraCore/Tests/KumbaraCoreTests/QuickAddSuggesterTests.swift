import Foundation
import Testing
@testable import KumbaraCore

@Suite("Hızlı ekleme önerisi (specs/10 §6)")
struct QuickAddSuggesterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func coffee(_ date: Date, _ amount: Decimal = 185, merchant: String = "Kahve Dünyası") -> LedgerEntry {
        LedgerEntry(date: date, amount: Money(amount, .TRY), kind: .expense, categoryID: nil, merchant: merchant)
    }

    /// 2026-10-12 Pazartesi'den itibaren 6 hafta, hafta içi her gün 08:00–09:00 arası.
    private var weekdayCoffees: [LedgerEntry] {
        var result: [LedgerEntry] = []
        let start = at(2026, 10, 12, 8, 10)
        for week in 0..<6 {
            for day in 0..<5 {
                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start)!
                result.append(coffee(calendar.date(byAdding: .minute, value: (day * 11) % 45, to: date)!))
            }
        }
        return result
    }

    @Test("Hafta içi sabah kahvesi: Salı 08:30'da öneri, Cumartesi 08:30'da yok (AC-I6-1)")
    func weekdayMorning() throws {
        let tuesday = at(2026, 11, 24, 8, 30)
        let found = QuickAddSuggester.suggestions(entries: weekdayCoffees, now: tuesday, calendar: calendar)
        let first = try #require(found.first)
        #expect(first.merchant == "Kahve Dünyası")
        #expect(first.amount == 185)
        let saturday = at(2026, 11, 28, 8, 30)
        #expect(QuickAddSuggester.suggestions(entries: weekdayCoffees, now: saturday, calendar: calendar).isEmpty)
        // Akşam 20:00'de de yok.
        #expect(QuickAddSuggester.suggestions(entries: weekdayCoffees, now: at(2026, 11, 24, 20), calendar: calendar).isEmpty)
    }

    @Test("3 tekrarlı satıcı önerilmez; reddedilen önerilmez")
    func thresholds() {
        let few = (0..<3).map { coffee(at(2026, 11, 16 + $0, 8, 15), merchant: "Simitçi") }
        #expect(QuickAddSuggester.suggestions(entries: few, now: at(2026, 11, 24, 8, 30), calendar: calendar).isEmpty)
        #expect(QuickAddSuggester.suggestions(entries: weekdayCoffees, now: at(2026, 11, 24, 8, 30), calendar: calendar,
                                              dismissedKeys: ["kahve dunyasi"]).isEmpty)
    }

    @Test("Tutar: son üç aynıysa o tutar, değilse medyan")
    func amount() throws {
        var entries = (0..<4).map { coffee(at(2026, 11, 16 + $0, 8, 15), [150, 160, 200, 210][$0]) }
        let tuesday = at(2026, 11, 24, 8, 30)
        #expect(try #require(QuickAddSuggester.suggestions(entries: entries, now: tuesday, calendar: calendar).first).amount == 180)
        entries += [coffee(at(2026, 11, 20, 8, 20), 210), coffee(at(2026, 11, 23, 8, 20), 210)]
        #expect(try #require(QuickAddSuggester.suggestions(entries: entries, now: tuesday, calendar: calendar).first).amount == 210)
    }
}
