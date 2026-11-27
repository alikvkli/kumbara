import Foundation

extension Decimal {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Kanonik kalıcı biçimden okur: isteğe bağlı `-`, rakamlar, isteğe bağlı `.` ve rakamlar.
    /// Örnek: `"1234.56"`, `"-0.001"`. Gruplama, üs, boşluk kabul edilmez.
    /// SwiftData/CloudKit'te Decimal alanlar bu biçimde String olarak saklanır (specs/05 §3).
    public init?(canonical string: String) {
        var body = Substring(string)
        if body.first == "-" { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              let value = Decimal(string: string, locale: Self.posix)
        else { return nil }
        self = value
    }

    /// Kanonik kalıcı biçim; `init?(canonical:)` ile birebir geri okunur.
    public var canonicalString: String {
        var copy = self
        return NSDecimalString(&copy, Self.posix)
    }

    /// Belirtilen ondalık basamağa yuvarlar. Yalnız gösterimde kullanılır (specs/00 C3).
    public func rounded(scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
