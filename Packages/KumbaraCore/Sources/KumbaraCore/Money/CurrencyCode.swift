import Foundation

/// ISO 4217 para birimi kodu (specs/00 C3).
public struct CurrencyCode: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// Üç büyük harften (A–Z) oluşmayan kodları reddeder.
    public init?(rawValue: String) {
        let scalars = rawValue.unicodeScalars
        guard scalars.count == 3, scalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked: String) { rawValue = unchecked }

    public static let TRY = CurrencyCode(unchecked: "TRY")
    public static let USD = CurrencyCode(unchecked: "USD")
    public static let EUR = CurrencyCode(unchecked: "EUR")
    public static let GBP = CurrencyCode(unchecked: "GBP")
    public static let CHF = CurrencyCode(unchecked: "CHF")

    /// Küsurat basamağı sayısı (gösterim ve yuvarlama için).
    public var minorUnits: Int {
        switch rawValue {
        case "JPY", "KRW", "CLP", "ISK", "VND": 0
        case "KWD", "BHD", "OMR", "JOD", "TND": 3
        default: 2
        }
    }

    public var description: String { rawValue }
}
