import Foundation

/// Kullanıcı girişinden veya OCR metninden tutar okur (specs/04 §2.3, specs/01 REQ-L4).
///
/// Kabul ettiği biçimler: `1.249,90` · `1249,90` · `*1.249,90` · `1.249,90 TL` · `₺1.249,90`
/// · `1,249.90` · `-12,5` · `12,50-`.
///
/// Ayırıcı kuralı:
/// - Hem `.` hem `,` varsa: **sondaki** ondalık ayırıcıdır, diğeri gruplamadır.
/// - Tek tür ayırıcı birden çok kez geçiyorsa: gruplamadır.
/// - Tek tür ayırıcı bir kez geçiyorsa: yerel ondalık ayırıcıyla aynıysa ondalıktır;
///   değilse ve ardından tam 3 rakam geliyorsa gruplamadır, aksi halde ondalıktır.
public struct AmountParser: Sendable {
    public var decimalSeparator: Character

    /// Varsayılan: Türkçe (`,` ondalık).
    public init(decimalSeparator: Character = ",") {
        precondition(decimalSeparator == "," || decimalSeparator == ".")
        self.decimalSeparator = decimalSeparator
    }

    public init(locale: Locale) {
        self.init(decimalSeparator: locale.decimalSeparator == "." ? "." : ",")
    }

    public func parse(_ input: String) -> Decimal? {
        var text = input
        for token in ["TRY", "TL", "USD", "EUR", "GBP", "₺", "$", "€", "£", "*"] {
            text = text.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        text = String(text.filter { !$0.isWhitespace })

        var negative = false
        if let first = text.first, first == "-" || first == "−" {
            negative = true
            text.removeFirst()
        } else if let last = text.last, last == "-" || last == "−" {
            negative = true
            text.removeLast()
        }

        guard !text.isEmpty, text.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," }),
              text.first!.isASCIIDigit || text.first == "." || text.first == ","
        else { return nil }

        let dots = text.count(where: { $0 == "." })
        let commas = text.count(where: { $0 == "," })
        let decimal: Character?

        switch (dots, commas) {
        case (0, 0):
            decimal = nil
        case (_, _) where dots > 0 && commas > 0:
            decimal = text.last(where: { $0 == "." || $0 == "," })
            // Ondalık ayırıcı yalnız bir kez ve en sonda geçebilir.
            let other: Character = decimal == "." ? "," : "."
            guard text.count(where: { $0 == decimal }) == 1,
                  let decIndex = text.lastIndex(of: decimal!),
                  let otherIndex = text.lastIndex(of: other), otherIndex < decIndex
            else { return nil }
        default:
            let separator: Character = dots > 0 ? "." : ","
            let occurrences = max(dots, commas)
            if occurrences > 1 {
                decimal = nil
            } else if separator == decimalSeparator {
                decimal = separator
            } else {
                let digitsAfter = text.distance(from: text.lastIndex(of: separator)!, to: text.endIndex) - 1
                decimal = digitsAfter == 3 ? nil : separator
            }
        }

        var normalized = ""
        var integerPart = true
        var groupLengths: [Int] = [0]
        for character in text {
            if character == decimal {
                integerPart = false
                normalized.append(".")
            } else if character == "." || character == "," {
                guard integerPart else { return nil }
                groupLengths.append(0)
            } else {
                normalized.append(character)
                if integerPart { groupLengths[groupLengths.count - 1] += 1 }
            }
        }

        // Gruplama varsa: ilk grup 1–3, diğerleri tam 3 rakam olmalı ("1.24.9" geçersiz).
        if groupLengths.count > 1 {
            guard (1...3).contains(groupLengths[0]), groupLengths.dropFirst().allSatisfy({ $0 == 3 }) else { return nil }
        }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        guard !normalized.hasSuffix("."), let value = Decimal(canonical: normalized) else { return nil }
        return negative ? -value : value
    }
}
