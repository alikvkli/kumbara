import Foundation

/// Bir varlık miktarının birimi.
public enum QuantityUnit: String, Sendable, Codable, CaseIterable {
    /// Gram (gram altın, bilezik, gümüş…)
    case gram
    /// Adet (çeyrek, yarım, tam… ziynet altın — specs/03 §6)
    case piece
    /// Para/kripto birimi (1 USD, 0,5 BTC)
    case unit
}

/// Truncgil'in fiyatladığı altın türleri (specs/02 §1, specs/01 REQ-P2).
public enum GoldKind: String, Sendable, Codable, CaseIterable {
    case gram24, has, bracelet22, carat18, carat14
    case quarter, half, full, republic, ata, resat, hamit, gremse, ikibucuk, besli

    public var unit: QuantityUnit {
        switch self {
        case .gram24, .has, .bracelet22, .carat18, .carat14: .gram
        default: .piece
        }
    }
}

public enum PreciousMetal: String, Sendable, Codable, CaseIterable {
    case silver, platinum, palladium
}

/// Portföyde tutulabilen bir varlığın kalıcı kimliği.
///
/// Kalıcı biçim `id` String'idir: `gold.gram24`, `metal.silver`, `fx.USD`,
/// `crypto.bitcoin`, `custom.<kullanıcı-kimliği>`.
public enum AssetCode: Hashable, Sendable {
    case gold(GoldKind)
    case metal(PreciousMetal)
    case fx(CurrencyCode)
    /// CoinGecko kimliği, küçük harf (`bitcoin`, `ethereum`).
    case crypto(String)
    /// Fiyatı elle girilen serbest varlık (fon, hisse, mevduat).
    case custom(String)

    public var id: String {
        switch self {
        case .gold(let kind): "gold.\(kind.rawValue)"
        case .metal(let metal): "metal.\(metal.rawValue)"
        case .fx(let code): "fx.\(code.rawValue)"
        case .crypto(let id): "crypto.\(id)"
        case .custom(let id): "custom.\(id)"
        }
    }

    public init?(id: String) {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        let kind = id[..<dot]
        let value = String(id[id.index(after: dot)...])
        guard !value.isEmpty else { return nil }
        switch kind {
        case "gold": guard let k = GoldKind(rawValue: value) else { return nil }; self = .gold(k)
        case "metal": guard let m = PreciousMetal(rawValue: value) else { return nil }; self = .metal(m)
        case "fx": guard let c = CurrencyCode(rawValue: value) else { return nil }; self = .fx(c)
        case "crypto":
            guard value.allSatisfy({ $0.isASCIIDigit || ("a"..."z").contains($0) || $0 == "-" }) else { return nil }
            self = .crypto(value)
        case "custom": self = .custom(value)
        default: return nil
        }
    }

    public var unit: QuantityUnit {
        switch self {
        case .gold(let kind): kind.unit
        case .metal: .gram
        case .fx, .crypto, .custom: .unit
        }
    }

    /// Miktarın gösterimdeki en fazla ondalık basamağı (specs/03 giriş).
    public var quantityScale: Int {
        switch self {
        case .gold(let kind): kind.unit == .gram ? 3 : 0
        case .metal: 3
        case .fx(let code): code.minorUnits
        case .crypto: 8
        case .custom: 4
        }
    }

    /// Ons fiyatı × USD/TRY ile türetilebilir mi (specs/02 §3). Ziynet altınlar türetilemez.
    public var isDerivableFromSpot: Bool {
        switch self {
        case .gold(.gram24), .gold(.has), .metal: true
        default: false
        }
    }
}

extension AssetCode: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let code = AssetCode(id: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bilinmeyen varlık: \(raw)")
        }
        self = code
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// Birimiyle birlikte bir varlık miktarı.
public struct Quantity: Hashable, Sendable, Codable {
    public var value: Decimal
    public var unit: QuantityUnit

    public init(_ value: Decimal, _ unit: QuantityUnit) {
        self.value = value
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case value, unit }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        guard let value = Decimal(canonical: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container,
                                                   debugDescription: "Kanonik olmayan miktar: \(raw)")
        }
        self.init(value, try container.decode(QuantityUnit.self, forKey: .unit))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.canonicalString, forKey: .value)
        try container.encode(unit, forKey: .unit)
    }
}
