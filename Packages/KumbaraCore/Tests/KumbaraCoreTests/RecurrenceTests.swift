import Foundation
import Testing
@testable import KumbaraCore

@Suite("Tekrarlayan işlemler (specs/08 §2)")
struct RecurrenceTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }

    @Test("AC-L7-1: her ayın 31'i → Şubat'ta 28/29, Nisan'da 30")
    func monthEnd() {
        let schedule = RecurrenceSchedule(frequency: .monthly(day: 31), start: d(2027, 1, 1))
        let dates = Array(schedule.occurrences(calendar: calendar).prefix(4))
        #expect(dates == [d(2027, 1, 31), d(2027, 2, 28), d(2027, 3, 31), d(2027, 4, 30)])
        let leap = RecurrenceSchedule(frequency: .monthly(day: 31), start: d(2028, 2, 1))
        #expect(leap.occurrences(calendar: calendar).first == d(2028, 2, 29))
    }

    @Test("AC-L7-2: 3 ay açılmazsa 3 vade; aynı gün tekrar çağrı yeni vade üretmez")
    func catchUpAndIdempotent() {
        let schedule = RecurrenceSchedule(frequency: .monthly(day: 1), start: d(2026, 8, 1))
        let first = schedule.due(after: d(2026, 8, 1), through: d(2026, 11, 27, hour: 18), calendar: calendar)
        #expect(first == [d(2026, 9, 1), d(2026, 10, 1), d(2026, 11, 1)])
        let again = schedule.due(after: first.last, through: d(2026, 11, 27, hour: 20), calendar: calendar)
        #expect(again.isEmpty)
        // Hiç üretilmemişse başlangıç vadesi de dahil; bugün vadesi olan dahil.
        #expect(schedule.due(after: nil, through: d(2026, 9, 1, hour: 8), calendar: calendar) == [d(2026, 8, 1), d(2026, 9, 1)])
    }

    @Test("Haftalık, yıllık, 3 ayda bir; bitiş tarihi ve tekrar sayısı")
    func frequencies() {
        // 27 Kasım 2026 Cuma; Pazartesi = 2
        let weekly = RecurrenceSchedule(frequency: .weekly(weekday: 2), start: d(2026, 11, 27), maxCount: 3)
        #expect(weekly.occurrences(calendar: calendar) == [d(2026, 11, 30), d(2026, 12, 7), d(2026, 12, 14)])

        let yearly = RecurrenceSchedule(frequency: .yearly(month: 2, day: 29), start: d(2026, 3, 1), end: d(2029, 1, 1))
        #expect(yearly.occurrences(calendar: calendar) == [d(2027, 2, 28), d(2028, 2, 29)])

        let quarterly = RecurrenceSchedule(frequency: .monthly(day: 15, interval: 3), start: d(2026, 1, 10))
        #expect(Array(quarterly.occurrences(calendar: calendar).prefix(3)) == [d(2026, 1, 15), d(2026, 4, 15), d(2026, 7, 15)])

        #expect(RecurrenceSchedule(frequency: .monthly(day: 5), start: d(2026, 11, 1))
            .nextDue(after: d(2026, 11, 27), calendar: calendar) == d(2026, 12, 5))
    }

    @Test("Kanonik metin gidip gelir; bozuk değer reddedilir")
    func canonical() {
        for value in [RecurrenceFrequency.monthly(day: 31, interval: 1), .weekly(weekday: 7), .yearly(month: 3, day: 15)] {
            #expect(RecurrenceFrequency(canonical: value.canonical) == value)
        }
        #expect(RecurrenceFrequency(canonical: "m:32:1") == nil)
        #expect(RecurrenceFrequency(canonical: "w:0") == nil)
        #expect(RecurrenceFrequency(canonical: "x") == nil)
    }
}
