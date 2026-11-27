import Foundation
import Testing
@testable import KumbaraCore

@Suite("Akıllı katman çapraz kontrolü (specs/04 §2.5)")
struct CrossCheckTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()
    let now = ISO8601DateFormatter().date(from: "2026-11-27T18:00:00+03:00")!

    /// Soldaki metin + sağdaki tutar, yukarıdan aşağı.
    func rows(_ items: [(String, String?)]) -> [TextRow] {
        var lines: [TextLine] = []
        for (index, item) in items.enumerated() {
            let y = 0.05 + Double(index) * 0.05
            lines.append(TextLine(text: item.0, box: TextBox(x: 0.05, y: y, width: 0.4, height: 0.02), confidence: 1))
            if let right = item.1 {
                lines.append(TextLine(text: right, box: TextBox(x: 0.7, y: y, width: 0.2, height: 0.02), confidence: 1))
            }
        }
        return TextRow.group(lines)
    }

    func parse(_ rows: [TextRow]) -> CapturedDraft {
        CaptureParser(calendar: calendar, now: now).parse(rows.flatMap(\.parts)).drafts[0]
    }

    var receipt: [TextRow] {
        rows([("MIGROS TIC. A.S.", nil), ("TARIH: 26.11.2026  SAAT: 14:35", nil), ("SUT 1L", "*42,50"),
              ("TOPLAM", "*1.249,90"), ("KREDI KARTI", "*1.249,90")])
    }

    @Test("Anlaşma güveni artırır")
    func agreement() {
        let rows = receipt
        let rule = parse(rows)
        let reading = ModelReading(amount: Decimal(string: "1249.90"), date: DateComponents(year: 2026, month: 11, day: 26),
                                   merchant: "Migros", categoryKey: "market.food")
        let result = CrossCheck.apply(reading, to: rule, rows: rows, calendar: calendar)
        #expect(result.amount?.value == Decimal(string: "1249.90"))
        #expect((result.amount?.confidence ?? 0) >= 0.97)
        #expect(result.modelCheck?.agreed.isSuperset(of: [.amount, .date, .category]) == true)
        #expect(result.modelCheck?.conflicts.isEmpty == true)
        #expect(result.merchant?.value == "Migros")  // bilinen zincir: model dokunmaz
    }

    @Test("Tutar anlaşmazlığında kural kazanır, güven düşer")
    func amountConflict() {
        let rows = receipt
        let rule = parse(rows)
        let result = CrossCheck.apply(ModelReading(amount: Decimal(string: "42.50")), to: rule, rows: rows, calendar: calendar)
        #expect(result.amount?.value == Decimal(string: "1249.90"))
        #expect(result.amount?.isLowConfidence == true)
        #expect(result.modelCheck?.conflicts == [.amount])
    }

    @Test("Metinde olmayan değer (uydurma) yok sayılır")
    func hallucination() {
        let rows = receipt
        let rule = parse(rows)
        let reading = ModelReading(amount: Decimal(string: "999.99"), date: DateComponents(year: 2026, month: 1, day: 3),
                                   merchant: "Starbucks", categoryKey: "not.a.key")
        let result = CrossCheck.apply(reading, to: rule, rows: rows, calendar: calendar)
        #expect(result.amount == rule.amount)
        #expect(result.date == rule.date)
        #expect(result.merchant == rule.merchant)
        #expect(result.categoryKey == rule.categoryKey)
        #expect(result.modelCheck == ModelCheck())
    }

    @Test("Kuralların bulamadığını metinde doğrulanan model değeri doldurur")
    func fills() {
        // Etiketsiz tutar, tarih yok, satıcı bilinmiyor.
        let rows = rows([("KOSE BUFE", nil), ("Fis 0042 - 26/11/2026", nil), ("TOST", "85,00"), ("AYRAN", "25,00"),
                         ("ODENECEK", nil), ("110,00", nil)])
        let rule = parse(rows)
        let reading = ModelReading(amount: Decimal(110), date: DateComponents(year: 2026, month: 11, day: 26),
                                   merchant: "Köşe Büfe", categoryKey: "dining.restaurant")
        let result = CrossCheck.apply(reading, to: rule, rows: rows, calendar: calendar)
        #expect(result.amount?.value == Decimal(110))
        #expect(calendar.dateComponents([.year, .month, .day], from: result.date.value) == DateComponents(year: 2026, month: 11, day: 26))
        #expect(result.categoryKey != nil)
        #expect(result.merchant != nil)
    }

    @Test("Kural tarihi güçlüyken farklı model tarihi çatışmadır")
    func dateConflict() {
        let rows = rows([("A101", nil), ("TARIH: 26.11.2026", nil), ("SKT 01.12.2026", nil), ("TOPLAM", "*50,00")])
        let rule = parse(rows)
        let result = CrossCheck.apply(ModelReading(date: DateComponents(year: 2026, month: 12, day: 1)), to: rule, rows: rows,
                                      calendar: calendar)
        #expect(calendar.component(.day, from: result.date.value) == 26)
        #expect(result.date.isLowConfidence)
        #expect(result.modelCheck?.conflicts == [.date])
    }
}
