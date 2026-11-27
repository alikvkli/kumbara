import Foundation
import Testing
@testable import KumbaraCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/market"))
    return try Data(contentsOf: url)
}

private func d(_ s: String) -> Decimal { Decimal(canonical: s)! }

private var istanbul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return c
}

@Suite("Sağlayıcı ayrıştırıcıları (gerçek yanıtlar, 2026-11-27)")
struct ProviderParserTests {
    @Test("Truncgil: altın türleri, metaller, döviz; Buying=bid Selling=ask; Decimal tam")
    func truncgil() throws {
        let quotes = try TruncgilParser.parse(fixture("truncgil-today.json"))
        let byAsset = Dictionary(uniqueKeysWithValues: quotes.map { ($0.asset, $0) })

        let gram = try #require(byAsset[.gold(.gram24)])
        #expect(gram.bid == d("5929.01"))
        #expect(gram.ask == d("5929.88"))
        #expect(gram.source == .truncgil)
        #expect(!gram.isDerived)

        #expect(byAsset[.gold(.quarter)]?.bid == 9975)
        #expect(byAsset[.gold(.quarter)]?.ask == 10219)
        #expect(byAsset[.gold(.bracelet22)]?.bid == d("5566.68"))
        #expect(byAsset[.metal(.silver)]?.ask == d("71.14"))
        #expect(byAsset[.fx(.USD)]?.bid == d("50.781"))

        // 15 altın türünün hepsi ve 3 metal
        for kind in GoldKind.allCases { #expect(byAsset[.gold(kind)] != nil, "\(kind) eksik") }
        for metal in PreciousMetal.allCases { #expect(byAsset[.metal(metal)] != nil) }

        // "2026-11-27 07:16:02" İstanbul = 04:16:02 UTC
        #expect(gram.asOf == Date(timeIntervalSince1970: 1_795_752_962))
    }

    @Test("Truncgil: sıfır fiyat (ONS) veri yok sayılır")
    func truncgilZero() throws {
        let json = #"{"Update_Date":"2026-11-27 07:16:02","ONS":{"Type":"Gold","Buying":0,"Selling":0},"GRA":{"Type":"Gold","Buying":0,"Selling":5000}}"#
        let quotes = try TruncgilParser.parse(Data(json.utf8))
        #expect(quotes.count == 1)
        #expect(quotes.first?.bid == nil)
        #expect(quotes.first?.mid == 5000)
    }

    @Test("Truncgil: bozuk yanıt hata verir")
    func truncgilMalformed() {
        #expect(throws: MarketParseError.malformed(.truncgil)) { try TruncgilParser.parse(Data("[]".utf8)) }
        #expect(throws: MarketParseError.missingField(.truncgil, "Update_Date")) {
            try TruncgilParser.parse(Data("{}".utf8))
        }
    }

    @Test("gold-api: ons fiyatı")
    func goldAPI() throws {
        let gold = try GoldAPIParser.parse(fixture("goldapi-XAU.json"))
        #expect(gold.metal == .gold)
        #expect(gold.usdPerOunce == d("3628.899902"))
        let silver = try GoldAPIParser.parse(fixture("goldapi-XAG.json"))
        #expect(silver.metal == .silver)
    }

    @Test("Türetme: ons → gram, Truncgil ile %0,5 içinde (specs/02 §1 doğrulaması)")
    func derivation() throws {
        let spot = try GoldAPIParser.parse(fixture("goldapi-XAU.json"))
        let truncgil = try TruncgilParser.parse(fixture("truncgil-today.json"))
        let usd = try #require(truncgil.first { $0.asset == .fx(.USD) })
        let gram = try #require(truncgil.first { $0.asset == .gold(.gram24) })

        let derived = try #require(SpotDerivation.quote(for: .gold(.gram24), spot: spot, usdTRY: usd.ask!, asOf: .now))
        #expect(derived.isDerived)
        #expect(derived.bid == derived.ask)
        #expect(abs(derived.mid - gram.mid) / gram.mid < d("0.005"))

        let silverSpot = try GoldAPIParser.parse(fixture("goldapi-XAG.json"))
        let silver = try #require(SpotDerivation.quote(for: .metal(.silver), spot: silverSpot, usdTRY: usd.ask!, asOf: .now))
        let silverTruncgil = try #require(truncgil.first { $0.asset == .metal(.silver) })
        #expect(abs(silver.mid - silverTruncgil.mid) / silverTruncgil.mid < d("0.02"))
    }

    @Test("Türetme ziynet altın ve yanlış metal için yapılmaz")
    func derivationRefuses() throws {
        let spot = try GoldAPIParser.parse(fixture("goldapi-XAU.json"))
        #expect(SpotDerivation.quote(for: .gold(.quarter), spot: spot, usdTRY: 50, asOf: .now) == nil)
        #expect(SpotDerivation.quote(for: .metal(.silver), spot: spot, usdTRY: 50, asOf: .now) == nil)
        #expect(SpotDerivation.quote(for: .gold(.gram24), spot: spot, usdTRY: 0, asOf: .now) == nil)
    }

    @Test("TCMB: döviz alış/satış, birim bölünür, bülten tarihi 15:30")
    func tcmb() throws {
        let quotes = try TCMBParser.parse(fixture("tcmb-today.xml"))
        let usd = try #require(quotes.first { $0.asset == .fx(.USD) })
        #expect(usd.bid == d("50.5866"))
        #expect(usd.ask == d("50.6777"))
        #expect(usd.source == .tcmb)
        #expect(istanbul.dateComponents([.year, .month, .day, .hour, .minute], from: usd.asOf)
                == DateComponents(year: 2026, month: 11, day: 26, hour: 15, minute: 30))
        // JPY 100 birim üzerinden ilan edilir
        if let jpy = quotes.first(where: { $0.asset == .fx(CurrencyCode(rawValue: "JPY")!) }) {
            #expect(jpy.mid < 1)
        }
        #expect(quotes.count > 10)
    }

    @Test("Frankfurter: güncel ve tarihsel")
    func frankfurter() throws {
        let latest = try FrankfurterParser.parse(fixture("frankfurter-latest.json"))
        #expect(latest.base == .USD)
        #expect(latest.rate(to: .TRY) == d("50.677"))
        #expect(latest.rate(to: .USD) == 1)
        let historical = try FrankfurterParser.parse(fixture("frankfurter-2025-03-14.json"))
        #expect(historical.rate(to: .TRY) == d("36.677"))
    }

    @Test("CoinGecko: TRY fiyatı ve güncelleme zamanı")
    func coingecko() throws {
        let quotes = try CoinGeckoParser.parse(fixture("coingecko-simple.json"), fetchedAt: .now)
        let btc = try #require(quotes.first { $0.asset == .crypto("bitcoin") })
        #expect(btc.mid == 3_120_109)
        #expect(btc.asOf == Date(timeIntervalSince1970: 1_795_752_991))
        #expect(quotes.map(\.asset.id) == ["crypto.bitcoin", "crypto.ethereum", "crypto.tether"])
    }
}

@Suite("Quote")
struct QuoteTests {
    @Test func validation() {
        #expect(Quote(asset: .fx(.USD), bid: nil, ask: nil, asOf: .now, source: .tcmb) == nil)
        #expect(Quote(asset: .fx(.USD), bid: 0, ask: -1, asOf: .now, source: .tcmb) == nil)
        #expect(Quote(asset: .fx(.USD), bid: 51, ask: 50, asOf: .now, source: .tcmb) == nil, "alış > satış")
        let q = Quote(asset: .gold(.quarter), bid: 9975, ask: 10219, asOf: .now, source: .truncgil)!
        #expect(q.mid == 10097)
        #expect(q.spread == 244)
        #expect(q.price(.bid) == 9975)
        #expect(q.price(.ask) == 10219)
        let single = Quote(asset: .crypto("bitcoin"), bid: nil, ask: 100, asOf: .now, source: .coingecko)!
        #expect(single.price(.bid) == 100)
        #expect(single.spread == nil)
    }
}

@Suite("Piyasa politikaları (specs/02 §3–5)")
struct MarketPolicyTests {
    @Test func fallbackPlans() {
        #expect(FallbackPlan.steps(for: .gold(.gram24)) == [.provider(.truncgil), .deriveFromSpot])
        #expect(FallbackPlan.steps(for: .gold(.quarter)) == [.provider(.truncgil)], "ziynet türetilmez")
        #expect(FallbackPlan.steps(for: .fx(.USD)) == [.provider(.truncgil), .provider(.tcmb), .provider(.frankfurter)])
        #expect(FallbackPlan.steps(for: .crypto("bitcoin")) == [.provider(.coingecko)])
        #expect(FallbackPlan.steps(for: .custom("fon")) == [.provider(.manual)])
    }

    @Test("Devre kesici: 3 hata → 15 dk atla; başarı sıfırlar")
    func circuitBreaker() {
        var breaker = CircuitBreaker()
        let t0 = Date(timeIntervalSince1970: 0)
        breaker.recordFailure(.truncgil, now: t0)
        breaker.recordFailure(.truncgil, now: t0)
        #expect(!breaker.isOpen(.truncgil, now: t0))
        breaker.recordFailure(.truncgil, now: t0)
        #expect(breaker.isOpen(.truncgil, now: t0.addingTimeInterval(60)))
        #expect(!breaker.isOpen(.tcmb, now: t0))
        #expect(!breaker.isOpen(.truncgil, now: t0.addingTimeInterval(15 * 60)))

        breaker.recordFailure(.tcmb, now: t0)
        breaker.recordFailure(.tcmb, now: t0)
        breaker.recordSuccess(.tcmb)
        breaker.recordFailure(.tcmb, now: t0)
        #expect(!breaker.isOpen(.tcmb, now: t0))
    }

    @Test("Akla yatkınlık: %15 üstü sıçrama doğrulama ister")
    func plausibility() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let previous = Quote(asset: .gold(.gram24), bid: 5900, ask: 5900, asOf: now.addingTimeInterval(-3600), source: .truncgil)!
        let normal = Quote(asset: .gold(.gram24), bid: 6000, ask: 6000, asOf: now, source: .truncgil)!
        let jump = Quote(asset: .gold(.gram24), bid: 7000, ask: 7000, asOf: now, source: .truncgil)!
        #expect(PlausibilityCheck.evaluate(normal, previous: previous, now: now) == .accept)
        #expect(PlausibilityCheck.evaluate(jump, previous: previous, now: now) == .needsConfirmation)
        #expect(PlausibilityCheck.evaluate(jump, previous: nil, now: now) == .accept)
        let old = Quote(asset: .gold(.gram24), bid: 5900, ask: 5900, asOf: now.addingTimeInterval(-25 * 3600), source: .truncgil)!
        #expect(PlausibilityCheck.evaluate(jump, previous: old, now: now) == .accept, "24 saatten eski referans yok sayılır")

        let derived = Quote(asset: .gold(.gram24), bid: 6950, ask: 6950, asOf: now, source: .goldAPI, isDerived: true)!
        #expect(PlausibilityCheck.confirms(jump, with: derived))
        #expect(!PlausibilityCheck.confirms(jump, with: previous))
    }

    @Test("Tazelik: piyasa saati, hafta içi, hafta sonu")
    func freshness() {
        let cal = istanbul
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        // 27 Kasım 2026 Cuma
        #expect(Freshness.evaluate(asOf: at(27, 14, 0), now: at(27, 14, 10), calendar: cal) == .live)
        #expect(Freshness.evaluate(asOf: at(27, 14, 0), now: at(27, 14, 20), calendar: cal) == .delayed)
        #expect(Freshness.evaluate(asOf: at(27, 17, 0), now: at(27, 20, 0), calendar: cal) == .live, "piyasa kapalı")
        #expect(Freshness.evaluate(asOf: at(26, 10, 0), now: at(27, 11, 0), calendar: cal) == .stale)
        // 29 Kasım Pazar: Cuma akşamı fiyatı 72 saat geçerli
        #expect(Freshness.evaluate(asOf: at(27, 18, 0), now: at(29, 20, 0), calendar: cal) == .live)
        // 30 Kasım Pazartesi 08:00 hâlâ hafta sonu penceresi
        #expect(Freshness.evaluate(asOf: at(27, 18, 0), now: at(30, 8, 0), calendar: cal) == .live)
        #expect(Freshness.evaluate(asOf: at(27, 18, 0), now: at(30, 10, 0), calendar: cal) == .stale)
    }
}
