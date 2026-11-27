import Foundation

/// Satıcı adını eşleme anahtarına indirger (REQ-L6, specs/04 §2.3).
///
/// `"MİGROS TİC. A.Ş."` → `"migros"`, `"Şok Market"` → `"sok market"`.
/// Türkçe büyük/küçük harf kuralları uygulanır (İ→i, I→ı), sonra aksanlar katlanır
/// (ı→i, ş→s…), unvan ekleri ve noktalama atılır.
public enum MerchantKey {
    private static let turkish = Locale(identifier: "tr_TR")

    /// Ad sonundaki tüzel kişilik ekleri (sırayla, tekrar tekrar atılır).
    private static let legalSuffixes: Set<String> = [
        "as", "a s", "ltd", "sti", "tic", "san", "ve", "ltd sti", "anonim", "sirketi", "limited",
        "pazarlama", "gida", "magazacilik",
    ]

    public static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased(with: turkish)
        let folded = lowered
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: turkish)

        let spaced = String(folded.map { (character: Character) -> Character in
            character.isLetter || character.isNumber ? character : " "
        })
        var words = spaced.split(separator: " ").map(String.init)

        // "a.ş." → ["a", "s"] olur; tek harfli artıkları da birleşik ek olarak ele al.
        while let last = words.last {
            if legalSuffixes.contains(last) {
                words.removeLast()
            } else if words.count >= 2, legalSuffixes.contains(words.suffix(2).joined(separator: " ")) {
                words.removeLast(2)
            } else {
                break
            }
        }
        return words.joined(separator: " ")
    }
}

/// Satıcı → kategori öğrenme kuralı (REQ-L6): son kullanılan kategori önerilir.
public struct MerchantRule: Hashable, Sendable {
    public var key: String
    public var displayName: String
    public var categoryID: UUID
    public var lastUsed: Date
    public var useCount: Int

    public init(key: String, displayName: String, categoryID: UUID, lastUsed: Date, useCount: Int = 1) {
        self.key = key
        self.displayName = displayName
        self.categoryID = categoryID
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}

public struct MerchantRuleBook: Sendable {
    public private(set) var rules: [String: MerchantRule]

    public init(_ rules: some Sequence<MerchantRule> = []) {
        self.rules = Dictionary(rules.map { ($0.key, $0) }, uniquingKeysWith: { $0.lastUsed >= $1.lastUsed ? $0 : $1 })
    }

    /// Kayıt sonrası kuralı günceller; yeni/değişen kuralı döner. Boş anahtar kaydedilmez.
    @discardableResult
    public mutating func record(merchant: String, categoryID: UUID, at date: Date) -> MerchantRule? {
        let key = MerchantKey.normalize(merchant)
        guard !key.isEmpty else { return nil }
        let display = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var rule = rules[key] ?? MerchantRule(key: key, displayName: display, categoryID: categoryID,
                                              lastUsed: date, useCount: 0)
        if date >= rule.lastUsed {
            rule.categoryID = categoryID
            rule.lastUsed = date
            rule.displayName = display
        }
        rule.useCount += 1
        rules[key] = rule
        return rule
    }

    public func suggestedCategory(for merchant: String) -> UUID? {
        rules[MerchantKey.normalize(merchant)]?.categoryID
    }

    /// Otomatik tamamlama: anahtarı veya bir kelimesi önekle başlayanlar; sık ve yeni olan önce.
    public func completions(for prefix: String, limit: Int = 5) -> [MerchantRule] {
        let needle = MerchantKey.normalize(prefix)
        guard !needle.isEmpty else { return [] }
        return rules.values
            .filter { rule in
                rule.key.hasPrefix(needle) || rule.key.split(separator: " ").contains { $0.hasPrefix(needle) }
            }
            .sorted { lhs, rhs in
                (lhs.useCount, lhs.lastUsed) != (rhs.useCount, rhs.lastUsed)
                    ? (lhs.useCount, lhs.lastUsed) > (rhs.useCount, rhs.lastUsed)
                    : lhs.key < rhs.key
            }
            .prefix(limit)
            .map { $0 }
    }
}
