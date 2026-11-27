import Foundation
import Testing
@testable import KumbaraCore

/// Biçim sistemin CLDR kurallarını izler (specs/01 REQ-X6). Bu testler ICU sürümü
/// değişince kırılabilir; o zaman beklenen değer bilinçli olarak güncellenir.
@Suite("Biçimlendirme")
struct FormattingTests {
    let tr = Locale(identifier: "tr_TR")
    let en = Locale(identifier: "en_US")

    @Test func money() {
        let m = Money(Decimal(canonical: "1249.9")!, .TRY)
        #expect(m.formatted(locale: tr) == "₺1.249,90")
        #expect((-m).formatted(locale: tr) == "-₺1.249,90")
        #expect(Money(10875, .TRY).formatted(locale: tr, sign: .always) == "+₺10.875,00")
        #expect(Money.zero(.TRY).formatted(locale: tr, sign: .always) == "₺0,00")
        #expect(m.formatted(locale: tr, sign: .never, fractionDigits: 0) == "₺1.250")
    }

    @Test func percent() {
        #expect(Decimal(canonical: "0.13942")!.formattedPercent(locale: tr, sign: .always) == "+%13,94")
        #expect(Decimal(canonical: "-0.023")!.formattedPercent(locale: tr, fractionDigits: 1) == "-%2,3")
        #expect(Decimal(canonical: "0.041")!.formattedPercent(locale: en, fractionDigits: 1) == "4.1%")
    }

    @Test func quantity() {
        #expect(AssetCode.gold(.gram24).formatQuantity(Decimal(canonical: "42.5")!, locale: tr) == "42,5")
        #expect(AssetCode.gold(.gram24).formatQuantity(Decimal(canonical: "1.23456")!, locale: tr) == "1,235")
        #expect(AssetCode.gold(.quarter).formatQuantity(8, locale: tr) == "8")
        #expect(AssetCode.crypto("bitcoin").formatQuantity(Decimal(canonical: "0.00125")!, locale: tr) == "0,00125")
        #expect(AssetCode.fx(.USD).formatQuantity(1200, locale: tr) == "1.200")
    }
}
