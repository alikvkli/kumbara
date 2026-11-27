import Foundation
import Testing
@testable import KumbaraCore

private struct Fixture: Decodable {
    let source: String
    let description: String
    let now: String
    let lines: [[Entry]]
    let expect: Expectation

    enum Entry: Decodable {
        case text(String), number(Double)
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) } else { self = .number(try c.decode(Double.self)) }
        }
    }

    struct DraftExpectation: Decodable {
        let amount: String
        let kind: String?
        let merchant: String?
        let date: String?
        let category: String?
    }

    struct Expectation: Decodable {
        let kind: String
        let amount: String?
        let merchant: String?
        let date: String?
        let category: String?
        let vat: String?
        let currency: String?
        let minAmountConfidence: Double?
        let maxAmountConfidence: Double?
        let maxMerchantConfidence: Double?
        let dateLowConfidence: Bool?
        let drafts: [DraftExpectation]?
    }

    var textLines: [TextLine] {
        lines.map { entry in
            guard case .text(let text) = entry[0], case .number(let x) = entry[1], case .number(let y) = entry[2] else {
                fatalError("Bozuk fixture satırı")
            }
            let confidence: Double = if entry.count > 3, case .number(let c) = entry[3] { c } else { 0.95 }
            return TextLine(text: text, box: TextBox(x: x, y: y, width: min(0.9, Double(text.count) * 0.012), height: 0.018),
                            confidence: confidence)
        }
    }
}

private var istanbul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return c
}

private func loadFixtures() throws -> [(name: String, fixture: Fixture)] {
    let dir = try #require(Bundle.module.url(forResource: "receipts", withExtension: nil, subdirectory: "Fixtures"))
    return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { ($0.deletingPathExtension().lastPathComponent, try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: $0))) }
}

private func expectDate(_ actual: Date, _ expected: String, _ name: String) {
    // "2026-11-27T14:35" ya da "2026-11-27"
    let parts = expected.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
    let c = istanbul.dateComponents([.year, .month, .day, .hour, .minute], from: actual)
    #expect([c.year, c.month, c.day] == [parts[0], parts[1], parts[2]], "\(name): tarih \(c)")
    if parts.count == 5 { #expect([c.hour, c.minute] == [parts[3], parts[4]], "\(name): saat \(c)") }
}

@Suite("Yakalama korpusu (specs/04 §6)")
struct CaptureCorpusTests {
    static let names: [String] = (try? loadFixtures().map(\.name)) ?? []

    @Test("Korpus örneği", arguments: names)
    func corpus(name: String) throws {
        let fixture = try #require(try loadFixtures().first { $0.name == name }?.fixture)
        let now = try #require(ISO8601DateFormatter().date(from: fixture.now))
        let result = CaptureParser(calendar: istanbul, now: now).parse(fixture.textLines)
        let e = fixture.expect

        #expect(result.kind.rawValue == e.kind, "\(name): tür \(result.kind)")

        if let drafts = e.drafts {
            #expect(result.drafts.count == drafts.count, "\(name): taslak sayısı \(result.drafts.count)")
            for (actual, expected) in zip(result.drafts, drafts) {
                #expect(actual.amount?.value == Decimal(canonical: expected.amount), "\(name): tutar")
                if let kind = expected.kind { #expect(actual.kind.rawValue == kind, "\(name): yön \(actual.kind)") }
                if let merchant = expected.merchant { #expect(actual.merchant?.value == merchant, "\(name): satıcı \(String(describing: actual.merchant?.value))") }
                if let date = expected.date { expectDate(actual.date.value, date, name) }
                if let category = expected.category { #expect(actual.categoryKey == category, "\(name): kategori \(String(describing: actual.categoryKey))") }
            }
            return
        }

        let draft = try #require(result.drafts.first, "\(name): taslak yok")
        if let amount = e.amount { #expect(draft.amount?.value == Decimal(canonical: amount), "\(name): tutar \(String(describing: draft.amount?.value))") }
        if let merchant = e.merchant { #expect(draft.merchant?.value == merchant, "\(name): satıcı \(String(describing: draft.merchant?.value))") }
        if let date = e.date { expectDate(draft.date.value, date, name) }
        if let category = e.category { #expect(draft.categoryKey == category, "\(name): kategori \(String(describing: draft.categoryKey))") }
        if let vat = e.vat { #expect(draft.vat == Decimal(canonical: vat), "\(name): KDV \(String(describing: draft.vat))") }
        if let currency = e.currency { #expect(draft.currency.rawValue == currency) }
        if let minimum = e.minAmountConfidence { #expect((draft.amount?.confidence ?? 0) >= minimum, "\(name): güven") }
        if let maximum = e.maxAmountConfidence { #expect((draft.amount?.confidence ?? 1) <= maximum, "\(name): güven") }
        if let maximum = e.maxMerchantConfidence { #expect((draft.merchant?.confidence ?? 1) <= maximum) }
        if e.dateLowConfidence == true { #expect(draft.date.isLowConfidence, "\(name): tarih güveni \(draft.date.confidence)") }
        #expect(!(draft.amount?.boxes.isEmpty ?? true), "\(name): tutarın kanıt kutusu yok")
    }

    @Test("Korpus boş değil ve hepsi yapay olarak işaretli")
    func corpusIsLabelled() throws {
        let fixtures = try loadFixtures()
        #expect(fixtures.count >= 12)
        #expect(fixtures.allSatisfy { ["synthetic", "device"].contains($0.fixture.source) })
    }
}

@Suite("Yakalama yardımcıları")
struct CaptureUnitTests {
    @Test("Tutar çıkarma: yalnız 2 küsuratlı sayılar", arguments: [
        ("*1.249,90", ["1249.9"]), ("TOPLAM *1.249,90", ["1249.9"]), ("-1.249,90 TL", ["1249.9"]), ("₺42,50", ["42.5"]),
        ("38,46 LT X 52,00", ["38.46", "52"]), ("TEL: 0216 555 12 12", []), ("FİŞ NO: 0042", []), ("%18", []),
        ("1 249,90", ["1249.9"]), ("$5.45", ["5.45"]), ("12.480,22 TL", ["12480.22"]),
        ("27.11.2026 13:05", []), ("Kartınızdan 27.11.2026 tarihinde 642,50 TL", ["642.5"]),
        // Gerçek OCR hataları (korpus): grup ayırıcısı virgül okunmuş, ayırıcıdan sonra boşluk.
        ("+2,863,04 TL", ["2863.04"]), ("520, 76", ["520.76"]), ("1,249.90", ["1249.9"]),
    ])
    func amounts(text: String, expected: [String]) {
        #expect(Extract.amounts(in: text).map(\.value) == expected.map { Decimal(canonical: $0)! })
    }

    @Test func signs() {
        #expect(Extract.amounts(in: "+3.500,00 TL").first?.sign == .plus)
        #expect(Extract.amounts(in: "−229,99").first?.sign == .minus)
        #expect(Extract.amounts(in: "229,99").first?.sign == Extract.Amount.Sign.none)
    }

    @Test("Tarih: sayısal, Türkçe ay, geçersiz ay reddedilir")
    func dates() {
        let d = { (s: String) in Extract.dates(in: CaptureText.fold(s), defaultYear: 2026).map { [$0.components.year!, $0.components.month!, $0.components.day!] } }
        #expect(d("27.11.2026") == [[2026, 11, 27]])
        #expect(d("27/11/26") == [[2026, 11, 27]])
        #expect(d("6 Kasım 2026") == [[2026, 11, 6]])
        #expect(d("27 KAS") == [[2026, 11, 27]])
        #expect(d("3 Ağustos 2025") == [[2025, 8, 3]])
        #expect(d("11/20/2026") == [])
    }

    @Test("Satır gruplama: aynı hizadaki parçalar soldan sağa birleşir")
    func rows() {
        let lines = [
            TextLine(text: "*1.249,90", box: TextBox(x: 0.7, y: 0.351, width: 0.2, height: 0.018)),
            TextLine(text: "TOPLAM", box: TextBox(x: 0.05, y: 0.35, width: 0.1, height: 0.018)),
            TextLine(text: "KREDİ KARTI", box: TextBox(x: 0.05, y: 0.38, width: 0.2, height: 0.018)),
        ]
        let rows = TextRow.group(lines)
        #expect(rows.map(\.text) == ["TOPLAM *1.249,90", "KREDİ KARTI"])
    }

    @Test("Eğik fotoğraf: sağ uç ~2° yukarıda olsa da satırlar doğru gruplanır")
    func skewedRows() {
        // 2°: genişliğin %70'i boyunca ~0,0125 yükseklik farkı; satır yüksekliği 0,02, satır aralığı 0,03
        let lines = [
            TextLine(text: "TOPKDV", box: TextBox(x: 0.05, y: 0.420, width: 0.12, height: 0.02)),
            TextLine(text: "*170,12", box: TextBox(x: 0.75, y: 0.4075, width: 0.15, height: 0.02)),
            TextLine(text: "TOPLAM", box: TextBox(x: 0.05, y: 0.450, width: 0.12, height: 0.02)),
            TextLine(text: "*1.249,90", box: TextBox(x: 0.72, y: 0.4375, width: 0.18, height: 0.02)),
        ]
        #expect(TextRow.group(lines).map(\.text) == ["TOPKDV *170,12", "TOPLAM *1.249,90"])
    }

    @Test("Bulanık anahtar kelime: OCR hataları")
    func fuzzy() {
        #expect(CaptureText.contains("t0plam *214,85", word: "toplam") == (true, false))
        #expect(CaptureText.contains("toplan", word: "toplam") == (true, false))
        #expect(CaptureText.contains("topkdv", word: "toplam").found == false)
        #expect(CaptureText.contains("kdv", word: "kdv") == (true, true))
    }

    @Test("Satıcı rehberi")
    func directory() {
        #expect(MerchantDirectory.lookup("MİGROS TİC. A.Ş.")?.displayName == "Migros")
        #expect(MerchantDirectory.lookup("Migros Ataşehir")?.categoryKey == "market.food")
        #expect(MerchantDirectory.lookup("BIMBO") == nil, "önek kelime bazında")
        #expect(MerchantDirectory.category(forText: "KADIKÖY AKARYAKIT") == "transport.fuel")
        #expect(CaptureParser.cleanMerchant("IŞIK ECZANESİ") == "Işık Eczanesi")
    }

    @Test("Mükerrer kontrolü (REQ-C6)")
    func duplicates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let day = Date(timeIntervalSince1970: 1_795_700_000)
        let existing = LedgerEntry(date: day, amount: Money(Decimal(string: "1249.90")!, .TRY), kind: .expense, merchant: "Migros")
        #expect(DuplicateCheck.isLikelyDuplicate(amount: Decimal(string: "1249.9")!, date: day.addingTimeInterval(3600),
                                                 merchant: "MİGROS ATAŞEHİR", existing: existing, calendar: cal))
        #expect(!DuplicateCheck.isLikelyDuplicate(amount: Decimal(string: "1249.9")!, date: day.addingTimeInterval(3 * 86_400),
                                                  merchant: "Migros", existing: existing, calendar: cal))
        #expect(!DuplicateCheck.isLikelyDuplicate(amount: 1250, date: day, merchant: "Migros", existing: existing, calendar: cal))
        #expect(!DuplicateCheck.isLikelyDuplicate(amount: Decimal(string: "1249.9")!, date: day, merchant: "Opet",
                                                  existing: existing, calendar: cal))
        #expect(DuplicateCheck.isLikelyDuplicate(amount: Decimal(string: "1249.9")!, date: day, merchant: nil,
                                                 existing: existing, calendar: cal))
    }
}
