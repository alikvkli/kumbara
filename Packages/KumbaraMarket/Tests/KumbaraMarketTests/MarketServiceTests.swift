import Foundation
import KumbaraCore
import Testing
@testable import KumbaraMarket

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Ana makine → yanıt (veya hata). İstekleri kaydeder.
private actor StubHTTP: HTTPClient {
    var responses: [String: Result<Data, Error>] = [:]
    private(set) var requested: [URL] = []

    init(_ responses: [String: Result<Data, Error>]) { self.responses = responses }

    func set(_ key: String, _ value: Result<Data, Error>) { responses[key] = value }

    func get(_ url: URL) async throws -> Data {
        requested.append(url)
        let key = responses.keys.sorted { $0.count > $1.count }.first { url.absoluteString.contains($0) }
        guard let key, let result = responses[key] else { throw HTTPClientError.status(404) }
        return try result.get()
    }

    func count(_ fragment: String) -> Int { requested.filter { $0.absoluteString.contains(fragment) }.count }
}

private struct Offline: Error {}

private func allUp() throws -> [String: Result<Data, Error>] {
    [
        "finans.truncgil.com": .success(try fixture("truncgil-today.json")),
        "tcmb.gov.tr": .success(try fixture("tcmb-today.xml")),
        "frankfurter.dev/v1/latest": .success(try fixture("frankfurter-latest.json")),
        "price/XAU": .success(try fixture("goldapi-XAU.json")),
        "price/XAG": .success(try fixture("goldapi-XAG.json")),
        "coingecko.com": .success(try fixture("coingecko-simple.json")),
    ]
}

/// Fixture'ların çekildiği an (Truncgil 07:16 İstanbul).
private let fixtureNow = Date(timeIntervalSince1970: 1_795_753_000)

@Suite("MarketService yedekleme zinciri (specs/02 §3)")
struct MarketServiceTests {
    @Test("Her şey çalışırken: altın/döviz Truncgil'den, kripto CoinGecko'dan; yedeklere gidilmez")
    func happyPath() async throws {
        let http = StubHTTP(try allUp())
        let service = MarketService(http: http, clock: { fixtureNow })
        let result = await service.refresh([.gold(.gram24), .gold(.quarter), .fx(.EUR), .crypto("bitcoin")])
        #expect(result.quotes[.gold(.gram24)]?.source == .truncgil)
        #expect(result.quotes[.gold(.quarter)]?.source == .truncgil)
        #expect(result.quotes[.fx(.EUR)]?.source == .truncgil)
        #expect(result.quotes[.crypto("bitcoin")]?.source == .coingecko)
        #expect(result.quotes[.fx(.USD)] != nil, "USD her zaman gelir")
        #expect(result.missing.isEmpty)
        #expect(result.failedProviders.isEmpty)
        #expect(await http.count("tcmb") == 0)
        #expect(await http.count("gold-api") == 0)
    }

    /// AC-M1-1
    @Test("Truncgil düşerse: döviz TCMB'den, gram altın ons fiyatından türetilir, çeyrek eksik kalır")
    func truncgilDown() async throws {
        var responses = try allUp()
        responses["finans.truncgil.com"] = .failure(Offline())
        let http = StubHTTP(responses)
        let service = MarketService(http: http, clock: { fixtureNow })
        let result = await service.refresh([.gold(.gram24), .gold(.quarter), .metal(.silver), .fx(.EUR)])

        #expect(result.failedProviders == [.truncgil])
        #expect(result.quotes[.fx(.EUR)]?.source == .tcmb)
        #expect(result.quotes[.fx(.USD)]?.source == .tcmb)
        let gram = try #require(result.quotes[.gold(.gram24)])
        #expect(gram.isDerived)
        #expect(gram.source == .goldAPI)
        #expect(result.quotes[.metal(.silver)]?.isDerived == true)
        #expect(result.quotes[.gold(.quarter)] == nil)
        #expect(result.missing == [.gold(.quarter)], "ziynet altın türetilmez; son bilinen fiyat gösterilir")
    }

    @Test("Truncgil ve TCMB düşerse döviz Frankfurter'den gelir")
    func frankfurterFallback() async throws {
        var responses = try allUp()
        responses["finans.truncgil.com"] = .failure(Offline())
        responses["tcmb.gov.tr"] = .failure(Offline())
        let service = MarketService(http: StubHTTP(responses), clock: { fixtureNow })
        let result = await service.refresh([.fx(.EUR)])
        let eur = try #require(result.quotes[.fx(.EUR)])
        #expect(eur.source == .frankfurter)
        // 50,677 / 0,91116
        #expect(abs(eur.mid - Decimal(string: "55.6181")!) < Decimal(string: "0.001")!)
        #expect(result.failedProviders == [.truncgil, .tcmb])
    }

    @Test("Ağ tamamen yokken: hata yok, her şey eksik (son bilinen fiyatla gösterilir)")
    func offline() async throws {
        let service = MarketService(http: StubHTTP([:]), clock: { fixtureNow })
        let result = await service.refresh([.gold(.gram24), .fx(.EUR)])
        #expect(result.quotes.isEmpty)
        #expect(result.missing == [.gold(.gram24), .fx(.EUR)])
    }

    @Test("Devre kesici: 3 başarısız yenilemeden sonra Truncgil'e istek atılmaz")
    func breaker() async throws {
        var responses = try allUp()
        responses["finans.truncgil.com"] = .failure(Offline())
        let http = StubHTTP(responses)
        let service = MarketService(http: http, clock: { fixtureNow })
        for _ in 0..<4 { _ = await service.refresh([.fx(.EUR)]) }
        #expect(await http.count("truncgil") == 3)
    }

    @Test("Akla yatkınlık: doğrulanmayan büyük sıçrama reddedilir, önceki fiyat korunur")
    func plausibilityRejects() async throws {
        let http = StubHTTP(try allUp())
        let service = MarketService(http: http, clock: { fixtureNow })
        // Bir saat önce çeyrek 5.000 TL imiş: Truncgil'in 10.097'si %100 sıçrama; doğrulayacak ikinci kaynak yok.
        await service.seed([Quote(asset: .gold(.quarter), bid: 5000, ask: 5000,
                                   asOf: fixtureNow.addingTimeInterval(-3600), source: .truncgil)!])
        let result = await service.refresh([.gold(.quarter)])
        #expect(result.rejected == [.gold(.quarter)])
        #expect(result.quotes[.gold(.quarter)] == nil)
    }

    @Test("Akla yatkınlık: gram altındaki sıçrama ons türetmesiyle doğrulanırsa kabul edilir")
    func plausibilityConfirmed() async throws {
        let http = StubHTTP(try allUp())
        let service = MarketService(http: http, clock: { fixtureNow })
        await service.seed([Quote(asset: .gold(.gram24), bid: 4500, ask: 4500,
                                  asOf: fixtureNow.addingTimeInterval(-3600), source: .truncgil)!])
        let result = await service.refresh([.gold(.gram24)])
        #expect(result.rejected.isEmpty)
        #expect(result.quotes[.gold(.gram24)]?.source == .truncgil)
        #expect(await http.count("gold-api") == 1)
    }

    @Test("Serbest varlık ağa gitmez")
    func customAssetsSkipped() async throws {
        let http = StubHTTP(try allUp())
        let service = MarketService(http: http, clock: { fixtureNow })
        let result = await service.refresh([.custom("fon")])
        #expect(result.missing.isEmpty)
        #expect(await http.count("coingecko") == 0)
    }

    @Test("Geçmiş USD/TRY")
    func historical() async throws {
        let http = StubHTTP(["frankfurter.dev/v1/2025-03-14": .success(try fixture("frankfurter-2025-03-14.json"))])
        let service = MarketService(http: http)
        #expect(try await service.usdTRY(year: 2025, month: 3, day: 14) == Decimal(string: "36.677")!)
    }
}
