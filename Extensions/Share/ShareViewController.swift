import KumbaraCore
import SwiftUI
import UniformTypeIdentifiers

/// Paylaş menüsü → "Kumbara" (REQ-C2, specs/04 §1).
///
/// Uzantıda OCR yapılmaz (bellek sınırı, specs/05 §4): dosya App Group gelen kutusuna yazılır,
/// uzantı kısa bir onayla kapanır. Kumbara bir sonraki açılışta onay ekranını gösterir.
@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case working
        case done(count: Int)
        case failed(String)
    }

    var phase: Phase = .working

    func run(_ providers: [NSItemProvider]) async {
        guard let inbox = CaptureInbox.shared() else {
            phase = .failed(String(localized: "Kumbara'nın paylaşım alanına erişilemedi."))
            return
        }
        var count = 0
        var tooLarge = false
        for provider in providers.prefix(10) {
            guard case let (data, fileExtension)? = await provider.receiptData() else { continue }
            do {
                try inbox.deposit(data, fileExtension: fileExtension)
                count += 1
            } catch CaptureInbox.DepositError.tooLarge {
                tooLarge = true
            } catch {
                continue
            }
        }
        if count > 0 {
            phase = .done(count: count)
        } else if tooLarge {
            phase = .failed(String(localized: "Dosya çok büyük (en fazla 25 MB)."))
        } else {
            phase = .failed(String(localized: "Paylaşılanlarda görüntü ya da PDF yok."))
        }
    }
}

extension NSItemProvider {
    /// PDF önce (e-arşiv faturanın metin katmanı OCR'dan daha doğru), sonra en somut görüntü türü.
    @MainActor
    func receiptData() async -> (Data, String)? {
        if hasItemConformingToTypeIdentifier(UTType.pdf.identifier), let data = try? await data(for: .pdf) {
            return (data, "pdf")
        }
        guard hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        let type = registeredContentTypes.first { $0.conforms(to: .image) && $0.preferredFilenameExtension != nil } ?? .image
        guard let data = try? await data(for: type) else { return nil }
        return (data, type.preferredFilenameExtension ?? Self.sniffExtension(data))
    }

    @MainActor
    private func data(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private static func sniffExtension(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        return "jpg"
    }
}

/// Uzantının tek ekranı: kısa bir durum kartı. Başarıda kendiliğinden kapanır.
struct ShareView: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            switch model.phase {
            case .working:
                ProgressView()
                    .controlSize(.large)
                Text("Kumbara'ya ekleniyor…")
                    .font(.headline)
            case .done(let count):
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: count)
                Group {
                    if count == 1 { Text("Gelen kutusuna eklendi") } else { Text("\(count) belge gelen kutusuna eklendi") }
                }
                .font(.headline)
                Text("Kumbara'yı açtığında tutarı ve satıcıyı onaylayacaksın.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Eklenemedi")
                    .font(.headline)
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.phase != .working {
                Button("Tamam", action: close)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.phase) {
            guard case .done = model.phase else { return }
            try? await Task.sleep(for: .seconds(1.4))
            close()
        }
    }
}

#if os(iOS)
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let providers = attachments
        Task { await model.run(providers) }
    }

    private var attachments: [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#else
import AppKit

final class ShareViewController: NSViewController {
    private let model = ShareModel()

    override func loadView() {
        view = NSHostingView(rootView: ShareView(model: model) { [weak self] in self?.finish() })
        preferredContentSize = NSSize(width: 360, height: 240)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.run(providers) }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif
