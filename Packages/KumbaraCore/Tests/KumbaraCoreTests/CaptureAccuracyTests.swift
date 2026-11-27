import Foundation
import Testing
@testable import KumbaraCore

/// Gerçek Vision OCR çıktıları üzerinde toplu doğruluk (specs/04 §6 başarı ölçütü).
@Suite("Yakalama doğruluğu — gerçek OCR (specs/04 §6)")
struct CaptureAccuracyTests {
    struct Score {
        var total = 0, correct = 0
        var misses: [String] = []
        var ratio: Double { total == 0 ? 1 : Double(correct) / Double(total) }
        mutating func check(_ ok: Bool, _ label: String) {
            total += 1
            if ok { correct += 1 } else { misses.append(label) }
        }
    }

    @Test("Tutar ≥ %95, tarih ≥ %90, satıcı ≥ %80")
    func accuracy() throws {
        guard let dir = Bundle.module.url(forResource: "vision", withExtension: nil, subdirectory: "Fixtures/receipts") else { return }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        var amount = Score(), date = Score(), merchant = Score(), kind = Score()

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            guard let expect = root["expect"] as? [String: Any], let expectedKind = expect["kind"] as? String, expectedKind != "?" else { continue }
            let now = (root["now"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
            let lines = (root["lines"] as? [[Any]] ?? []).compactMap { entry -> TextLine? in
                guard entry.count >= 3, let text = entry[0] as? String, let x = entry[1] as? Double, let y = entry[2] as? Double else { return nil }
                let confidence = entry.count > 3 ? entry[3] as? Double ?? 1 : 1
                return TextLine(text: text, box: TextBox(x: x, y: y, width: min(0.9, Double(text.count) * 0.012), height: 0.018),
                                confidence: confidence)
            }
            let result = CaptureParser(calendar: calendar, now: now).parse(lines)
            kind.check(result.kind.rawValue == expectedKind, "\(name): tür \(result.kind)")

            let expectations: [[String: Any]] = (expect["drafts"] as? [[String: Any]]) ?? [expect]
            for (index, e) in expectations.enumerated() {
                let draft = index < result.drafts.count ? result.drafts[index] : nil
                let label = expectations.count > 1 ? "\(name)#\(index + 1)" : name
                if let value = e["amount"] as? String {
                    amount.check(draft?.amount?.value == Decimal(canonical: value),
                                 "\(label): tutar \(draft?.amount.map { "\($0.value)" } ?? "yok") ≠ \(value)")
                }
                if let value = e["date"] as? String {
                    let parts = value.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
                    let c = draft.map { calendar.dateComponents([.year, .month, .day], from: $0.date.value) }
                    date.check(c.map { [$0.year, $0.month, $0.day] == [parts[0], parts[1], parts[2]] } ?? false, "\(label): tarih")
                }
                if let value = e["merchant"] as? String {
                    merchant.check(draft?.merchant?.value == value, "\(label): satıcı \(draft?.merchant?.value ?? "yok") ≠ \(value)")
                }
            }
        }

        print("""
            Gerçek OCR doğruluğu (\(files.count) dosya):
              tür     \(kind.correct)/\(kind.total)
              tutar   \(amount.correct)/\(amount.total)  %\(Int(amount.ratio * 100))
              tarih   \(date.correct)/\(date.total)  %\(Int(date.ratio * 100))
              satıcı  \(merchant.correct)/\(merchant.total)  %\(Int(merchant.ratio * 100))
            Kaçanlar:
            \((amount.misses + date.misses + merchant.misses + kind.misses).map { "  - " + $0 }.joined(separator: "\n"))
            """)
        #expect(amount.ratio >= 0.95, "tutar %\(Int(amount.ratio * 100)): \(amount.misses)")
        #expect(date.ratio >= 0.90, "tarih %\(Int(date.ratio * 100)): \(date.misses)")
        #expect(merchant.ratio >= 0.80, "satıcı %\(Int(merchant.ratio * 100)): \(merchant.misses)")
    }
}
