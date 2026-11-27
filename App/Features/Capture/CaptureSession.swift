import CoreGraphics
import Foundation
import KumbaraCapture
import KumbaraCore
import Observation
import UniformTypeIdentifiers

/// Fiş/ekran görüntüsü → OCR → taslak akışının durumu (specs/04 §2).
@MainActor
@Observable
final class CaptureSession {
    enum Source: Identifiable, Hashable {
        case camera, photos, files
        var id: Self { self }
    }

    struct Review: Identifiable {
        let id = UUID()
        let preview: CGImage?
        let lines: [TextLine]
        let result: CaptureResult
    }

    /// Bekleyen kaynak isteği (araç çubuğu / menü komutu).
    var requestedSource: Source?
    var isProcessing = false
    var review: Review?
    var errorMessage: String?

    func process(data: Data, contentType: UTType?) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let document = try await TextRecognizer.recognize(data: data, contentType: contentType)
            let result = CaptureParser().parse(document.lines)
            review = Review(preview: document.preview, lines: document.lines, result: result)
        } catch CaptureError.noText {
            errorMessage = String(localized: "Görüntüde okunabilir yazı bulunamadı.")
        } catch {
            errorMessage = String(localized: "Görüntü okunamadı.")
        }
    }

    func process(fileURL url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = String(localized: "Dosya açılamadı.")
            return
        }
        await process(data: data, contentType: UTType(filenameExtension: url.pathExtension))
    }
}
