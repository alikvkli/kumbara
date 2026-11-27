import Foundation

/// Fiyat kaynağı (specs/02 §1).
public enum ProviderID: String, Sendable, Codable, CaseIterable {
    case truncgil
    case goldAPI = "goldapi"
    case tcmb
    case frankfurter
    case coingecko
    /// Kullanıcının elle girdiği fiyat (serbest varlık).
    case manual
}

/// Değerlemede kullanılacak fiyat (REQ-P4).
public enum PriceKind: String, Sendable, Codable, CaseIterable {
    /// Kuyumcu/banka ALIŞ = senin bozdurma fiyatın. Varsayılan (D6).
    case bid
    /// Kuyumcu/banka SATIŞ = senin alım fiyatın.
    case ask
    /// Orta fiyat.
    case mid
}

/// Bir varlığın belirli bir andaki fiyatı (specs/02 §2). Fiyatlar `currency` cinsindendir (TRY).
public struct Quote: Hashable, Sendable {
    public let asset: AssetCode
    public let bid: Decimal?
    public let ask: Decimal?
    public let mid: Decimal
    public let currency: CurrencyCode
    /// Kaynağın bildirdiği zaman; bildirmiyorsa çekim zamanı.
    public let asOf: Date
    public let source: ProviderID
    /// Ons fiyatından türetildi mi (makas bilinmez, "yaklaşık").
    public let isDerived: Bool

    /// Geçersiz fiyatlar (≤ 0, ya da alış > satış) için `nil` (specs/02 §4).
    public init?(asset: AssetCode, bid: Decimal?, ask: Decimal?, currency: CurrencyCode = .TRY,
                 asOf: Date, source: ProviderID, isDerived: Bool = false) {
        let bid = bid.flatMap { $0 > 0 ? $0 : nil }
        let ask = ask.flatMap { $0 > 0 ? $0 : nil }
        let mid: Decimal
        switch (bid, ask) {
        case let (b?, a?):
            guard b <= a else { return nil }
            mid = (b + a) / 2
        case let (b?, nil): mid = b
        case let (nil, a?): mid = a
        case (nil, nil): return nil
        }
        self.asset = asset
        self.bid = bid
        self.ask = ask
        self.mid = mid
        self.currency = currency
        self.asOf = asOf
        self.source = source
        self.isDerived = isDerived
    }

    /// İstenen fiyat; o taraf yoksa orta fiyat.
    public func price(_ kind: PriceKind) -> Decimal {
        switch kind {
        case .bid: bid ?? mid
        case .ask: ask ?? mid
        case .mid: mid
        }
    }

    /// Alış-satış makası (birim başına); iki taraf da biliniyorsa.
    public var spread: Decimal? {
        guard let bid, let ask else { return nil }
        return ask - bid
    }
}

public enum MarketParseError: Error, Equatable {
    case malformed(ProviderID)
    case missingField(ProviderID, String)
}

extension Decimal {
    /// JSON'dan `Double` olarak gelen fiyatı ikili kayan nokta hatası olmadan çevirir:
    /// Swift'in en kısa gidiş-dönüş gösterimi (`5929.88`) üzerinden (specs/00 C3).
    init?(jsonNumber value: Any?) {
        switch value {
        case let number as Double:
            guard number.isFinite else { return nil }
            self.init(string: "\(number)", locale: Locale(identifier: "en_US_POSIX"))
        case let number as Int:
            self.init(number)
        case let number as NSNumber:
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            self.init(string: "\(double)", locale: Locale(identifier: "en_US_POSIX"))
        case let string as String:
            self.init(canonical: string)
        default:
            return nil
        }
    }
}
