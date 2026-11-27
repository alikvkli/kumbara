import Foundation

/// Bir alanın önerisi ve güveni (REQ-C4). `boxes`: kanıt olarak görüntüde çerçevelenecek yerler.
public struct Suggestion<Value: Hashable & Sendable>: Hashable, Sendable {
    public var value: Value
    /// 0…1. 0,6 altı arayüzde vurgulanır.
    public var confidence: Double
    public var boxes: [TextBox]

    public init(_ value: Value, confidence: Double, boxes: [TextBox] = []) {
        self.value = value
        self.confidence = confidence
        self.boxes = boxes
    }

    public var isLowConfidence: Bool { confidence < 0.6 }
}

/// OCR'dan önerilen işlem taslağı; kullanıcı onaylayınca kayda dönüşür (C5).
public struct CapturedDraft: Hashable, Sendable {
    public var kind: TransactionKind
    public var amount: Suggestion<Decimal>?
    public var currency: CurrencyCode
    public var date: Suggestion<Date>
    public var merchant: Suggestion<String>?
    /// `DefaultCategories` seed anahtarı (satıcı hafızası uygulamada önce gelir).
    public var categoryKey: String?
    public var vat: Decimal?
    /// Cihaz üstü modelle çapraz kontrol yapıldıysa sonucu (specs/04 §2.5).
    public var modelCheck: ModelCheck? = nil
}

public enum DocumentKind: String, Sendable, Codable {
    case receipt
    case bankList
    case notification
    case unknown
}

public struct CaptureResult: Sendable {
    public var kind: DocumentKind
    public var drafts: [CapturedDraft]
    public var rows: [TextRow]
}

/// `[TextLine]` → `[CapturedDraft]` (specs/04 §2). Saf Swift; Vision'dan bağımsız.
public struct CaptureParser: Sendable {
    public var calendar: Calendar
    public var now: Date

    public init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ lines: [TextLine]) -> CaptureResult {
        let rows = TextRow.group(lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        let kind = classify(rows)
        let drafts: [CapturedDraft]
        switch kind {
        case .receipt: drafts = parseReceipt(rows).map { [$0] } ?? []
        case .bankList: drafts = parseBankList(rows)
        case .notification: drafts = parseNotification(rows).map { [$0] } ?? []
        case .unknown: drafts = parseReceipt(rows).map { [$0] } ?? []
        }
        return CaptureResult(kind: kind, drafts: drafts, rows: rows)
    }

    // MARK: Sınıflandırma (specs/04 §2.2)

    private static let receiptMarkers = ["toplam", "topkdv", "kdv", "fis no", "z no", "eku no", "ettn", "fatura", "nakit", "para ustu"]
    private static let notificationMarkers = ["harcama yapilmistir", "harcama yaptiniz", "kartinizdan", "tutarinda", "islem yapilmistir",
                                              "isyerinde", "isyerinden", "odemeniz"]

    func classify(_ rows: [TextRow]) -> DocumentKind {
        let keys = rows.map(\.key)
        let all = keys.joined(separator: "\n")
        let receiptScore = Self.receiptMarkers.filter { marker in keys.contains { CaptureText.contains($0, word: marker).found } }.count
        let notificationScore = Self.notificationMarkers.filter { all.contains($0) }.count
        let amountRows = rows.filter { !Extract.amounts(in: $0.text).isEmpty }
        let signedRows = amountRows.filter { row in Extract.amounts(in: row.text).contains { $0.sign != .none } }
        let year = calendar.component(.year, from: now)
        let dateRows = keys.filter { !Extract.dates(in: $0, defaultYear: year).isEmpty }.count

        if notificationScore >= 1 && amountRows.count <= 2 { return .notification }
        if receiptScore >= 2 { return .receipt }
        if amountRows.count >= 3 && (signedRows.count >= 2 || dateRows >= 2) { return .bankList }
        if receiptScore >= 1 { return .receipt }
        return amountRows.isEmpty ? .unknown : .receipt
    }

    // MARK: Fiş

    /// Öncelik sırası: en spesifik toplam etiketi kazanır.
    private static let totalLabels: [(label: String, confidence: Double)] = [
        ("genel toplam", 0.97), ("odenecek tutar", 0.95), ("toplam tutar", 0.95), ("toplam", 0.93),
        ("odenecek", 0.9), ("total", 0.9), ("tutar", 0.75),
    ]
    /// Toplam olmayan ama "toplam" geçebilen satırlar.
    private static let excludedForTotal = ["kdv", "topkdv", "ara toplam", "para ustu", "indirim", "matrah"]
    private static let paymentLabels = ["kredi karti", "k.karti", "banka karti", "nakit", "temassiz", "kart"]

    func parseReceipt(_ rows: [TextRow]) -> CapturedDraft? {
        let keys = rows.map(\.key)

        // Tutar
        var amount: Suggestion<Decimal>?
        labelLoop: for (label, baseConfidence) in Self.totalLabels {
            for (index, row) in rows.enumerated() {
                let key = keys[index]
                let match = CaptureText.contains(key, word: label)
                guard match.found else { continue }
                if Self.excludedForTotal.contains(where: { key.contains($0) }) && !key.contains("genel toplam") { continue }
                // Tutar aynı satırda; yoksa hemen alttaki satırda (dar fişlerde kayabilir).
                // Tutar aynı satırda; yoksa hemen altta (dar fişlerde kayar). Altta yoksa üstte: eğik
                // fişte tutar etiketin üstüne de kayabilir. Kendi etiketi olan komşu satır atlanır.
                var candidates = Extract.amounts(in: row.text).map { ($0, row) }
                if candidates.isEmpty {
                    let neighbours = [index + 1, index - 1].filter { rows.indices.contains($0) && !Self.isLabelled(keys[$0]) }
                    if let nearest = neighbours.first(where: { !Extract.amounts(in: rows[$0].text).isEmpty }) {
                        candidates = Extract.amounts(in: rows[nearest].text).map { ($0, rows[nearest]) }
                    }
                }
                guard let (found, sourceRow) = candidates.last else { continue }
                var confidence = match.exact ? baseConfidence : baseConfidence - 0.12
                // Ödeme satırı aynı tutarı söylüyorsa güven artar.
                let confirmed = rows.enumerated().contains { other in
                    other.offset != index && Self.paymentLabels.contains { keys[other.offset].contains($0) }
                        && Extract.amounts(in: other.element.text).contains { $0.value == found.value }
                }
                if confirmed { confidence = min(0.99, confidence + 0.04) }
                amount = Suggestion(found.value, confidence: confidence, boxes: [sourceRow.box])
                break labelLoop
            }
        }
        if amount == nil {
            // Yedek: KDV/ara toplam dışındaki en büyük tutar (güven düşük).
            let candidates = rows.enumerated().filter { !Self.excludedForTotal.contains(where: keys[$0.offset].contains) }
                .flatMap { item in Extract.amounts(in: item.element.text).map { ($0.value, item.element.box) } }
            if let best = candidates.max(by: { $0.0 < $1.0 }) {
                amount = Suggestion(best.0, confidence: 0.4, boxes: [best.1])
            }
        }

        // KDV
        var vat: Decimal?
        if let index = keys.firstIndex(where: { $0.contains("topkdv") || ($0.contains("kdv") && !$0.contains("dahil") && !$0.contains("%")) }) {
            vat = Extract.amounts(in: rows[index].text).last?.value
        }

        return CapturedDraft(kind: .expense, amount: amount, currency: currency(in: keys),
                             date: date(in: rows, keys: keys), merchant: merchant(in: rows, keys: keys),
                             categoryKey: nil, vat: vat)
            .withCategory(from: rows)
    }

    /// Satırda kendi etiketi var mı (KDV, ödeme, toplam…): komşu tutar ararken bunlar atlanır.
    private static func isLabelled(_ key: String) -> Bool {
        key.contains(where: \.isLetter) && (excludedForTotal.contains(where: key.contains)
            || paymentLabels.contains(where: key.contains) || totalLabels.contains { key.contains($0.label) })
    }

    private func currency(in keys: [String]) -> CurrencyCode {
        let all = keys.joined(separator: " ")
        if all.contains("usd") || all.contains("$") { return .USD }
        if all.contains("eur") || all.contains("€") { return .EUR }
        return .TRY
    }

    private static let addressMarkers = ["mah", "cad", "sok.", "sk.", "no:", "no :", "tel", "v.d", "vd:", "vergi", "mersis",
                                         "www", "http", ".com", "fis", "tarih", "saat", "kasiyer", "magaza", "sube", "adres",
                                         "bulvar", "blv", "apt", "kat:", "posta", "ttsg", "e-arsiv", "fatura"]

    func merchant(in rows: [TextRow], keys: [String]) -> Suggestion<String>? {
        // 1. Bilinen zincir herhangi bir satırda (ilk 6 satır öncelikli).
        for (index, row) in rows.prefix(6).enumerated() {
            if let entry = MerchantDirectory.lookup(row.text) {
                return Suggestion(entry.displayName, confidence: 0.92, boxes: [rows[index].box])
            }
        }
        // 2. Üst satırlardan adres/fiş bilgisi olmayan, harf ağırlıklı ilk satır.
        for row in rows.prefix(5) {
            let key = row.key
            let letters = row.text.filter(\.isLetter).count
            let digits = row.text.filter(\.isNumber).count
            guard letters >= 3, digits <= letters / 3,
                  !Self.addressMarkers.contains(where: { key.contains($0) }) else { continue }
            let cleaned = Self.cleanMerchant(row.text)
            guard !cleaned.isEmpty else { continue }
            return Suggestion(cleaned, confidence: 0.6, boxes: [row.box])
        }
        return nil
    }

    /// "MİGROS TİC. A.Ş." → "Migros Tic." değil "Migros": unvan ekleri atılır, büyük harf yumuşatılır.
    static func cleanMerchant(_ raw: String) -> String {
        let suffixes: Set<String> = ["a.ş.", "a.s.", "aş", "a.ş", "ltd.", "ltd", "şti.", "şti", "sti.", "tic.", "tic", "san.", "san",
                                     "ve", "anonim", "şirketi", "limited", "pazarlama", "a.s"]
        var words = raw.split(separator: " ").map(String.init)
        // "SAMSUN SPOR KUL.DER.İKT." → kısaltma zinciri (noktalı kısa parçalar) unvandır.
        func isAbbreviation(_ word: String) -> Bool {
            let parts = word.split(separator: ".", omittingEmptySubsequences: true)
            return word.contains(".") && parts.count >= 2 && parts.allSatisfy { $0.count <= 4 && $0.allSatisfy(\.isLetter) }
        }
        while let last = words.last,
              suffixes.contains(last.lowercased(with: Locale(identifier: "tr_TR"))) || (words.count > 1 && isAbbreviation(last)) {
            words.removeLast()
        }
        let turkish = Locale(identifier: "tr_TR")
        return words.map { word in
            guard word == word.uppercased(with: turkish), word.count > 3 else { return word }
            return word.prefix(1) + word.dropFirst().lowercased(with: turkish)
        }
        .joined(separator: " ")
    }

    func date(in rows: [TextRow], keys: [String]) -> Suggestion<Date> {
        let year = calendar.component(.year, from: now)
        var best: (date: Date, confidence: Double, rank: Int, box: TextBox)?
        for (index, key) in keys.enumerated() {
            // "19 MAYIS VD" vergi dairesi adıdır, tarih değil.
            if !key.contains("tarih"), key.range(of: #"\bv\.?\s?d\b|vergi"#, options: .regularExpression) != nil { continue }
            for match in Extract.dates(in: key, defaultYear: year) {
                var components = match.components
                // Saat aynı satırda ya da hemen altta
                let time = Extract.time(in: key, excluding: [match.range])
                    ?? (index + 1 < keys.count ? Extract.time(in: keys[index + 1]) : nil)
                components.hour = time?.hour ?? 12
                components.minute = time?.minute ?? 0
                guard let date = calendar.date(from: components),
                      calendar.component(.day, from: date) == match.components.day else { continue }
                let labelled = key.contains("tarih")
                var confidence = labelled ? 0.92 : 0.85
                // Beklenmedik derecede eski/ileri tarih: yine de önerilir ama düşük güvenle (kullanıcı onaylar).
                let plausible = date <= now.addingTimeInterval(86_400) && date >= now.addingTimeInterval(-366 * 86_400)
                if !plausible { confidence = 0.3 }
                // Sıra: etiketli > makul aralıkta > diğerleri. Etiketli ama eski bir tarih, etiketsiz bir
                // ifadeden ("19 Mayıs") daha güvenilirdir.
                let rank = (labelled ? 2 : 0) + (plausible ? 1 : 0)
                if best == nil || rank > best!.rank { best = (date, confidence, rank, rows[index].box) }
            }
        }
        if let best { return Suggestion(best.date, confidence: best.confidence, boxes: [best.box]) }
        return Suggestion(now, confidence: 0.2)
    }

    // MARK: Banka hareket listesi (REQ-C5)

    private static let skipInList = ["bakiye", "kullanilabilir", "limit", "toplam borc", "donem borcu", "asgari"]

    func parseBankList(_ rows: [TextRow]) -> [CapturedDraft] {
        let year = calendar.component(.year, from: now)
        var currentDate: (date: Date, box: TextBox)?
        var drafts: [CapturedDraft] = []
        for (index, row) in rows.enumerated() {
            let key = row.key
            let dates = Extract.dates(in: key, defaultYear: year)
            let amounts = Extract.amounts(in: row.text)
            if var components = dates.first?.components {
                components.hour = 12
                if let date = calendar.date(from: components) { currentDate = (date, row.box) }
            }
            guard let amount = amounts.last, !Self.skipInList.contains(where: key.contains) else { continue }
            // Açıklama: tutar ve tarih dışındaki metin; boşsa bir üst satır.
            var description = row.text
            description.removeSubrange(amount.range)
            if !dates.isEmpty {
                description = description.replacingOccurrences(of: #"\d{1,2}[./\-]\d{1,2}[./\-]\d{2,4}"#, with: "", options: .regularExpression)
            }
            description = description.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–·|"))
            if description.filter(\.isLetter).count < 2, index > 0 {
                description = rows[index - 1].text
            }
            let kind: TransactionKind = amount.sign == .plus ? .income : .expense
            let merchantName = MerchantDirectory.lookup(description)?.displayName ?? Self.cleanMerchant(description)
            var draft = CapturedDraft(
                kind: kind,
                amount: Suggestion(amount.value, confidence: amount.sign == .none ? 0.7 : 0.9, boxes: [row.box]),
                currency: .TRY,
                date: currentDate.map { Suggestion($0.date, confidence: 0.85, boxes: [$0.box]) } ?? Suggestion(now, confidence: 0.2),
                merchant: merchantName.isEmpty ? nil : Suggestion(merchantName, confidence: 0.7, boxes: [row.box]),
                categoryKey: nil, vat: nil)
            if kind == .expense { draft.categoryKey = MerchantDirectory.category(forText: description) }
            drafts.append(draft)
        }
        return drafts
    }

    // MARK: Bildirim / SMS

    private static let merchantPatterns = [
        #"([\p{L}\p{N}][\p{L}\p{N} .&'\-]{1,40}?)\s+(?:isyerinde|isyerinden|uye isyerinde)"#,
        #"(?:isyeri|uye isyeri)\s*:?\s*([\p{L}\p{N}][\p{L}\p{N} .&'\-]{1,40})"#,
    ]

    func parseNotification(_ rows: [TextRow]) -> CapturedDraft? {
        let text = rows.map(\.text).joined(separator: " ")
        let folded = CaptureText.fold(text)
        guard let amount = Extract.amounts(in: text).first else { return nil }
        var merchant: Suggestion<String>?
        for pattern in Self.merchantPatterns {
            if let range = folded.range(of: pattern, options: .regularExpression),
               let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: folded, range: NSRange(range, in: folded)),
               let group = Range(match.range(at: 1), in: folded) {
                // Katlanmış metindeki konumu özgün metne taşı (harf sayısı aynı kalır).
                var name = text.count == folded.count
                    ? String(text[text.index(text.startIndex, offsetBy: folded.distance(from: folded.startIndex, to: group.lowerBound))..<text.index(text.startIndex, offsetBy: folded.distance(from: folded.startIndex, to: group.upperBound))])
                    : String(folded[group])
                // "13:05 tarihinde A101 …" → "A101 …"
                if let marker = CaptureText.fold(name).range(of: "tarihinde ") {
                    let offset = CaptureText.fold(name).distance(from: CaptureText.fold(name).startIndex, to: marker.upperBound)
                    name = String(name.dropFirst(offset))
                }
                let display = MerchantDirectory.lookup(name)?.displayName ?? Self.cleanMerchant(name.trimmingCharacters(in: .whitespaces))
                merchant = Suggestion(display, confidence: 0.75, boxes: rows.map(\.box))
                break
            }
        }
        let keys = rows.map(\.key)
        let kind: TransactionKind = folded.contains("hesabiniza") && folded.contains("yatirildi") ? .income : .expense
        var draft = CapturedDraft(kind: kind, amount: Suggestion(amount.value, confidence: 0.85, boxes: rows.map(\.box)),
                                  currency: currency(in: keys), date: date(in: rows, keys: keys), merchant: merchant,
                                  categoryKey: nil, vat: nil)
        if let merchant { draft.categoryKey = MerchantDirectory.category(forText: merchant.value) }
        return draft
    }
}

extension CapturedDraft {
    /// Satıcıdan, o yoksa fişteki anahtar kelimelerden kategori.
    func withCategory(from rows: [TextRow]) -> CapturedDraft {
        var copy = self
        if let merchant, let key = MerchantDirectory.category(forText: merchant.value) {
            copy.categoryKey = key
        } else {
            copy.categoryKey = rows.lazy.compactMap { MerchantDirectory.category(forText: $0.text) }.first
        }
        return copy
    }
}

/// Olası mükerrer kayıt (REQ-C6): aynı tutar, ±1 gün, benzer satıcı.
public enum DuplicateCheck {
    public static func isLikelyDuplicate(amount: Decimal, date: Date, merchant: String?,
                                         existing: LedgerEntry, calendar: Calendar) -> Bool {
        guard abs(existing.amount.amount - amount) < Decimal(string: "0.01")! else { return false }
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: existing.date),
                                               to: calendar.startOfDay(for: date)).day ?? 99)
        guard days <= 1 else { return false }
        guard let merchant, let other = existing.merchant else { return true }
        return similarity(MerchantKey.normalize(merchant), MerchantKey.normalize(other)) > 0.8
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        if a.hasPrefix(b) || b.hasPrefix(a) { return 1 }
        let distance = CaptureText.distance(a, b)
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }
}
