import Foundation
import Testing
@testable import KumbaraCore

private func d(_ s: String) -> Decimal { Decimal(canonical: s)! }

@Suite("CurrencyCode")
struct CurrencyCodeTests {
    @Test("Geçerli ISO kodu", arguments: ["TRY", "USD", "XAU"])
    func valid(code: String) { #expect(CurrencyCode(rawValue: code)?.rawValue == code) }

    @Test("Geçersiz kod reddedilir", arguments: ["", "try", "TR", "TRYY", "T1Y", "TRŞ"])
    func invalid(code: String) { #expect(CurrencyCode(rawValue: code) == nil) }

    @Test func minorUnits() {
        #expect(CurrencyCode.TRY.minorUnits == 2)
        #expect(CurrencyCode(rawValue: "JPY")!.minorUnits == 0)
        #expect(CurrencyCode(rawValue: "KWD")!.minorUnits == 3)
    }
}

@Suite("Decimal kanonik biçim (C3)")
struct DecimalCanonicalTests {
    @Test("Gidiş-dönüş", arguments: ["0", "1234.56", "-0.001", "0.00000001", "100000000000000000000", "5925.33"])
    func roundTrip(raw: String) {
        let value = Decimal(canonical: raw)
        #expect(value != nil)
        #expect(value.map { Decimal(canonical: $0.canonicalString) } == value)
    }

    @Test("Kanonik olmayan reddedilir", arguments: ["", "-", ".5", "5.", "1,5", "1.234.5", "1e3", " 1", "+1", "١٢"])
    func rejects(raw: String) { #expect(Decimal(canonical: raw) == nil) }

    @Test func trailingZerosNormalized() { #expect(d("1234.560").canonicalString == "1234.56") }

    @Test("Yuvarlama yarımda sıfırdan uzağa")
    func rounding() {
        #expect(d("2.5").rounded(scale: 0) == 3)
        #expect(d("-2.5").rounded(scale: 0) == -3)
        #expect(d("1.005").rounded(scale: 2) == d("1.01"))
        #expect(d("13.9423").rounded(scale: 2) == d("13.94"))
    }

    @Test("Decimal ondalık toplamı tam (Double değil)")
    func noFloatingError() {
        #expect(d("0.1") + d("0.2") == d("0.3"))
    }
}

@Suite("Money")
struct MoneyTests {
    @Test func arithmetic() {
        let a = Money(d("1249.90"), .TRY)
        let b = Money(d("750.10"), .TRY)
        #expect(a + b == Money(2000, .TRY))
        #expect(a - b == Money(d("499.80"), .TRY))
        #expect(-a == Money(d("-1249.90"), .TRY))
        #expect(a * 2 == Money(d("2499.80"), .TRY))
        #expect(Money(78000, .TRY) / 15 == Money(5200, .TRY))
        #expect(b < a)
        #expect((-a).isNegative && (-a).magnitude == a)
    }

    @Test("Boş toplam sıfırdır")
    func sum() {
        #expect([Money]().sum(in: .TRY) == .zero(.TRY))
        #expect([Money(10, .USD), Money(d("0.5"), .USD)].sum(in: .USD) == Money(d("10.5"), .USD))
    }

    @Test("Çevrim açıkça kurla yapılır")
    func conversion() {
        let usd = Money(1200, .USD)
        #expect(usd.converted(to: .TRY, rate: d("50.77")) == Money(60924, .TRY))
    }

    @Test("Gösterim yuvarlaması para birimi basamağına")
    func rounded() {
        #expect(Money(d("10.005"), .TRY).rounded() == Money(d("10.01"), .TRY))
        #expect(Money(d("10.5"), CurrencyCode(rawValue: "JPY")!).rounded() == Money(11, CurrencyCode(rawValue: "JPY")!))
    }

    @Test("Codable tutarı String olarak yazar, hassasiyet kaybolmaz")
    func codable() throws {
        let value = Money(d("12345678901234567.89"), .TRY)
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"12345678901234567.89\""))
        #expect(try JSONDecoder().decode(Money.self, from: data) == value)
    }

    @Test("Bozuk JSON reddedilir")
    func codableRejects() {
        let bad = Data(#"{"amount":"1,5","currency":"TRY"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Money.self, from: bad) }
        let badCurrency = Data(#"{"amount":"1.5","currency":"tl"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Money.self, from: badCurrency) }
    }

    /// specs/01 AC-P3-1 ve specs/03 §3 örneğinin Money ile aritmetiği.
    @Test("AC-P3-1 aritmetiği")
    func acceptanceP3() {
        let cost = Money(5000, .TRY) * 10 + Money(5600, .TRY) * 5
        #expect(cost == Money(78000, .TRY))
        #expect(cost / 15 == Money(5200, .TRY))
        let value = Money(5925, .TRY) * 15
        #expect(value - cost == Money(10875, .TRY))
        #expect(((value - cost).amount / cost.amount).rounded(scale: 4) == d("0.1394"))
    }
}
