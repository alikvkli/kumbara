import CoreGraphics
import Foundation
import ImageIO
import KumbaraCore
import PDFKit
import UniformTypeIdentifiers
import Vision

public enum CaptureError: Error, Equatable {
    case unreadableImage
    case unreadablePDF
    case noText
}

/// Cihaz üstü OCR (specs/04 §2.1, C2): Vision `RecognizeTextRequest`, Türkçe + İngilizce,
/// doğru mod, dil düzeltme açık. Görüntü cihazdan çıkmaz.
public enum TextRecognizer {
    public static func recognize(_ image: CGImage) async throws -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation -> TextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox.cgRect
            // Vision: sol alt orijin → TextBox: sol üst orijin
            let box = TextBox(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
            return TextLine(text: candidate.string, box: box, confidence: Double(candidate.confidence))
        }
    }

    /// Görüntü, PDF ya da metin katmanlı PDF → satırlar. PDF'te metin katmanı varsa OCR yapılmaz.
    public static func recognize(data: Data, contentType: UTType?) async throws -> RecognizedDocument {
        if contentType?.conforms(to: .pdf) == true || data.starts(with: Array("%PDF".utf8)) {
            return try await recognizePDF(data)
        }
        guard let image = ImageLoader.cgImage(from: data, maxPixel: 3000) else { throw CaptureError.unreadableImage }
        let lines = try await recognize(image)
        guard !lines.isEmpty else { throw CaptureError.noText }
        return RecognizedDocument(lines: lines, preview: image)
    }

    private static func recognizePDF(_ data: Data) async throws -> RecognizedDocument {
        guard let document = PDFDocument(data: data), document.pageCount > 0, let page = document.page(at: 0) else {
            throw CaptureError.unreadablePDF
        }
        let preview = ImageLoader.render(page, maxPixel: 2000)
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            // E-arşiv/e-fatura: metin katmanı güvenilir; satırlara sıralı sahte kutular verilir.
            let rows = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let step = 1.0 / Double(max(rows.count, 1))
            let lines = rows.enumerated().map { index, row in
                TextLine(text: row, box: TextBox(x: 0.05, y: Double(index) * step, width: 0.9, height: step * 0.8), confidence: 1)
            }
            return RecognizedDocument(lines: lines, preview: preview)
        }
        guard let preview else { throw CaptureError.unreadablePDF }
        let lines = try await recognize(preview)
        guard !lines.isEmpty else { throw CaptureError.noText }
        return RecognizedDocument(lines: lines, preview: preview)
    }
}

/// OCR sonucu ve önizleme görüntüsü. `CGImage` değişmez olduğu için aktörler arası taşınması güvenlidir.
public struct RecognizedDocument: @unchecked Sendable {
    public let lines: [TextLine]
    public let preview: CGImage?
}

public enum ImageLoader {
    /// Uzun kenarı `maxPixel`'e küçültülmüş, yönü düzeltilmiş görüntü.
    public static func cgImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func render(_ page: PDFPage, maxPixel: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = maxPixel / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

/// OCR çıktısını test korpusu biçiminde dışa aktarır (T3.1, specs/04 §6). Kişisel bilgiyi
/// kullanıcı paylaşmadan önce kendisi temizler; uygulama hiçbir yere göndermez.
public enum CorpusExport {
    public static func json(lines: [TextLine], description: String, now: Date = .now) -> Data {
        let entries: [[Any]] = lines.map { [$0.text, round4($0.box.x), round4($0.box.y), round4($0.confidence)] }
        let object: [String: Any] = [
            "source": "device",
            "description": description,
            "now": ISO8601DateFormatter().string(from: now),
            "lines": entries,
            "expect": ["kind": "?"],
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}
