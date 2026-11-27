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

    /// Paylaş uzantısının yazdığı gelen kutusu (REQ-C2); App Group yoksa `nil`.
    let inbox: CaptureInbox?
    /// Şu an onay ekranında olan gelen kutusu dosyası: ekran kapanınca silinir.
    private var reviewingInboxItem: CaptureInbox.Item?

    init(inbox: CaptureInbox? = nil) {
        self.inbox = inbox
    }

    /// Bekleyen kaynak isteği (araç çubuğu / menü komutu).
    var requestedSource: Source?
    var isProcessing = false
    var review: Review?
    var errorMessage: String?

    /// Ayarlar › Akıllı kontrol (varsayılan açık). UI testlerinde kapalı: sonuç cihaza bağlı olmasın.
    static var smartCheckEnabled: Bool {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return false }
        return UserDefaults.standard.object(forKey: SettingsKey.smartCheck) as? Bool ?? true
    }

    func process(data: Data, contentType: UTType?) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let document = try await TextRecognizer.recognize(data: data, contentType: contentType)
            var result = CaptureParser().parse(document.lines)
            // Opsiyonel akıllı katman (specs/04 §2.5): yalnız tek fişte, ayar açıksa, cihaz destekliyorsa.
            if Self.smartCheckEnabled, result.kind == .receipt, result.drafts.count == 1,
               let reading = await SmartReader.read(result.rows) {
                result.drafts[0] = CrossCheck.apply(reading, to: result.drafts[0], rows: result.rows, calendar: .current)
            }
            review = Review(preview: document.preview, lines: document.lines, result: result)
        } catch CaptureError.noText {
            errorMessage = String(localized: "Görüntüde okunabilir yazı bulunamadı.")
        } catch {
            errorMessage = String(localized: "Görüntü okunamadı.")
        }
    }

    /// Gelen kutusundaki en eski dosyayı onaya getirir. Uygulama öne gelince ve her onay ekranı
    /// kapanınca çağrılır; böylece birden çok paylaşım sırayla onaylanır.
    func drainInbox() async {
        guard review == nil, !isProcessing, reviewingInboxItem == nil,
              let inbox, let item = inbox.pending().first else { return }
        guard let data = try? Data(contentsOf: item.url) else {
            inbox.remove(item)
            return
        }
        reviewingInboxItem = item
        await process(data: data, contentType: UTType(filenameExtension: item.fileExtension))
        if review == nil {
            // Okunamadı: hata gösterildi; aynı dosya her açılışta tekrar denenmesin.
            inbox.remove(item)
            reviewingInboxItem = nil
        }
    }

    /// Onay ekranı kapandı (kaydedildi ya da vazgeçildi).
    func reviewDismissed() async {
        if let item = reviewingInboxItem {
            inbox?.remove(item)
            reviewingInboxItem = nil
        }
        await drainInbox()
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
