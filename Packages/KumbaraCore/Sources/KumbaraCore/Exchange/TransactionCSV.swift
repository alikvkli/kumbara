import Foundation

// MARK: - Dışa aktarma (specs/09 §3.1)

/// Dışa aktarılacak tek işlem; adlar çözülmüş hâlde (veri katmanı doldurur).
public struct ExportTransaction: Sendable, Hashable {
    public var date: Date
    public var kind: TransactionKind
    public var status: TransactionStatus
    public var amount: Money
    public var account: String
    public var toAccount: String?
    public var category: String?
    public var subcategory: String?
    public var merchant: String?
    public var note: String

    public init(date: Date, kind: TransactionKind, status: TransactionStatus, amount: Money, account: String,
                toAccount: String? = nil, category: String? = nil, subcategory: String? = nil,
                merchant: String? = nil, note: String = "") {
        self.date = date
        self.kind = kind
        self.status = status
        self.amount = amount
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.subcategory = subcategory
        self.merchant = merchant
        self.note = note
    }
}

public enum TransactionCSV {
    /// Yerel ayara göre: ondalık `,` ise alan ayırıcı `;` (Excel tr_TR), değilse `,`.
    public static func delimiter(for locale: Locale) -> Character {
        locale.decimalSeparator == "," ? ";" : ","
    }

    private static func isTurkish(_ locale: Locale) -> Bool { locale.language.languageCode?.identifier == "tr" }

    public static func header(locale: Locale) -> [String] {
        isTurkish(locale)
            ? ["Tarih", "Tür", "Tutar", "Para birimi", "Hesap", "Karşı hesap", "Kategori", "Alt kategori", "Satıcı", "Not", "Durum"]
            : ["Date", "Type", "Amount", "Currency", "Account", "To account", "Category", "Subcategory", "Merchant", "Note", "Status"]
    }

    /// Tutar işaretli yazılır (gider −, gelir +, transfer işaretsiz) ki tabloda toplanabilsin;
    /// binlik ayırıcı yok, ondalık ayırıcı yerel ayardan.
    public static func encode(_ transactions: [ExportTransaction], locale: Locale, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = isTurkish(locale) ? "dd.MM.yyyy HH:mm" : "yyyy-MM-dd HH:mm"
        let decimal = locale.decimalSeparator ?? "."
        let turkish = isTurkish(locale)

        func amount(_ entry: ExportTransaction) -> String {
            var value = entry.amount.amount
            if entry.kind == .expense { value = -value }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .plain)
            var text = rounded.canonicalString
            if !text.contains(".") { text += ".00" } else if text.split(separator: ".").last?.count == 1 { text += "0" }
            return decimal == "." ? text : text.replacingOccurrences(of: ".", with: decimal)
        }
        func kind(_ kind: TransactionKind) -> String {
            switch kind {
            case .expense: turkish ? "Gider" : "Expense"
            case .income: turkish ? "Gelir" : "Income"
            case .transfer: turkish ? "Transfer" : "Transfer"
            }
        }
        func status(_ status: TransactionStatus) -> String {
            switch status {
            case .posted: turkish ? "Kesin" : "Posted"
            case .draft: turkish ? "Taslak" : "Draft"
            case .planned: turkish ? "Planlı" : "Planned"
            }
        }

        let rows = [header(locale: locale)] + transactions.map { entry in
            [formatter.string(from: entry.date), kind(entry.kind), amount(entry), entry.amount.currency.rawValue,
             entry.account, entry.toAccount ?? "", entry.category ?? "", entry.subcategory ?? "",
             entry.merchant ?? "", entry.note, status(entry.status)]
        }
        return CSV.encode(rows, delimiter: delimiter(for: locale))
    }
}

// MARK: - İçe aktarma (specs/09 §3.2)

/// Banka ekstresi CSV'sinde hangi sütunun ne olduğu. Tutar tek sütunda (işaretli) ya da
/// borç/alacak diye iki sütunda olabilir.
public struct CSVImportMapping: Hashable, Sendable {
    public enum Amount: Hashable, Sendable {
        /// Tek sütun. `positiveIsExpense`: kart ekstrelerinde harcama artı yazılır.
        case signed(column: Int, positiveIsExpense: Bool)
        case split(debit: Int, credit: Int)
    }

    public var hasHeader: Bool
    public var date: Int
    public var amount: Amount
    public var description: Int
    public var dateFormat: String
    public var decimalSeparator: Character

    public init(hasHeader: Bool, date: Int, amount: Amount, description: Int, dateFormat: String, decimalSeparator: Character) {
        self.hasHeader = hasHeader
        self.date = date
        self.amount = amount
        self.description = description
        self.dateFormat = dateFormat
        self.decimalSeparator = decimalSeparator
    }
}

public struct ImportedRow: Hashable, Sendable {
    /// Dosyadaki satır numarası (1'den), hata mesajları için.
    public var line: Int
    public var date: Date
    /// Pozitif büyüklük; yön `kind`'da.
    public var amount: Decimal
    public var kind: TransactionKind
    public var description: String

    /// Aynı satırın ikinci kez içe alınmasını önleyen anahtar: gün + tutar + yön + açıklama.
    public func fingerprint(calendar: Calendar) -> String {
        ImportFingerprint.make(date: date, amount: amount, kind: kind, description: description, calendar: calendar)
    }
}

public enum ImportFingerprint {
    public static func make(date: Date, amount: Decimal, kind: TransactionKind, description: String, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        // Bankalar büyük harf ve ASCII yazar ("MIGROS KADIKOY"): Türkçe küçük harf, ı→i, aksan katlama.
        let text = description.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(amount.canonicalString)|\(kind.rawValue)|\(text)"
    }
}

public struct ImportIssue: Hashable, Sendable {
    public enum Reason: Hashable, Sendable { case date, amount, missingColumn }
    public var line: Int
    public var reason: Reason
}

public struct CSVImportResult: Hashable, Sendable {
    public var rows: [ImportedRow]
    public var issues: [ImportIssue]
}

public enum CSVImporter {
    public static let dateFormats = ["dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "MM/dd/yyyy",
                                     "dd.MM.yyyy HH:mm", "dd.MM.yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "yyyy-MM-dd HH:mm:ss",
                                     "dd.MM.yy"]

    public static func apply(_ mapping: CSVImportMapping, to table: [[String]], timeZone: TimeZone = .current) -> CSVImportResult {
        let formatter = dateFormatter(mapping.dateFormat, timeZone: timeZone)
        let parser = AmountParser(decimalSeparator: mapping.decimalSeparator)
        var rows: [ImportedRow] = []
        var issues: [ImportIssue] = []

        for (index, fields) in table.enumerated() where !(mapping.hasHeader && index == 0) {
            let line = index + 1
            func field(_ column: Int) -> String? {
                column < fields.count ? fields[column].trimmingCharacters(in: .whitespaces) : nil
            }
            guard let dateText = field(mapping.date), let descriptionText = field(mapping.description) else {
                issues.append(ImportIssue(line: line, reason: .missingColumn))
                continue
            }
            guard let date = formatter.date(from: dateText) else {
                issues.append(ImportIssue(line: line, reason: .date))
                continue
            }
            let signed: Decimal?
            switch mapping.amount {
            case let .signed(column, positiveIsExpense):
                signed = field(column).flatMap(parser.parse).map { positiveIsExpense ? -$0 : $0 }
            case let .split(debit, credit):
                let out = field(debit).flatMap { $0.isEmpty ? nil : parser.parse($0) }
                let into = field(credit).flatMap { $0.isEmpty ? nil : parser.parse($0) }
                if let out, out != 0 { signed = -abs(out) } else if let into { signed = abs(into) } else { signed = nil }
            }
            guard let signed, signed != 0 else {
                issues.append(ImportIssue(line: line, reason: .amount))
                continue
            }
            rows.append(ImportedRow(line: line, date: date, amount: abs(signed),
                                    kind: signed < 0 ? .expense : .income, description: descriptionText))
        }
        return CSVImportResult(rows: rows, issues: issues)
    }

    /// İlk satırlara bakarak sütunları, tarih biçimini ve ondalık ayırıcıyı tahmin eder.
    /// Kullanıcı eşleme ekranında hepsini değiştirebilir.
    public static func guessMapping(for table: [[String]], timeZone: TimeZone = .current) -> CSVImportMapping? {
        guard let first = table.first, !first.isEmpty else { return nil }
        let sample = Array(table.prefix(30))
        let columnCount = sample.map(\.count).max() ?? 0

        // Başlık: ilk satırda tarih ya da tutar olarak okunabilen alan yoksa.
        let hasHeader = !first.contains { guessDateFormat([$0]) != nil || AmountParser().parse($0) != nil }
        let header = hasHeader ? first.map { $0.lowercased(with: Locale(identifier: "tr_TR")) } : []
        let data = hasHeader ? Array(sample.dropFirst()) : sample
        func values(_ column: Int) -> [String] {
            data.compactMap { column < $0.count ? $0[column].trimmingCharacters(in: .whitespaces) : nil }.filter { !$0.isEmpty }
        }
        func headerIndex(_ keywords: [String]) -> Int? {
            header.firstIndex { name in keywords.contains { name.contains($0) } }
        }

        let dateColumn = headerIndex(["tarih", "date"]) ?? (0..<columnCount).first { guessDateFormat(values($0)) != nil }
        guard let dateColumn, let dateFormat = guessDateFormat(values(dateColumn)) else { return nil }

        let amountLike = (0..<columnCount).filter { column in
            column != dateColumn && !values(column).isEmpty && values(column).allSatisfy { AmountParser().parse($0) != nil }
        }
        let debit = headerIndex(["borç", "borc", "debit", "çıkan"])
        let credit = headerIndex(["alacak", "credit", "giren"])
        let amount: CSVImportMapping.Amount
        if let debit, let credit, debit != credit {
            amount = .split(debit: debit, credit: credit)
        } else if let column = headerIndex(["tutar", "amount", "miktar"]) ?? amountLike.first {
            // Hiç eksi yoksa (kart ekstresi) artılar harcamadır.
            let hasNegative = values(column).contains { $0.hasPrefix("-") || $0.hasPrefix("−") || $0.hasSuffix("-") }
            amount = .signed(column: column, positiveIsExpense: !hasNegative)
        } else {
            return nil
        }

        let amountColumns: Set<Int> = switch amount {
        case let .signed(column, _): [column]
        case let .split(debit, credit): [debit, credit]
        }
        let description = headerIndex(["açıklama", "aciklama", "description", "işlem", "detay", "satıcı"])
            .flatMap { amountColumns.contains($0) || $0 == dateColumn ? nil : $0 }
            ?? (0..<columnCount).filter { !amountColumns.contains($0) && $0 != dateColumn }
                .max { values($0).map(\.count).reduce(0, +) < values($1).map(\.count).reduce(0, +) }
            ?? dateColumn

        let amountSamples = amountColumns.flatMap(values)
        return CSVImportMapping(hasHeader: hasHeader, date: dateColumn, amount: amount, description: description,
                                dateFormat: dateFormat, decimalSeparator: guessDecimalSeparator(amountSamples))
    }

    /// Değerlerin tamamını okuyan ilk biçim.
    public static func guessDateFormat(_ values: [String], timeZone: TimeZone = .current) -> String? {
        let values = values.filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return dateFormats.first { format in
            let formatter = dateFormatter(format, timeZone: timeZone)
            // Yıl makul aralıkta olmalı: "05.11.26" dd.MM.yyyy ile 26. yıl diye okunmasın.
            let separators = format.filter { !$0.isLetter }
            return values.allSatisfy { value in
                // Foundation ayırıcıda gevşek ("03/11/2026"yi dd.MM.yyyy ile de okur); ayırıcılar birebir tutmalı.
                guard value.filter({ !$0.isNumber }) == separators, let date = formatter.date(from: value) else { return false }
                let year = Calendar(identifier: .gregorian).component(.year, from: date)
                return (1990...2100).contains(year)
            }
        }
    }

    /// Son ayırıcıdan sonra 1–2 basamak varsa o ondalıktır; karar verilemezse `,` (tr_TR).
    public static func guessDecimalSeparator(_ values: [String]) -> Character {
        for value in values {
            guard let index = value.lastIndex(where: { $0 == "." || $0 == "," }) else { continue }
            let digits = value[value.index(after: index)...].filter(\.isNumber).count
            if digits == 1 || digits == 2 { return value[index] }
        }
        return ","
    }

    private static func dateFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}
