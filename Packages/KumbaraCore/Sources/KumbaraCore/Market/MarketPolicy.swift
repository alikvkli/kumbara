import Foundation

/// Varlık grubuna göre sağlayıcı sırası (specs/02 §3).
public enum FallbackPlan {
    public enum Step: Hashable, Sendable {
        case provider(ProviderID)
        /// Ons fiyatı × USD/TRY ile türetme (yalnız `isDerivableFromSpot`).
        case deriveFromSpot
    }

    public static func steps(for asset: AssetCode) -> [Step] {
        switch asset {
        case .gold, .metal:
            asset.isDerivableFromSpot ? [.provider(.truncgil), .deriveFromSpot] : [.provider(.truncgil)]
        case .fx:
            [.provider(.truncgil), .provider(.tcmb), .provider(.frankfurter)]
        case .crypto:
            [.provider(.coingecko)]
        case .custom:
            [.provider(.manual)]
        }
    }
}

/// Art arda 3 hatadan sonra sağlayıcıyı 15 dk atlar (specs/02 §3). Değer tipidir; saat dışarıdan verilir.
public struct CircuitBreaker: Sendable {
    public var failureThreshold = 3
    public var cooldown: TimeInterval = 15 * 60
    private var failures: [ProviderID: Int] = [:]
    private var openUntil: [ProviderID: Date] = [:]

    public init() {}

    public func isOpen(_ provider: ProviderID, now: Date) -> Bool {
        guard let until = openUntil[provider] else { return false }
        return now < until
    }

    public mutating func recordSuccess(_ provider: ProviderID) {
        failures[provider] = 0
        openUntil[provider] = nil
    }

    public mutating func recordFailure(_ provider: ProviderID, now: Date) {
        let count = (failures[provider] ?? 0) + 1
        failures[provider] = count
        if count >= failureThreshold {
            openUntil[provider] = now.addingTimeInterval(cooldown)
            failures[provider] = 0
        }
    }
}

/// Yeni fiyatın akla yatkınlığı (specs/02 §4).
public enum PlausibilityCheck {
    public static let maxJump = Decimal(string: "0.15")!
    public static let confirmationTolerance = Decimal(string: "0.03")!

    public enum Verdict: Equatable, Sendable {
        case accept
        /// İkinci kaynakla doğrulanmadan kabul edilmez.
        case needsConfirmation
    }

    /// Son fiyat 24 saatten yeniyse ve orta fiyat %15'ten fazla saptıysa doğrulama ister.
    public static func evaluate(_ candidate: Quote, previous: Quote?, now: Date) -> Verdict {
        guard let previous, previous.asset == candidate.asset,
              now.timeIntervalSince(previous.asOf) < 24 * 3600, previous.mid > 0
        else { return .accept }
        let change = abs(candidate.mid - previous.mid) / previous.mid
        return change > maxJump ? .needsConfirmation : .accept
    }

    /// İkinci kaynak adayla %3 içinde uyuşuyorsa doğrulanmış sayılır.
    public static func confirms(_ candidate: Quote, with other: Quote) -> Bool {
        guard candidate.asset == other.asset, other.mid > 0 else { return false }
        return abs(candidate.mid - other.mid) / other.mid <= confirmationTolerance
    }
}

/// Fiyatın tazeliği (specs/02 §5, C4).
public enum Freshness: String, Sendable, Equatable {
    case live
    /// Piyasa saatinde 15 dakikadan eski.
    case delayed
    /// Hafta içi 24 saatten, hafta sonu 72 saatten eski.
    case stale

    public static func evaluate(asOf: Date, now: Date, calendar: Calendar) -> Freshness {
        let age = now.timeIntervalSince(asOf)
        let weekday = calendar.component(.weekday, from: now) // 1 = Pazar, 7 = Cumartesi
        let hour = calendar.component(.hour, from: now)
        let isWeekendWindow = weekday == 1 || weekday == 7 || (weekday == 2 && hour < 9)
        let staleAfter: TimeInterval = isWeekendWindow ? 72 * 3600 : 24 * 3600
        if age > staleAfter { return .stale }
        let isMarketHours = !isWeekendWindow && (9..<18).contains(hour)
        if isMarketHours && age > 15 * 60 { return .delayed }
        return .live
    }
}
