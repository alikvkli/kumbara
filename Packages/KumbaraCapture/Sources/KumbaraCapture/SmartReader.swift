import Foundation
import KumbaraCore

#if canImport(FoundationModels)
import FoundationModels

/// Opsiyonel akıllı katman (specs/04 §2.5): Apple Intelligence'ın cihaz üstü modeli fiş metnini
/// okur, `CrossCheck` kural tabanlı sonuçla karşılaştırır. Görüntü değil yalnız OCR metni verilir;
/// her şey cihazda kalır (C2). Desteklemeyen cihazda, kapalıyken ya da süre aşılırsa `nil`.
public enum SmartReader {
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Onay ekranı en fazla `budget` kadar bekler; model yetişmezse kurallarla devam edilir.
    public static func read(_ rows: [TextRow], budget: Duration = .seconds(5)) async -> ModelReading? {
        guard isAvailable, !rows.isEmpty else { return nil }
        let text = rows.prefix(80).map(\.text).joined(separator: "\n")
        return await withTaskGroup(of: ModelReading?.self) { group in
            group.addTask { try? await ask(text) }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func ask(_ text: String) async throws -> ModelReading {
        let session = LanguageModelSession(instructions: """
            You read Turkish shop receipts that were recognised by OCR and may contain errors. \
            Report only values that are printed on the receipt. If a value is not printed, leave it empty. \
            Never compute, guess or invent a value.
            """)
        let response = try await session.respond(
            to: "Receipt text (one line per row):\n\(text)",
            generating: ReceiptFields.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.reading
    }
}

@Generable
struct ReceiptFields {
    @Guide(description: "The grand total actually paid (TOPLAM / GENEL TOPLAM / ÖDENECEK), as a plain number with a dot as the decimal separator, e.g. 1249.90. Not VAT (KDV), not a line item.")
    var total: String?

    @Guide(description: "The purchase date printed on the receipt as YYYY-MM-DD. Not an expiry date (SKT).")
    var date: String?

    @Guide(description: "The shop or brand name as printed, without legal suffixes such as A.Ş., Ltd. Şti., Tic.")
    var merchant: String?

    @Guide(description: "One of: market.food, market.household, dining.restaurant, dining.cafe, dining.delivery, transport.fuel, transport.public, transport.taxi, transport.tolls, health.pharmacy, health.doctor, clothing, entertainment, personal, other.expense")
    var category: String?
}

extension ReceiptFields {
    var reading: ModelReading {
        ModelReading(amount: total.flatMap(Self.amount), date: date.flatMap(Self.day),
                     merchant: merchant, categoryKey: category?.trimmingCharacters(in: .whitespaces))
    }

    static func amount(_ raw: String) -> Decimal? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        // "1249.90" beklenir; model yine de "1.249,90" yazarsa son ayırıcı ondalıktır.
        guard let last = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) else { return Decimal(canonical: cleaned) }
        let integer = cleaned[..<last].filter(\.isNumber)
        let fraction = cleaned[cleaned.index(after: last)...]
        return Decimal(canonical: "\(integer).\(fraction)")
    }

    static func day(_ raw: String) -> DateComponents? {
        let parts = raw.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}

#else

public enum SmartReader {
    public static var isAvailable: Bool { false }
    public static func read(_ rows: [TextRow], budget: Duration = .seconds(5)) async -> ModelReading? { nil }
}

#endif
