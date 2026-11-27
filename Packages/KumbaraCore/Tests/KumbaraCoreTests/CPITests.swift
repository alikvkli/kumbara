import Foundation
import Testing
@testable import KumbaraCore

@Suite("Gömülü TÜFE ve enflasyon karşılaştırması (specs/09 §5)")
struct CPITests {
    private let table = CPIData.turkey
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func ratio(_ a: LedgerMonth, _ b: LedgerMonth) throws -> Double {
        let x = try #require(table.index[a]), y = try #require(table.index[b])
        return (x / y as NSDecimalNumber).doubleValue
    }

    @Test("Tablo 2018 Ocak'tan son açıklanan aya kesintisiz")
    func continuous() {
        #expect(table.latest?.month == LedgerMonth(year: 2026, month: 10))
        var month = LedgerMonth(year: 2018, month: 1)
        var count = 0
        while month <= LedgerMonth(year: 2026, month: 10) {
            #expect(table.index[month] != nil, "\(month) eksik")
            month = month.next
            count += 1
        }
        #expect(count == 106)
    }

    @Test("Zincirleme: baz değişimi aylık ve yıllık oranları korur")
    func chainedRatios() throws {
        // TÜİK: Ocak 2025 aylık %5,03; Aralık 2025 yıllık %30,89; Aralık 2024 yıllık %44,38.
        #expect(abs(try ratio(LedgerMonth(year: 2025, month: 1), LedgerMonth(year: 2024, month: 12)) - 1.0503) < 0.0001)
        #expect(abs(try ratio(LedgerMonth(year: 2025, month: 12), LedgerMonth(year: 2024, month: 12)) - 1.3089) < 0.0001)
        #expect(abs(try ratio(LedgerMonth(year: 2024, month: 12), LedgerMonth(year: 2023, month: 12)) - 1.4438) < 0.0001)
    }

    @Test("Enflasyon karşılaştırması: tablonun son ayından sonraki alım enflasyonsuz sayılır")
    func benchmarkAfterLatestMonth() throws {
        let buyJan = Trade(asset: .gold(.gram24), side: .buy, quantity: 1, unitPrice: 10_000,
                           date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!)
        let buyNov = Trade(asset: .gold(.gram24), side: .buy, quantity: 1, unitPrice: 10_000,
                           date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!)
        let value = try #require(RealReturn.cpiBenchmark(trades: [buyJan, buyNov], cpi: table, calendar: calendar))
        let expected = 10_000 * (try ratio(LedgerMonth(year: 2026, month: 10), LedgerMonth(year: 2026, month: 1))) + 10_000
        #expect(abs((value as NSDecimalNumber).doubleValue - expected) < 0.01)
    }
}
