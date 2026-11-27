import Foundation
import Testing
@testable import KumbaraCore

@Suite("CSV (specs/09 §3)")
struct CSVTests {
    @Test("Tırnak, ayırıcı, satır sonu ve kaçış gidiş-dönüşte korunur")
    func roundTrip() {
        let rows = [["Tarih", "Not"], ["01.11.2026", "Ali'nin \"doğum günü\"; pasta\nve mum"], ["02.11.2026", ""]]
        let text = CSV.encode(rows, delimiter: ";")
        #expect(text.hasPrefix(CSV.byteOrderMark))
        #expect(CSV.decode(text) == rows)
    }

    @Test("Ayırıcı ilk satırdan tahmin edilir")
    func detectsDelimiter() {
        #expect(CSV.detectDelimiter("Tarih;Tutar;Açıklama\n") == ";")
        #expect(CSV.detectDelimiter("date,amount,\"a;b\"\n") == ",")
        #expect(CSV.detectDelimiter("date\tamount\n") == "\t")
    }

    @Test("Boş satırlar atlanır, CRLF okunur")
    func skipsBlankLines() {
        #expect(CSV.decode("a,b\r\n\r\nc,d\r\n") == [["a", "b"], ["c", "d"]])
    }
}

@Suite("İşlem CSV'si")
struct TransactionCSVTests {
    private var istanbul: TimeZone { TimeZone(identifier: "Europe/Istanbul")! }

    @Test("Türkçe dışa aktarma: ; ayırıcı, işaretli tutar, virgüllü ondalık")
    func exportTurkish() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = istanbul
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 30))!
        let text = TransactionCSV.encode([
            ExportTransaction(date: date, kind: .expense, status: .posted, amount: Money(Decimal(string: "1249.9")!, .TRY),
                              account: "Kredi kartı", category: "Market", subcategory: "Gıda", merchant: "Migros"),
            ExportTransaction(date: date, kind: .income, status: .draft, amount: Money(62_000, .TRY), account: "Maaş"),
        ], locale: Locale(identifier: "tr_TR"), timeZone: istanbul)
        let rows = CSV.decode(text)
        #expect(rows[0].first == "Tarih")
        #expect(rows[1] == ["05.11.2026 14:30", "Gider", "-1249,90", "TRY", "Kredi kartı", "", "Market", "Gıda", "Migros", "", "Kesin"])
        #expect(rows[2][2] == "62000,00")
        #expect(rows[2][10] == "Taslak")
    }

    @Test("Dışa aktarılan dosya içe aktarmada aynı tutarları verir (AC-X4-1)")
    func exportImportRoundTrip() throws {
        let base = Date(timeIntervalSince1970: 1_793_000_000)
        var entries: [ExportTransaction] = []
        for index in 0..<50 {
            let kind: TransactionKind = index % 5 == 0 ? .income : .expense
            let amount = Decimal(index * 137 + 1) / 100
            entries.append(ExportTransaction(date: base.addingTimeInterval(Double(index) * 86_400), kind: kind,
                                             status: .posted, amount: Money(amount, .TRY), account: "Banka",
                                             merchant: "Satıcı \(index)"))
        }
        let tr = Locale(identifier: "tr_TR")
        let table = CSV.decode(TransactionCSV.encode(entries, locale: tr, timeZone: istanbul))
        let mapping = try #require(CSVImporter.guessMapping(for: table, timeZone: istanbul))
        #expect(mapping.hasHeader)
        #expect(mapping.date == 0)
        #expect(mapping.amount == CSVImportMapping.Amount.signed(column: 2, positiveIsExpense: false))
        #expect(mapping.decimalSeparator == ",")
        let result = CSVImporter.apply(CSVImportMapping(hasHeader: true, date: 0, amount: mapping.amount, description: 8,
                                                        dateFormat: mapping.dateFormat, decimalSeparator: ","),
                                       to: table, timeZone: istanbul)
        #expect(result.issues.isEmpty)
        #expect(result.rows.count == 50)
        var total = Decimal(0), expected = Decimal(0)
        for row in result.rows { total += row.kind == TransactionKind.expense ? -row.amount : row.amount }
        for entry in entries { expected += entry.kind == TransactionKind.expense ? -entry.amount.amount : entry.amount.amount }
        #expect(total == expected)
    }

    @Test("Banka ekstresi: borç/alacak sütunları, başlık ve tarih biçimi tahmini")
    func importBankStatement() throws {
        let text = """
        İşlem Tarihi;Açıklama;Borç;Alacak;Bakiye
        03/11/2026;MIGROS KADIKOY;1.249,90;;10.250,10
        05/11/2026;MAAS ODEMESI;;62.000,00;72.250,10
        07/11/2026;OPET;2.000,00;;70.250,10
        yanlış;satır;1,00;;0
        """
        let table = CSV.decode(text)
        let mapping = try #require(CSVImporter.guessMapping(for: Array(table.prefix(4))))
        #expect(mapping.date == 0)
        #expect(mapping.description == 1)
        #expect(mapping.amount == .split(debit: 2, credit: 3))
        #expect(mapping.dateFormat == "dd/MM/yyyy")
        let result = CSVImporter.apply(mapping, to: table)
        #expect(result.rows.map(\.amount) == [Decimal(string: "1249.9")!, 62_000, 2_000])
        #expect(result.rows.map(\.kind) == [.expense, .income, .expense])
        #expect(result.issues == [ImportIssue(line: 5, reason: .date)])
    }

    @Test("Kart ekstresi: eksi yoksa artılar harcamadır")
    func cardStatementPositiveIsExpense() throws {
        let table = CSV.decode("Tarih,Açıklama,Tutar\n2026-11-03,Netflix,229.99\n2026-11-04,Starbucks,185.00\n")
        let mapping = try #require(CSVImporter.guessMapping(for: table))
        #expect(mapping.amount == .signed(column: 2, positiveIsExpense: true))
        #expect(mapping.decimalSeparator == ".")
        #expect(CSVImporter.apply(mapping, to: table).rows.allSatisfy { $0.kind == .expense })
    }

    @Test("İki basamaklı yıl yanlış yüzyıla okunmaz")
    func twoDigitYear() {
        #expect(CSVImporter.guessDateFormat(["05.11.26", "06.11.26"]) == "dd.MM.yy")
    }

    @Test("Parmak izi: boşluk ve büyük/küçük harf farkı aynı satırdır")
    func fingerprint() {
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let a = ImportFingerprint.make(date: date, amount: 100, kind: .expense, description: "MIGROS  Kadıköy", calendar: calendar)
        let b = ImportFingerprint.make(date: date.addingTimeInterval(60), amount: 100, kind: .expense, description: "migros kadıköy", calendar: calendar)
        #expect(a == b)
        #expect(a != ImportFingerprint.make(date: date, amount: 100, kind: .income, description: "migros kadıköy", calendar: calendar))
    }
}
