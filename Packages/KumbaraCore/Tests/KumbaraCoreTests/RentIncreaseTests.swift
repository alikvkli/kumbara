import Foundation
import Testing
@testable import KumbaraCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@Suite("Kira artışı (specs/12)")
struct RentIncreaseTests {
    private let table = CPIData.turkey

    /// TÜİK'in açıkladığı "12 aylık ortalamalara göre değişim" oranları (bültenler ve haberler).
    @Test("Gömülü TÜFE tablosu TÜİK'in açıkladığı 12 aylık ortalamaları verir (AC-I9-1)", arguments: [
        (LedgerMonth(year: 2024, month: 6), "0.6507"),  // Temmuz 2024 kira artışı %65,07
        (LedgerMonth(year: 2024, month: 12), "0.5851"), // 2024 ortalaması %58,51
        (LedgerMonth(year: 2025, month: 12), "0.3488"), // 2025 ortalaması %34,88
        (LedgerMonth(year: 2026, month: 6), "0.3203"),  // Temmuz 2026 kira artışı %32,03
    ])
    func matchesPublished(month: LedgerMonth, expected: String) {
        #expect(RentIncrease.averageChange(for: month, cpi: table) == Decimal(string: expected))
    }

    @Test("Ortalama elle hesaplanan küçük tabloyla aynı")
    func handVector() {
        // İlk 12 ay 100, sonraki 12 ay 110 → %10.
        var index: [LedgerMonth: Decimal] = [:]
        var month = LedgerMonth(year: 2024, month: 1)
        for i in 0..<24 {
            index[month] = i < 12 ? 100 : 110
            month = month.next
        }
        let cpi = RealReturn.CPITable(index)
        #expect(RentIncrease.averageChange(for: LedgerMonth(year: 2025, month: 12), cpi: cpi) == Decimal(string: "0.1"))
        // Bir ay eksik → hesaplanmaz.
        #expect(RentIncrease.averageChange(for: LedgerMonth(year: 2026, month: 1), cpi: cpi) == nil)
    }

    @Test("Temmuz'da yenilenen ₺20.000 kira: Haziran oranı, en fazla ₺26.406 (AC-I9-2)")
    func julyRenewal() throws {
        let quote = RentIncrease.quote(start: date(2025, 7, 15), currentRent: 20_000, now: date(2026, 7, 1),
                                       cpi: table, calendar: calendar)
        #expect(quote.renewal == calendar.startOfDay(for: date(2026, 7, 15)))
        #expect(quote.year == 2)
        #expect(quote.referenceMonth == LedgerMonth(year: 2026, month: 6))
        #expect(quote.source == .table)
        #expect(quote.maximumRent == 26_406)
        #expect(quote.maximumIncrease == 6_406)
        #expect(quote.exceeds(27_000) == true)
        #expect(quote.exceeds(26_000) == false)
        #expect(!quote.isPastFiveYears)
    }

    @Test("Oran tabloda yoksa tahmin yok; elle girilen aynı ayın oranı kullanılır (AC-I9-3)")
    func missingMonth() throws {
        // Aralık 2026 yenilemesi Kasım 2026 verisini ister; tablo Ekim'de bitiyor.
        let missing = RentIncrease.quote(start: date(2024, 12, 1), currentRent: 15_000, now: date(2026, 11, 28),
                                         cpi: table, calendar: calendar)
        #expect(missing.referenceMonth == LedgerMonth(year: 2026, month: 11))
        #expect(missing.rate == nil)
        #expect(missing.maximumRent == nil)
        #expect(missing.exceeds(20_000) == nil)

        let wrongMonth = RentIncrease.quote(start: date(2024, 12, 1), currentRent: 15_000, now: date(2026, 11, 28), cpi: table,
                                            manualRate: (LedgerMonth(year: 2026, month: 10), Decimal(string: "0.31")!),
                                            calendar: calendar)
        #expect(wrongMonth.rate == nil)

        let manual = RentIncrease.quote(start: date(2024, 12, 1), currentRent: 15_000, now: date(2026, 11, 28), cpi: table,
                                        manualRate: (LedgerMonth(year: 2026, month: 11), Decimal(string: "0.3105")!),
                                        calendar: calendar)
        #expect(manual.source == .manual)
        #expect(manual.maximumRent == Decimal(string: "19657.5"))

        // Tablo o ayı biliyorsa elle girilen oran yok sayılır.
        let table = RentIncrease.quote(start: date(2025, 7, 15), currentRent: 20_000, now: date(2026, 7, 1), cpi: self.table,
                                       manualRate: (LedgerMonth(year: 2026, month: 6), Decimal(string: "0.5")!),
                                       calendar: calendar)
        #expect(table.source == .table)
    }

    @Test("Yenileme: son 45 gün içindeyse o, değilse sıradaki; 5 yıl bilgisi")
    func renewalSelection() {
        let start = date(2020, 3, 10)
        let recent = RentIncrease.relevantRenewal(start: start, now: date(2026, 4, 20), calendar: calendar)
        #expect(recent.date == calendar.startOfDay(for: date(2026, 3, 10)))
        #expect(recent.year == 7)
        let upcoming = RentIncrease.relevantRenewal(start: start, now: date(2026, 5, 1), calendar: calendar)
        #expect(upcoming.date == calendar.startOfDay(for: date(2027, 3, 10)))
        #expect(upcoming.year == 8)
        let beforeFirst = RentIncrease.relevantRenewal(start: date(2026, 9, 1), now: date(2026, 10, 1), calendar: calendar)
        #expect(beforeFirst.year == 2)
        #expect(beforeFirst.date == calendar.startOfDay(for: date(2027, 9, 1)))

        let quote = RentIncrease.quote(start: start, currentRent: 10_000, now: date(2026, 4, 20), cpi: table, calendar: calendar)
        #expect(quote.isPastFiveYears)
    }

    @Test("Ortalama düştüyse artış yok")
    func deflation() {
        let quote = RentIncrease.Quote(renewal: date(2026, 1, 1), year: 2, referenceMonth: LedgerMonth(year: 2025, month: 12),
                                       currentRent: 10_000, rate: Decimal(string: "-0.01"), source: .manual)
        #expect(quote.maximumRent == 10_000)
        #expect(quote.maximumIncrease == 0)
    }

    @Test("TÜİK yayın günü: ertesi ayın 3'ü")
    func publication() {
        let day = RentIncrease.publicationDate(of: LedgerMonth(year: 2026, month: 11), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: day) == DateComponents(year: 2026, month: 12, day: 3))
    }
}
