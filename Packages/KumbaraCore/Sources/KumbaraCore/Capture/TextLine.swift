import Foundation

/// Görüntü üzerinde normalize dikdörtgen: 0…1, sol üst köşe orijin (specs/04 §2).
public struct TextBox: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }

    public func union(_ other: TextBox) -> TextBox {
        let minX = min(x, other.x), minY = min(y, other.y)
        let maxX = max(self.maxX, other.maxX), maxY = max(y + height, other.y + other.height)
        return TextBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// OCR'ın bir satır/parça çıktısı. Vision'dan bağımsızdır; Linux'ta test edilir.
public struct TextLine: Hashable, Sendable, Codable {
    public var text: String
    public var box: TextBox
    /// 0…1
    public var confidence: Double

    public init(text: String, box: TextBox, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// Aynı yatay hizadaki parçalar birleştirilmiş görsel satır ("TOPLAM ........ *1.249,90").
public struct TextRow: Hashable, Sendable {
    public var parts: [TextLine]
    public var text: String { parts.map(\.text).joined(separator: " ") }
    public var box: TextBox { parts.dropFirst().reduce(parts[0].box) { $0.union($1.box) } }
    public var confidence: Double { parts.map(\.confidence).min() ?? 0 }
    /// Eşleme için Türkçe harf/aksan duyarsız, küçük harf metin.
    public var key: String { CaptureText.fold(text) }

    /// Parçaları dikey merkez yakınlığına göre satırlara toplar (yukarıdan aşağı, soldan sağa).
    public static func group(_ lines: [TextLine]) -> [TextRow] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let index = rows.lastIndex(where: { row in
                let height = (row.map(\.box.height).reduce(0, +) / Double(row.count) + line.box.height) / 2
                // 0,7 × satır yüksekliği: ~2°'lik eğik fotoğrafta aynı satırın uçları ayrılmaz;
                // fişte satır aralığı ≥ 1,4 × yükseklik olduğundan komşu satırlar birleşmez.
                let rowMid = row.map(\.box.midY).reduce(0, +) / Double(row.count)
                return abs(rowMid - line.box.midY) < height * 0.7
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { TextRow(parts: $0.sorted { $0.box.x < $1.box.x }) }
    }
}

enum CaptureText {
    private static let turkish = Locale(identifier: "tr_TR")

    /// "MİGROS TİC. A.Ş." → "migros tic. a.s."; ı → i; aksanlar katlanır, noktalama korunur.
    static func fold(_ text: String) -> String {
        text.lowercased(with: turkish)
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: turkish)
    }

    /// Levenshtein mesafesi (kısa anahtar kelimelerde OCR hatası toleransı için).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Satırda kelime (OCR hatası payıyla) geçiyor mu. 5+ harfli kelimelerde 1 hata kabul.
    static func contains(_ row: String, word: String) -> (found: Bool, exact: Bool) {
        if row.contains(word) { return (true, true) }
        let tolerance = word.count >= 5 ? 1 : 0
        guard tolerance > 0 else { return (false, false) }
        // OCR'ın sık karıştırdıkları: 0↔o, 1↔i/l, 5↔s
        let normalized = row.replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "5", with: "s")
        if normalized.contains(word) { return (true, false) }
        let tokens = normalized.split(whereSeparator: { !$0.isLetter })
        let wordTokens = word.split(separator: " ")
        guard wordTokens.count <= tokens.count else { return (false, false) }
        for start in 0...(tokens.count - wordTokens.count) {
            let window = tokens[start..<(start + wordTokens.count)].joined(separator: " ")
            if distance(window, word) <= tolerance { return (true, false) }
        }
        return (false, false)
    }
}
