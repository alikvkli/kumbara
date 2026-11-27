import Foundation
import KumbaraCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

public enum HTTPClientError: Error, Equatable {
    case status(Int)
    case notHTTP
}

/// Kullanıcıya ait hiçbir bilgi göndermez: genel User-Agent, çerez yok, önbellek yok (specs/00 C1).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 10) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "Kumbara/1.0", "Accept": "application/json, text/xml"]
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw HTTPClientError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw HTTPClientError.status(http.statusCode) }
        return data
    }
}

/// Uç noktalar tek yerde (specs/02 §1). Yalnız bu alan adlarına istek gider.
public enum MarketEndpoint {
    public static let truncgil = URL(string: "https://finans.truncgil.com/v4/today.json")!
    public static let tcmb = URL(string: "https://www.tcmb.gov.tr/kurlar/today.xml")!

    public static func goldAPI(_ metal: SpotPrice.Metal) -> URL {
        URL(string: "https://api.gold-api.com/price/\(metal.rawValue)")!
    }

    public static func frankfurterLatest(base: CurrencyCode = .USD) -> URL {
        URL(string: "https://api.frankfurter.dev/v1/latest?base=\(base.rawValue)")!
    }

    /// `day` UTC değil, Avrupa takvim günü olarak yorumlanır: yyyy-MM-dd.
    public static func frankfurterHistorical(year: Int, month: Int, day: Int, base: CurrencyCode = .USD,
                                             symbol: CurrencyCode = .TRY) -> URL {
        let date = String(format: "%04d-%02d-%02d", year, month, day)
        return URL(string: "https://api.frankfurter.dev/v1/\(date)?base=\(base.rawValue)&symbols=\(symbol.rawValue)")!
    }

    public static func coingecko(ids: [String]) -> URL {
        let joined = ids.sorted().joined(separator: ",")
        return URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(joined)&vs_currencies=try,usd&include_last_updated_at=true")!
    }
}

