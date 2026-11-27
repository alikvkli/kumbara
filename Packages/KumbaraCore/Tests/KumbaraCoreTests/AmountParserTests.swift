import Foundation
import Testing
@testable import KumbaraCore

@Suite("AmountParser")
struct AmountParserTests {
    let tr = AmountParser()
    let en = AmountParser(decimalSeparator: ".")

    @Test("Türkçe biçimler", arguments: [
        ("1.249,90", "1249.9"),
        ("1249,90", "1249.9"),
        ("*1.249,90", "1249.9"),
        ("1.249,90 TL", "1249.9"),
        ("₺1.249,90", "1249.9"),
        ("1.249,90₺", "1249.9"),
        ("TOPLAM *1.249,90", nil),          // etiket ayıklama ayrıştırıcının işi değil
        ("62.000", "62000"),
        ("1.234.567,89", "1234567.89"),
        ("12,5", "12.5"),
        ("12.5", "12.5"),                    // tek nokta + 3 olmayan basamak → ondalık
        ("1,249", "1.249"),                  // TR'de tek virgül ondalıktır
        ("0,99", "0.99"),
        (",5", "0.5"),
        ("250", "250"),
        ("  250  ", "250"),
        ("-12,50", "-12.5"),
        ("−12,50", "-12.5"),                 // U+2212
        ("12,50-", "-12.5"),                 // bazı banka ekstreleri
        ("1,249.90", "1249.9"),              // İngilizce biçim TR ayarında da çözülür
        ("1 249,90", "1249.9"),              // boşlukla gruplama
    ])
    func turkish(input: String, expected: String?) {
        #expect(tr.parse(input) == expected.flatMap { Decimal(canonical: $0) })
    }

    @Test("İngilizce yerel ayar", arguments: [
        ("1,249.90", "1249.9"),
        ("1,249", "1249"),
        ("1.249", "1.249"),
        ("12,5", "12.5"),
        ("$50.00", "50"),
    ])
    func english(input: String, expected: String) {
        #expect(en.parse(input) == Decimal(canonical: expected))
    }

    @Test("Geçersiz girişler", arguments: [
        "", "-", "TL", "abc", "12a", "1.24.9", "1.2345,00", "12,34,56,7", "1,234.5,6", "1.2,3.4", "12,", "--5", "1e5",
    ])
    func invalid(input: String) { #expect(tr.parse(input) == nil) }

    @Test("Yerel ayardan ondalık ayırıcı")
    func fromLocale() {
        #expect(AmountParser(locale: Locale(identifier: "tr_TR")).decimalSeparator == ",")
        #expect(AmountParser(locale: Locale(identifier: "en_US")).decimalSeparator == ".")
    }
}
