import Foundation

/// Cihaz üstü dil modelinin (Apple Foundation Models) fişten okudukları (specs/04 §2.5).
/// Model yalnız ikinci görüştür; karar `CrossCheck` kurallarıyla verilir.
public struct ModelReading: Sendable, Equatable {
    public var amount: Decimal?
    /// Yalnız yıl, ay, gün.
    public var date: DateComponents?
    public var merchant: String?
    /// `DefaultCategories` gider anahtarı.
    public var categoryKey: String?

    public init(amount: Decimal? = nil, date: DateComponents? = nil, merchant: String? = nil, categoryKey: String? = nil) {
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.categoryKey = categoryKey
    }
}

/// Çapraz kontrolün sonucu; onay ekranı kullanıcıya bunu söyler.
public struct ModelCheck: Hashable, Sendable {
    public enum Field: String, Hashable, Sendable, CaseIterable {
        case amount, date, merchant, category
    }

    /// Kurallarla aynı sonuç: güven artar.
    public var agreed: Set<Field> = []
    /// Farklı okundu: kural tabanlı değer kalır, güven düşer, alan vurgulanır.
    public var conflicts: Set<Field> = []
    /// Kurallar bulamadı ya da emin değildi; modelin metinde doğrulanan değeri kullanıldı.
    public var filled: Set<Field> = []

    public init() {}
}

/// Kural tabanlı taslak + model okuması → son taslak (specs/04 §2.5).
///
/// Temel kural: modelin hiçbir değeri **fiş metninde karşılığı yoksa** kullanılmaz (uydurma
/// tutar/tarih/satıcı giremez). Tutarda anlaşmazlıkta kural tabanlı kazanır ve güven düşer.
public enum CrossCheck {
    public static func apply(_ reading: ModelReading, to draft: CapturedDraft, rows: [TextRow], calendar: Calendar) -> CapturedDraft {
        var result = draft
        var check = ModelCheck()

        // Tutar
        let amountsInText = Set(rows.flatMap { Extract.amounts(in: $0.text).map(\.value) })
        if let modelAmount = reading.amount, amountsInText.contains(modelAmount) {
            if var rule = draft.amount {
                if rule.value == modelAmount {
                    rule.confidence = max(rule.confidence, 0.97)
                    check.agreed.insert(.amount)
                } else {
                    rule.confidence = min(rule.confidence, 0.5)
                    check.conflicts.insert(.amount)
                }
                result.amount = rule
            } else {
                let box = rows.first { Extract.amounts(in: $0.text).contains { $0.value == modelAmount } }?.box
                result.amount = Suggestion(modelAmount, confidence: 0.65, boxes: box.map { [$0] } ?? [])
                check.filled.insert(.amount)
            }
        }

        // Tarih
        if let wanted = reading.date, let year = wanted.year, let month = wanted.month, let day = wanted.day {
            let grounded = rows.contains { row in
                Extract.dates(in: row.key, defaultYear: year).contains {
                    $0.components.year == year && $0.components.month == month && $0.components.day == day
                }
            }
            let rule = draft.date
            let ruleDay = calendar.dateComponents([.year, .month, .day], from: rule.value)
            let same = ruleDay.year == year && ruleDay.month == month && ruleDay.day == day
            if grounded {
                if same {
                    // Eski ama doğru okunmuş bir tarih (ör. 2016 fişi) de "anlaşıldı" sayılır.
                    result.date.confidence = max(rule.confidence, rule.confidence >= 0.8 ? 0.95 : 0.75)
                    check.agreed.insert(.date)
                } else if rule.confidence >= 0.8 {
                    result.date.confidence = min(rule.confidence, 0.55)
                    check.conflicts.insert(.date)
                } else {
                    let time = calendar.dateComponents([.hour, .minute], from: rule.value)
                    let components = DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute)
                    if let date = calendar.date(from: components) {
                        let box = rows.first { !Extract.dates(in: $0.key, defaultYear: year).isEmpty }?.box
                        result.date = Suggestion(date, confidence: 0.7, boxes: box.map { [$0] } ?? [])
                        check.filled.insert(.date)
                    }
                }
            }
        }

        // Satıcı: bilinen zincir (≥ 0,9) kesindir; model yalnız tahmini adı düzeltebilir.
        if let raw = reading.merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           (draft.merchant?.confidence ?? 0) < 0.9 {
            let key = MerchantKey.normalize(raw)
            let grounded = key.count >= 3 && rows.contains { MerchantKey.normalize($0.text).contains(key) }
            if grounded {
                let display = MerchantDirectory.lookup(raw)?.displayName ?? CaptureParser.cleanMerchant(raw)
                if let rule = draft.merchant, Self.sameMerchant(rule.value, display) {
                    result.merchant?.confidence = max(rule.confidence, 0.8)
                    check.agreed.insert(.merchant)
                } else {
                    let box = rows.first { MerchantKey.normalize($0.text).contains(key) }?.box
                    result.merchant = Suggestion(display, confidence: 0.75, boxes: box.map { [$0] } ?? [])
                    check.filled.insert(.merchant)
                }
            }
        }

        // Kategori: yalnız kurallar bulamadıysa ve geçerli bir gider anahtarıysa.
        if result.categoryKey == nil, let key = reading.categoryKey,
           DefaultCategories.expense.contains(where: { $0.key == key || $0.children.contains { $0.key == key } }) {
            result.categoryKey = key
            check.filled.insert(.category)
        } else if let key = reading.categoryKey, key == result.categoryKey {
            check.agreed.insert(.category)
        }

        result.modelCheck = check
        return result
    }

    static func sameMerchant(_ a: String, _ b: String) -> Bool {
        let x = MerchantKey.normalize(a), y = MerchantKey.normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.hasPrefix(y) || y.hasPrefix(x)
    }
}
