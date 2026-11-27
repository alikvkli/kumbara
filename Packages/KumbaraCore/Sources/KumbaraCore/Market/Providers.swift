import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private let istanbul = TimeZone(identifier: "Europe/Istanbul")!

// MARK: Truncgil (specs/02 §1 — altın için birincil)

public enum TruncgilParser {
    /// Truncgil alan adı → varlık. Alanlar `Buying` (alış = bid) ve `Selling` (satış = ask).
    public static let goldKeys: [String: AssetCode] = [
        "GRA": .gold(.gram24), "HAS": .gold(.has), "YIA": .gold(.bracelet22),
        "18AYARALTIN": .gold(.carat18), "14AYARALTIN": .gold(.carat14),
        "CEYREKALTIN": .gold(.quarter), "YARIMALTIN": .gold(.half), "TAMALTIN": .gold(.full),
        "CUMHURIYETALTINI": .gold(.republic), "ATAALTIN": .gold(.ata), "RESATALTIN": .gold(.resat),
        "HAMITALTIN": .gold(.hamit), "GREMSEALTIN": .gold(.gremse), "IKIBUCUKALTIN": .gold(.ikibucuk),
        "BESLIALTIN": .gold(.besli),
        "GUMUS": .metal(.silver), "GPL": .metal(.platinum), "PAL": .metal(.palladium),
    ]

    public static func parse(_ data: Data) throws -> [Quote] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketParseError.malformed(.truncgil)
        }
        guard let stamp = root["Update_Date"] as? String, let asOf = parseDate(stamp) else {
            throw MarketParseError.missingField(.truncgil, "Update_Date")
        }
        var quotes: [Quote] = []
        for (key, value) in root {
            guard let fields = value as? [String: Any] else { continue }
            let asset: AssetCode?
            if let gold = goldKeys[key] {
                asset = gold
            } else if fields["Type"] as? String == "Currency", let code = CurrencyCode(rawValue: key) {
                asset = .fx(code)
            } else {
                asset = nil
            }
            guard let asset,
                  let quote = Quote(asset: asset, bid: Decimal(jsonNumber: fields["Buying"]),
                                    ask: Decimal(jsonNumber: fields["Selling"]), asOf: asOf, source: .truncgil)
            else { continue }
            quotes.append(quote)
        }
        return quotes.sorted { $0.asset.id < $1.asset.id }
    }

    /// `"2026-11-27 07:16:02"` — saat dilimi yok; İstanbul saati.
    static func parseDate(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = istanbul
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                  hour: parts[3], minute: parts[4], second: parts[5]))
    }
}

// MARK: gold-api.com (ons fiyatı, USD)

public struct SpotPrice: Hashable, Sendable {
    public enum Metal: String, Sendable, CaseIterable {
        case gold = "XAU", silver = "XAG", platinum = "XPT", palladium = "XPD"
    }
    public let metal: Metal
    public let usdPerOunce: Decimal
    public let asOf: Date
}

public enum GoldAPIParser {
    public static func parse(_ data: Data) throws -> SpotPrice {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let symbol = root["symbol"] as? String, let metal = SpotPrice.Metal(rawValue: symbol),
              root["currency"] as? String == "USD",
              let price = Decimal(jsonNumber: root["price"]), price > 0
        else { throw MarketParseError.malformed(.goldAPI) }
        let formatter = ISO8601DateFormatter()
        guard let stamp = root["updatedAt"] as? String, let asOf = formatter.date(from: stamp) else {
            throw MarketParseError.missingField(.goldAPI, "updatedAt")
        }
        return SpotPrice(metal: metal, usdPerOunce: price, asOf: asOf)
    }
}

/// Ons fiyatından gram fiyatı türetme (specs/02 §3). Yalnız gram/has altın ve metaller.
public enum SpotDerivation {
    /// 1 troy ons = 31,1034768 g.
    public static let gramsPerTroyOunce = Decimal(string: "31.1034768", locale: Locale(identifier: "en_US_POSIX"))!

    public static func quote(for asset: AssetCode, spot: SpotPrice, usdTRY: Decimal, asOf: Date) -> Quote? {
        let expected: SpotPrice.Metal
        switch asset {
        case .gold(.gram24), .gold(.has): expected = .gold
        case .metal(.silver): expected = .silver
        case .metal(.platinum): expected = .platinum
        case .metal(.palladium): expected = .palladium
        default: return nil
        }
        guard spot.metal == expected, usdTRY > 0 else { return nil }
        let gram = spot.usdPerOunce / gramsPerTroyOunce * usdTRY
        return Quote(asset: asset, bid: gram, ask: gram, asOf: min(asOf, spot.asOf), source: .goldAPI, isDerived: true)
    }
}

// MARK: TCMB (resmî döviz kuru)

public enum TCMBParser {
    public static func parse(_ data: Data) throws -> [Quote] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let date = delegate.bulletinDate else { throw MarketParseError.malformed(.tcmb) }
        return delegate.currencies.compactMap { item -> Quote? in
            guard let code = CurrencyCode(rawValue: item.code),
                  let unit = Decimal(canonical: item.fields["Unit"] ?? "1"), unit > 0
            else { return nil }
            let bid = item.fields["ForexBuying"].flatMap { Decimal(canonical: $0) }.map { $0 / unit }
            let ask = item.fields["ForexSelling"].flatMap { Decimal(canonical: $0) }.map { $0 / unit }
            return Quote(asset: .fx(code), bid: bid, ask: ask, asOf: date, source: .tcmb)
        }
        .sorted { $0.asset.id < $1.asset.id }
    }

    /// Bülten tarihi `Tarih="26.11.2026"`; kur 15:30'da ilan edilir (İstanbul).
    static func bulletinDate(_ text: String) -> Date? {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = istanbul
        return calendar.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0], hour: 15, minute: 30))
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        struct Item { var code: String; var fields: [String: String] = [:] }
        var bulletinDate: Date?
        var currencies: [Item] = []
        private var current: Item?
        private var element: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "Tarih_Date", let tarih = attributes["Tarih"] {
                bulletinDate = TCMBParser.bulletinDate(tarih)
            } else if name == "Currency", let code = attributes["CurrencyCode"] {
                current = Item(code: code)
            } else if current != nil {
                element = name
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "Currency", let item = current {
                currencies.append(item)
                current = nil
            } else if let element, element == name {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { current?.fields[name] = value }
                self.element = nil
            }
        }
    }
}

// MARK: Frankfurter (ECB orta kur; tarihsel)

public struct FXRates: Hashable, Sendable {
    public let base: CurrencyCode
    /// Kurun geçerli olduğu gün (ECB, 16:00 CET).
    public let date: Date
    public let rates: [CurrencyCode: Decimal]

    /// 1 `base` = ? `currency`
    public func rate(to currency: CurrencyCode) -> Decimal? {
        currency == base ? 1 : rates[currency]
    }
}

public enum FrankfurterParser {
    public static func parse(_ data: Data) throws -> FXRates {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseRaw = root["base"] as? String, let base = CurrencyCode(rawValue: baseRaw),
              let dateText = root["date"] as? String,
              let ratesRaw = root["rates"] as? [String: Any]
        else { throw MarketParseError.malformed(.frankfurter) }
        let parts = dateText.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 16))
        else { throw MarketParseError.missingField(.frankfurter, "date") }
        var rates: [CurrencyCode: Decimal] = [:]
        for (key, value) in ratesRaw {
            if let code = CurrencyCode(rawValue: key), let rate = Decimal(jsonNumber: value), rate > 0 {
                rates[code] = rate
            }
        }
        return FXRates(base: base, date: date, rates: rates)
    }
}

// MARK: CoinGecko (kripto)

public enum CoinGeckoParser {
    /// `vs_currencies=try` ile istenen yanıttan TRY fiyatları (tek fiyat: bid = ask).
    public static func parse(_ data: Data, fetchedAt: Date) throws -> [Quote] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketParseError.malformed(.coingecko)
        }
        return root.compactMap { id, value -> Quote? in
            guard let fields = value as? [String: Any], let price = Decimal(jsonNumber: fields["try"]) else { return nil }
            let asOf = (fields["last_updated_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? fetchedAt
            return Quote(asset: .crypto(id), bid: price, ask: price, asOf: asOf, source: .coingecko)
        }
        .sorted { $0.asset.id < $1.asset.id }
    }
}
