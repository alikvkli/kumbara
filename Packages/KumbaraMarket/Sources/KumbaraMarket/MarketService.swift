import Foundation
import KumbaraCore

/// Bir yenilemenin sonucu.
public struct MarketRefresh: Sendable {
    /// Bu yenilemede kabul edilen fiyatlar (istenen varlıklar).
    public var quotes: [AssetCode: Quote]
    /// Hiçbir kaynaktan alınamayan varlıklar (son bilinen fiyat gösterilmeli — C4).
    public var missing: Set<AssetCode>
    /// Akla yatkınlık kontrolünden geçemeyen, reddedilen fiyatlar.
    public var rejected: Set<AssetCode>
    /// Hata veren sağlayıcılar.
    public var failedProviders: Set<ProviderID>
}

/// Yedekleme zinciri, devre kesici ve akla yatkınlık kontrolüyle fiyat toplar (specs/02 §3–4).
public actor MarketService {
    private let http: any HTTPClient
    private let clock: @Sendable () -> Date
    private var breaker = CircuitBreaker()
    /// Son kabul edilen fiyatlar (akla yatkınlık referansı). Uygulama açılışında diskten doldurulur.
    private var lastAccepted: [AssetCode: Quote] = [:]

    public init(http: any HTTPClient = URLSessionHTTPClient(), clock: @escaping @Sendable () -> Date = { .now }) {
        self.http = http
        self.clock = clock
    }

    /// Son bilinen fiyatları yükler (çevrimdışı açılış, akla yatkınlık referansı).
    public func seed(_ quotes: [Quote]) {
        for quote in quotes where (lastAccepted[quote.asset]?.asOf ?? .distantPast) < quote.asOf {
            lastAccepted[quote.asset] = quote
        }
    }

    public func refresh(_ assets: Set<AssetCode>) async -> MarketRefresh {
        let now = clock()
        var failed: Set<ProviderID> = []
        // Türetme ve gösterim için USD/TRY her zaman istenir.
        var wanted = assets.filter { if case .custom = $0 { return false }; return true }
        wanted.insert(.fx(.USD))

        // 1. Birincil kaynaklar paralel.
        let needsTruncgil = wanted.contains { if case .crypto = $0 { return false }; return true }
        let cryptoIDs = wanted.compactMap { asset -> String? in
            if case .crypto(let id) = asset { return id }
            return nil
        }
        async let truncgilResult = needsTruncgil ? fetch(.truncgil, now: now) { try TruncgilParser.parse(try await self.http.get(MarketEndpoint.truncgil)) } : nil
        async let cryptoResult = cryptoIDs.isEmpty ? nil : fetch(.coingecko, now: now) {
            try CoinGeckoParser.parse(try await self.http.get(MarketEndpoint.coingecko(ids: cryptoIDs)), fetchedAt: now)
        }

        var found: [AssetCode: Quote] = [:]
        for result in [await truncgilResult, await cryptoResult] {
            switch result {
            case .success(let quotes)?:
                for quote in quotes where wanted.contains(quote.asset) { found[quote.asset] = quote }
            case .failure(let provider)?:
                failed.insert(provider)
            case nil:
                break
            }
        }

        // 2. Eksik dövizler: TCMB, sonra Frankfurter.
        let missingFX = wanted.filter { if case .fx = $0 { return found[$0] == nil }; return false }
        var tcmbQuotes: [Quote] = []
        if !missingFX.isEmpty || needsConfirmation(found, now: now).contains(where: { if case .fx = $0 { return true }; return false }) {
            switch await fetch(.tcmb, now: now, { try TCMBParser.parse(try await self.http.get(MarketEndpoint.tcmb)) }) {
            case .success(let quotes): tcmbQuotes = quotes
            case .failure(let provider): failed.insert(provider)
            }
            for quote in tcmbQuotes where missingFX.contains(quote.asset) { found[quote.asset] = quote }
        }
        let stillMissingFX = wanted.filter { if case .fx = $0 { return found[$0] == nil }; return false }
        if !stillMissingFX.isEmpty {
            switch await fetch(.frankfurter, now: now, { () -> [Quote] in
                let rates = try FrankfurterParser.parse(try await self.http.get(MarketEndpoint.frankfurterLatest(base: .USD)))
                return Self.tryQuotes(from: rates)
            }) {
            case .success(let quotes):
                for quote in quotes where stillMissingFX.contains(quote.asset) { found[quote.asset] = quote }
            case .failure(let provider):
                failed.insert(provider)
            }
        }

        // 3. Eksik türetilebilir metaller (ve doğrulama gereken gram altın): ons × USD/TRY.
        let usdTRY = (found[.fx(.USD)] ?? lastAccepted[.fx(.USD)])?.price(.ask)
        let jumpy = needsConfirmation(found, now: now)
        let derivable = wanted.filter { $0.isDerivableFromSpot && (found[$0] == nil || jumpy.contains($0)) }
        var derived: [AssetCode: Quote] = [:]
        if let usdTRY, !derivable.isEmpty {
            let metals = Set(derivable.compactMap(Self.metal(for:)))
            for metal in metals.sorted(by: { $0.rawValue < $1.rawValue }) {
                switch await fetch(.goldAPI, now: now, { try GoldAPIParser.parse(try await self.http.get(MarketEndpoint.goldAPI(metal))) }) {
                case .success(let spot):
                    for asset in derivable where Self.metal(for: asset) == metal {
                        derived[asset] = SpotDerivation.quote(for: asset, spot: spot, usdTRY: usdTRY, asOf: now)
                    }
                case .failure(let provider):
                    failed.insert(provider)
                }
            }
        }
        for (asset, quote) in derived where found[asset] == nil { found[asset] = quote }

        // 4. Akla yatkınlık: büyük sıçrama ikinci kaynakla doğrulanmazsa reddedilir.
        var rejected: Set<AssetCode> = []
        for (asset, quote) in found {
            guard PlausibilityCheck.evaluate(quote, previous: lastAccepted[asset], now: now) == .needsConfirmation else { continue }
            let second = derived[asset] ?? tcmbQuotes.first { $0.asset == asset && $0.source != quote.source }
            if let second, second.source != quote.source, PlausibilityCheck.confirms(quote, with: second) { continue }
            rejected.insert(asset)
        }
        for asset in rejected { found[asset] = nil }

        for (asset, quote) in found { lastAccepted[asset] = quote }
        let requested = assets.filter { if case .custom = $0 { return false }; return true }
        return MarketRefresh(
            quotes: found.filter { requested.contains($0.key) || $0.key == .fx(.USD) },
            missing: requested.subtracting(found.keys).subtracting(rejected),
            rejected: rejected,
            failedProviders: failed
        )
    }

    /// Geçmiş bir günün USD/TRY orta kuru (alım kaydında, specs/03 §4).
    public func usdTRY(year: Int, month: Int, day: Int) async throws -> Decimal {
        let rates = try FrankfurterParser.parse(try await http.get(
            MarketEndpoint.frankfurterHistorical(year: year, month: month, day: day)))
        guard let rate = rates.rate(to: .TRY) else { throw MarketParseError.missingField(.frankfurter, "TRY") }
        return rate
    }

    // MARK: Yardımcılar

    private enum Outcome<Value: Sendable>: Sendable {
        case success(Value)
        case failure(ProviderID)
    }

    private func fetch<Value: Sendable>(_ provider: ProviderID, now: Date,
                              _ work: @Sendable () async throws -> Value) async -> Outcome<Value> {
        guard !breaker.isOpen(provider, now: now) else { return .failure(provider) }
        do {
            let value = try await work()
            breaker.recordSuccess(provider)
            return .success(value)
        } catch {
            breaker.recordFailure(provider, now: now)
            return .failure(provider)
        }
    }

    private func needsConfirmation(_ quotes: [AssetCode: Quote], now: Date) -> Set<AssetCode> {
        Set(quotes.filter { PlausibilityCheck.evaluate($0.value, previous: lastAccepted[$0.key], now: now) == .needsConfirmation }.keys)
    }

    private static func metal(for asset: AssetCode) -> SpotPrice.Metal? {
        switch asset {
        case .gold(.gram24), .gold(.has): .gold
        case .metal(.silver): .silver
        case .metal(.platinum): .platinum
        case .metal(.palladium): .palladium
        default: nil
        }
    }

    /// USD tabanlı kurlardan TRY fiyatları: 1 X = (USD/TRY) / (USD/X) TRY. Orta kur; makas yok.
    static func tryQuotes(from rates: FXRates) -> [Quote] {
        guard rates.base == .USD, let usdTRY = rates.rate(to: .TRY) else { return [] }
        var quotes: [Quote] = []
        if let usd = Quote(asset: .fx(.USD), bid: usdTRY, ask: usdTRY, asOf: rates.date, source: .frankfurter) {
            quotes.append(usd)
        }
        for (code, perUSD) in rates.rates where code != .TRY && perUSD > 0 {
            let price = usdTRY / perUSD
            if let quote = Quote(asset: .fx(code), bid: price, ask: price, asOf: rates.date, source: .frankfurter) {
                quotes.append(quote)
            }
        }
        return quotes
    }
}
