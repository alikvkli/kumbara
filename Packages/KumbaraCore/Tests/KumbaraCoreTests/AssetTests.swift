import Foundation
import Testing
@testable import KumbaraCore

@Suite("AssetCode")
struct AssetCodeTests {
    static let all: [AssetCode] =
        GoldKind.allCases.map { .gold($0) }
        + PreciousMetal.allCases.map { .metal($0) }
        + [.fx(.USD), .fx(.EUR), .crypto("bitcoin"), .crypto("usd-coin"), .custom("tefas-AFT")]

    @Test("Kimlik gidiş-dönüş", arguments: all)
    func roundTrip(code: AssetCode) {
        #expect(AssetCode(id: code.id) == code)
    }

    @Test("Geçersiz kimlik", arguments: ["", "gold", "gold.", "gold.gram22", "fx.usd", "crypto.Bitcoin", "stock.THYAO", "metal.gold"])
    func invalid(id: String) { #expect(AssetCode(id: id) == nil) }

    @Test func stableIdentifiers() {
        // Kalıcı katmanda saklanır: değişirse göç gerekir.
        #expect(AssetCode.gold(.gram24).id == "gold.gram24")
        #expect(AssetCode.gold(.quarter).id == "gold.quarter")
        #expect(AssetCode.fx(.USD).id == "fx.USD")
        #expect(AssetCode.crypto("bitcoin").id == "crypto.bitcoin")
    }

    @Test("Ziynet altın adet, gram altın gram (specs/03 §6)")
    func units() {
        #expect(AssetCode.gold(.gram24).unit == .gram)
        #expect(AssetCode.gold(.bracelet22).unit == .gram)
        #expect(AssetCode.gold(.quarter).unit == .piece)
        #expect(AssetCode.gold(.republic).unit == .piece)
        #expect(AssetCode.metal(.silver).unit == .gram)
        #expect(AssetCode.fx(.USD).unit == .unit)
    }

    @Test("Yalnız gram/has/metal ons fiyatından türetilir (specs/02 §3)")
    func derivable() {
        #expect(AssetCode.gold(.gram24).isDerivableFromSpot)
        #expect(AssetCode.gold(.has).isDerivableFromSpot)
        #expect(AssetCode.metal(.platinum).isDerivableFromSpot)
        #expect(!AssetCode.gold(.quarter).isDerivableFromSpot)
        #expect(!AssetCode.gold(.bracelet22).isDerivableFromSpot)
        #expect(!AssetCode.fx(.USD).isDerivableFromSpot)
    }

    @Test func codable() throws {
        let data = try JSONEncoder().encode([AssetCode.gold(.gram24), .fx(.EUR)])
        #expect(String(decoding: data, as: UTF8.self) == #"["gold.gram24","fx.EUR"]"#)
        #expect(try JSONDecoder().decode([AssetCode].self, from: data) == [.gold(.gram24), .fx(.EUR)])
    }

    @Test func quantityCodable() throws {
        let q = Quantity(Decimal(canonical: "42.125")!, .gram)
        let data = try JSONEncoder().encode(q)
        #expect(String(decoding: data, as: UTF8.self).contains(#""42.125""#))
        #expect(try JSONDecoder().decode(Quantity.self, from: data) == q)
    }
}
