import Foundation

/// Tutar ve miktarların yerel ayara göre gösterimi (specs/01 REQ-X6, specs/06 §4).
/// Biçim sistemin (ICU/CLDR) yerel ayar kurallarını izler; elle desen yazılmaz.
public enum SignDisplay: Sendable {
    /// Yalnız negatifte işaret.
    case automatic
    /// Kâr/zarar için: her zaman `+` / `-` (sıfırda işaret yok).
    case always
    /// Hiç işaret yok (yönü satır başka yoldan gösteriyorsa).
    case never
}

extension Money {
    public func formatted(locale: Locale = .current, sign: SignDisplay = .automatic,
                          fractionDigits: Int? = nil) -> String {
        let digits = fractionDigits ?? currency.minorUnits
        let style = Decimal.FormatStyle.Currency(code: currency.rawValue, locale: locale)
            .precision(.fractionLength(digits))
            .sign(strategy: sign.currencyStrategy)
        return amount.formatted(style)
    }
}

extension Decimal {
    /// Para birimi olmadan sayı (fiyat, kur). `fractionDigits` aralık olabilir: `0...3`.
    public func formattedNumber(locale: Locale = .current, fractionDigits: ClosedRange<Int>,
                                sign: SignDisplay = .automatic) -> String {
        let style = Decimal.FormatStyle(locale: locale)
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: sign.numberStrategy)
        return formatted(style)
    }

    /// Yüzde; `self` oran olarak verilir (0,1394 → %13,94).
    public func formattedPercent(locale: Locale = .current, fractionDigits: Int = 2,
                                 sign: SignDisplay = .automatic) -> String {
        let style = Decimal.FormatStyle.Percent(locale: locale)
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: sign.percentStrategy)
        return formatted(style)
    }
}

extension AssetCode {
    /// Miktarı varlığın ölçeğine göre biçimler (sondaki sıfırlar atılır): `42,5`, `0,00125`.
    public func formatQuantity(_ value: Decimal, locale: Locale = .current) -> String {
        value.formattedNumber(locale: locale, fractionDigits: 0...quantityScale)
    }
}

extension SignDisplay {
    var currencyStrategy: Decimal.FormatStyle.Currency.Configuration.SignDisplayStrategy {
        switch self {
        case .automatic: .automatic
        case .always: .always(showZero: false)
        case .never: .never
        }
    }

    var numberStrategy: Decimal.FormatStyle.Configuration.SignDisplayStrategy {
        switch self {
        case .automatic: .automatic
        case .always: .always(includingZero: false)
        case .never: .never
        }
    }

    var percentStrategy: Decimal.FormatStyle.Percent.Configuration.SignDisplayStrategy {
        numberStrategy
    }
}
