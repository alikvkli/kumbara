import Foundation

/// Para birimiyle birlikte bir tutar. Birimsiz tutar kalıcı katmana yazılmaz (specs/00 C3).
///
/// Farklı para birimleri arasında aritmetik bir programlama hatasıdır ve `precondition`
/// ile durdurulur; çeviri her zaman açıkça `converted(to:rate:)` ile yapılır.
public struct Money: Hashable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(_ amount: Decimal, _ currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money { Money(0, currency) }

    public var isZero: Bool { amount.isZero }
    public var isNegative: Bool { amount < 0 }
    public var magnitude: Money { Money(abs(amount), currency) }

    /// `rate`: 1 birim `self.currency` kaç birim `target` eder.
    public func converted(to target: CurrencyCode, rate: Decimal) -> Money {
        precondition(rate > 0, "Kur pozitif olmalı")
        return Money(amount * rate, target)
    }

    /// Para biriminin küsurat basamağına yuvarlanmış kopya (gösterim için).
    public func rounded(_ mode: NSDecimalNumber.RoundingMode = .plain) -> Money {
        Money(amount.rounded(scale: currency.minorUnits, mode), currency)
    }
}

extension Money {
    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Para birimi uyuşmazlığı: \(lhs.currency) + \(rhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Para birimi uyuşmazlığı: \(lhs.currency) - \(rhs.currency)")
        return Money(lhs.amount - rhs.amount, lhs.currency)
    }

    public static prefix func - (value: Money) -> Money { Money(-value.amount, value.currency) }

    public static func * (lhs: Money, rhs: Decimal) -> Money { Money(lhs.amount * rhs, lhs.currency) }
    public static func * (lhs: Decimal, rhs: Money) -> Money { rhs * lhs }

    public static func / (lhs: Money, rhs: Decimal) -> Money {
        precondition(!rhs.isZero, "Sıfıra bölme")
        return Money(lhs.amount / rhs, lhs.currency)
    }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Para birimi uyuşmazlığı")
        return lhs.amount < rhs.amount
    }
}

extension Money: Codable {
    private enum CodingKeys: String, CodingKey { case amount, currency }

    /// Tutar kanonik String olarak kodlanır; JSON sayısına (Double) dönüşüp hassasiyet kaybetmez.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .amount)
        guard let amount = Decimal(canonical: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container,
                                                   debugDescription: "Kanonik olmayan tutar: \(raw)")
        }
        self.init(amount, try container.decode(CurrencyCode.self, forKey: .currency))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount.canonicalString, forKey: .amount)
        try container.encode(currency, forKey: .currency)
    }
}

extension Sequence where Element == Money {
    /// Boş dizide `currency` cinsinden sıfır döner; farklı para birimi programlama hatasıdır.
    public func sum(in currency: CurrencyCode) -> Money {
        reduce(.zero(currency), +)
    }
}
