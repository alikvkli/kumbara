import Foundation

/// RFC 4180 tarzı CSV: tırnaklı alanlar, alan içinde ayırıcı / satır sonu / `""` kaçışı (specs/09 §3).
public enum CSV {
    /// Excel'in Türkçe karakterleri UTF-8 olarak tanıması için dosya başı işareti.
    public static let byteOrderMark = "\u{FEFF}"

    public static func encode(_ rows: [[String]], delimiter: Character, includeBOM: Bool = true) -> String {
        let special: Set<Character> = [delimiter, "\"", "\n", "\r"]
        var output = includeBOM ? byteOrderMark : ""
        for row in rows {
            output += row.map { field in
                field.contains(where: special.contains)
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    : field
            }.joined(separator: String(delimiter))
            output += "\r\n"
        }
        return output
    }

    /// Metni satırlara ve alanlara ayırır. Ayırıcı verilmezse ilk satırdan tahmin edilir.
    /// Boş satırlar atlanır; alanların baş/son boşlukları korunur (tırnak dışında da).
    public static func decode(_ text: String, delimiter: Character? = nil) -> [[String]] {
        var body = Substring(text)
        if body.hasPrefix(byteOrderMark) { body = body.dropFirst() }
        let separator = delimiter ?? detectDelimiter(String(body))

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = body.makeIterator()
        var pending: Character? = nil

        func endRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty:
                inQuotes = true
            case separator:
                row.append(field)
                field = ""
            case "\r\n", "\n", "\r":
                endRow()
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// İlk satırda tırnak dışında en çok geçen aday: `;`, `,`, sekme, `|`.
    public static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let candidates: [Character] = [";", ",", "\t", "|"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for character in firstLine {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, candidates.contains(character) { counts[character, default: 0] += 1 }
        }
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates where (counts[candidate] ?? 0) > bestCount {
            best = candidate
            bestCount = counts[candidate] ?? 0
        }
        return best
    }
}
