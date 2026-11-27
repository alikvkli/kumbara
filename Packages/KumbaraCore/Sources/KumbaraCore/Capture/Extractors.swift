import Foundation

/// Satırdan tutar ve tarih çıkarıcılar (specs/04 §2.3).
enum Extract {
    /// Tutar adayları: `1.249,90` · `*1.249,90` · `1249,90` · `₺1.249,90` · `1.249,90 TL` · `-750,00` · `1,249.90`.
    /// Fiş ve banka ekranlarında tutar her zaman 2 küsurat basamaklıdır; bu, adet/kod/telefon gibi
    /// sayıları eler.
    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])([+\-−])?\s?[*₺$€]?\s?(\d{1,3}(?:[.\s]\d{3})+|\d+)([.,]\d{2})(?![\d]|[.,]\d)\s?(?:TL|TRY|₺)?"#,
        options: [.caseInsensitive])

    struct Amount: Equatable {
        var value: Decimal
        /// Metinde açık işaret var mı (+/−); banka listelerinde yön belirler.
        var sign: Sign
        var range: Range<String.Index>
        enum Sign { case none, plus, minus }
    }

    static func amounts(in text: String) -> [Amount] {
        let parser = AmountParser(decimalSeparator: ",")
        let ns = text as NSString
        return amountPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let sign: Amount.Sign
            if let signRange = Range(match.range(at: 1), in: text) {
                sign = text[signRange] == "+" ? .plus : .minus
            } else {
                sign = .none
            }
            let integer = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: " ", with: "")
            let fraction = ns.substring(with: match.range(at: 3))
            // Ondalık ayırıcı kesin: son 2 hane. Gruplamayı kaldırıp kanonik biçime çevir.
            let digits = integer.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(canonical: digits + "." + fraction.dropFirst()) ?? parser.parse(integer + fraction),
                  value > 0 else { return nil }
            return Amount(value: value, sign: sign, range: range)
        }
    }

    static let monthNames: [String: Int] = [
        "ocak": 1, "oca": 1, "subat": 2, "sub": 2, "mart": 3, "mar": 3, "nisan": 4, "nis": 4,
        "mayis": 5, "may": 5, "haziran": 6, "haz": 6, "temmuz": 7, "tem": 7, "agustos": 8, "agu": 8,
        "eylul": 9, "eyl": 9, "ekim": 10, "eki": 10, "kasim": 11, "kas": 11, "aralik": 12, "ara": 12,
    ]

    private static let numericDate = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})[./\-](\d{1,2})[./\-](\d{4}|\d{2})(?!\d)"#)
    private static let namedDate = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s+([a-z]{3,8})\.?\s*(\d{4})?"#)
    private static let time = try! NSRegularExpression(pattern: #"(?<!\d)([01]?\d|2[0-3])[:.]([0-5]\d)(?![\d,])"#)

    struct DateMatch {
        var components: DateComponents
        var range: Range<String.Index>
    }

    /// `folded`: `CaptureText.fold` uygulanmış metin. Yıl yoksa `defaultYear`.
    static func dates(in folded: String, defaultYear: Int) -> [DateMatch] {
        let ns = folded as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [DateMatch] = []
        for match in numericDate.matches(in: folded, range: full) {
            guard let day = Int(ns.substring(with: match.range(at: 1))),
                  let month = Int(ns.substring(with: match.range(at: 2))),
                  var year = Int(ns.substring(with: match.range(at: 3))),
                  let range = Range(match.range, in: folded) else { continue }
            if year < 100 { year += 2000 }
            guard (1...12).contains(month), (1...31).contains(day) else { continue }
            result.append(DateMatch(components: DateComponents(year: year, month: month, day: day), range: range))
        }
        for match in namedDate.matches(in: folded, range: full) {
            guard let day = Int(ns.substring(with: match.range(at: 1))),
                  let month = monthNames[ns.substring(with: match.range(at: 2))],
                  let range = Range(match.range, in: folded) else { continue }
            let year = match.range(at: 3).location != NSNotFound ? Int(ns.substring(with: match.range(at: 3))) ?? defaultYear : defaultYear
            result.append(DateMatch(components: DateComponents(year: year, month: month, day: day), range: range))
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func time(in folded: String, excluding: [Range<String.Index>] = []) -> (hour: Int, minute: Int)? {
        let ns = folded as NSString
        for match in time.matches(in: folded, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: folded), !excluding.contains(where: { $0.overlaps(range) }),
                  let hour = Int(ns.substring(with: match.range(at: 1))), let minute = Int(ns.substring(with: match.range(at: 2)))
            else { continue }
            return (hour, minute)
        }
        return nil
    }
}

/// Bilinen satıcılar ve anahtar kelimeler → görünen ad ve varsayılan kategori (specs/04 §2.3–2.4).
public enum MerchantDirectory {
    public struct Entry: Hashable, Sendable {
        public let displayName: String
        /// `DefaultCategories` seed anahtarı.
        public let categoryKey: String?
    }

    /// Anahtar: `MerchantKey.normalize` biçiminde önek.
    static let chains: [(key: String, entry: Entry)] = [
        ("migros", Entry(displayName: "Migros", categoryKey: "market.food")),
        ("macrocenter", Entry(displayName: "Macrocenter", categoryKey: "market.food")),
        ("bim birlesik", Entry(displayName: "BİM", categoryKey: "market.food")),
        ("bim", Entry(displayName: "BİM", categoryKey: "market.food")),
        ("a101", Entry(displayName: "A101", categoryKey: "market.food")),
        ("sok marketler", Entry(displayName: "Şok", categoryKey: "market.food")),
        ("sok", Entry(displayName: "Şok", categoryKey: "market.food")),
        ("carrefoursa", Entry(displayName: "CarrefourSA", categoryKey: "market.food")),
        ("file market", Entry(displayName: "File", categoryKey: "market.food")),
        ("hakmar", Entry(displayName: "Hakmar", categoryKey: "market.food")),
        ("metro gross", Entry(displayName: "Metro", categoryKey: "market.food")),
        ("opet", Entry(displayName: "Opet", categoryKey: "transport.fuel")),
        ("shell", Entry(displayName: "Shell", categoryKey: "transport.fuel")),
        ("petrol ofisi", Entry(displayName: "Petrol Ofisi", categoryKey: "transport.fuel")),
        ("bp", Entry(displayName: "BP", categoryKey: "transport.fuel")),
        ("totalenergies", Entry(displayName: "TotalEnergies", categoryKey: "transport.fuel")),
        ("aytemiz", Entry(displayName: "Aytemiz", categoryKey: "transport.fuel")),
        ("starbucks", Entry(displayName: "Starbucks", categoryKey: "dining.cafe")),
        ("kahve dunyasi", Entry(displayName: "Kahve Dünyası", categoryKey: "dining.cafe")),
        ("espressolab", Entry(displayName: "Espressolab", categoryKey: "dining.cafe")),
        ("burger king", Entry(displayName: "Burger King", categoryKey: "dining.restaurant")),
        ("mcdonald", Entry(displayName: "McDonald's", categoryKey: "dining.restaurant")),
        ("dominos", Entry(displayName: "Domino's", categoryKey: "dining.restaurant")),
        ("kofteci yusuf", Entry(displayName: "Köfteci Yusuf", categoryKey: "dining.restaurant")),
        ("yemeksepeti", Entry(displayName: "Yemeksepeti", categoryKey: "dining.delivery")),
        ("getir", Entry(displayName: "Getir", categoryKey: "dining.delivery")),
        ("trendyol yemek", Entry(displayName: "Trendyol Yemek", categoryKey: "dining.delivery")),
        ("netflix", Entry(displayName: "Netflix", categoryKey: "subscriptions")),
        ("spotify", Entry(displayName: "Spotify", categoryKey: "subscriptions")),
        ("youtube", Entry(displayName: "YouTube", categoryKey: "subscriptions")),
        ("apple com bill", Entry(displayName: "Apple", categoryKey: "subscriptions")),
        ("turkcell", Entry(displayName: "Turkcell", categoryKey: "housing.internet")),
        ("vodafone", Entry(displayName: "Vodafone", categoryKey: "housing.internet")),
        ("turk telekom", Entry(displayName: "Türk Telekom", categoryKey: "housing.internet")),
        ("enerjisa", Entry(displayName: "Enerjisa", categoryKey: "housing.electricity")),
        ("ck enerji", Entry(displayName: "CK Enerji", categoryKey: "housing.electricity")),
        ("igdas", Entry(displayName: "İGDAŞ", categoryKey: "housing.gas")),
        ("baskentgaz", Entry(displayName: "Başkentgaz", categoryKey: "housing.gas")),
        ("iski", Entry(displayName: "İSKİ", categoryKey: "housing.water")),
        ("zara", Entry(displayName: "Zara", categoryKey: "clothing")),
        ("lc waikiki", Entry(displayName: "LC Waikiki", categoryKey: "clothing")),
        ("defacto", Entry(displayName: "DeFacto", categoryKey: "clothing")),
        ("koton", Entry(displayName: "Koton", categoryKey: "clothing")),
        ("istanbulkart", Entry(displayName: "İstanbulkart", categoryKey: "transport.public")),
        ("uber", Entry(displayName: "Uber", categoryKey: "transport.taxi")),
        ("bitaksi", Entry(displayName: "BiTaksi", categoryKey: "transport.taxi")),
        ("ispark", Entry(displayName: "İSPARK", categoryKey: "transport.tolls")),
    ]

    /// Ad bulunamazsa satırdaki anahtar kelimeden kategori.
    static let keywords: [(word: String, categoryKey: String)] = [
        ("akaryakit", "transport.fuel"), ("motorin", "transport.fuel"), ("benzin", "transport.fuel"),
        ("eczane", "health.pharmacy"), ("eczanesi", "health.pharmacy"),
        ("restoran", "dining.restaurant"), ("lokanta", "dining.restaurant"), ("kebap", "dining.restaurant"),
        ("cafe", "dining.cafe"), ("kahve", "dining.cafe"), ("pastane", "dining.cafe"),
        ("market", "market.food"), ("gida", "market.food"), ("bakkal", "market.food"),
    ]

    public static func lookup(_ raw: String) -> Entry? {
        let key = MerchantKey.normalize(raw)
        guard !key.isEmpty else { return nil }
        let words = key.split(separator: " ").map(String.init)
        for (chain, entry) in chains {
            let chainWords = chain.split(separator: " ").map(String.init)
            if words.starts(with: chainWords) || key == chain { return entry }
        }
        return nil
    }

    public static func category(forText raw: String) -> String? {
        if let entry = lookup(raw), let key = entry.categoryKey { return key }
        let words = Set(MerchantKey.normalize(raw).split(separator: " ").map(String.init))
        return keywords.first { words.contains($0.word) }?.categoryKey
    }
}
