#if os(iOS)
import KumbaraCore
import SwiftUI
import VisionKit

/// Canlı tarama (v1.x, specs/04 §7): kamera açıkken fişin yazıları anında tanınır, TOPLAM bulununca
/// söylenir; kullanıcı çekmeden önce görüntünün okunur olduğunu bilir. Çekilen kare bugünkü okuma
/// hattından geçer (aynı kurallar, aynı onay ekranı; C5). Cihaz desteklemiyorsa ya da kullanıcı
/// isterse belge kamerasına geçilir.
struct LiveReceiptScanner: View {
    static let settingKey = "capture.liveScan"

    /// DataScanner bu cihazda var ve kamera izni verilmiş mi.
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    let onCapture: (Data) -> Void
    let onUseDocumentCamera: () -> Void
    let onCancel: () -> Void

    @Environment(\.locale) private var locale
    @State private var handle = ScannerHandle()
    @State private var status: LiveScanGuide.Status = .empty
    @State private var isCapturing = false
    @State private var captureFailed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScannerView(handle: handle) { status = $0 }
                .ignoresSafeArea()

            VStack(spacing: 14) {
                statusLabel
                HStack(spacing: 12) {
                    Button("Vazgeç", action: onCancel)
                        .buttonStyle(.bordered)
                    Button(action: capture) {
                        Label(isFound ? "Bu fişi kullan" : "Çek", systemImage: "camera.shutter.button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing)
                }
                .controlSize(.large)
                Button("Belge kamerasıyla çek", action: onUseDocumentCamera)
                    .font(.footnote)
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .alert("Fotoğraf alınamadı", isPresented: $captureFailed) {
            Button("Belge kamerasına geç", action: onUseDocumentCamera)
            Button("Tamam", role: .cancel) {}
        }
    }

    private var isFound: Bool { if case .found = status { true } else { false } }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .empty:
            Label("Fişi kadraja al", systemImage: "viewfinder")
                .foregroundStyle(.secondary)
        case .searching:
            Label("TOPLAM satırı görünmüyor; biraz uzaklaş ya da fişi düzelt", systemImage: "text.viewfinder")
                .foregroundStyle(.orange)
        case let .steadying(amount):
            Label("\(Money(amount, .TRY).formatted(locale: locale)) okunuyor… sabit tut", systemImage: "hand.raised")
                .foregroundStyle(.secondary)
        case let .found(amount):
            Label("Toplam \(Money(amount, .TRY).formatted(locale: locale))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        }
    }

    private func capture() {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            if let data = await handle.capture() {
                onCapture(data)
            } else {
                captureFailed = true
            }
        }
    }
}

/// SwiftUI ile tarayıcı denetleyicisi arasındaki köprü (fotoğraf çekmek için).
@MainActor
@Observable
final class ScannerHandle {
    @ObservationIgnored fileprivate weak var controller: DataScannerViewController?

    func capture() async -> Data? {
        guard let controller, let image = try? await controller.capturePhoto() else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let handle: ScannerHandle
    let onStatus: (LiveScanGuide.Status) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["tr-TR"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        handle.controller = controller
        // Görünüm hiyerarşiye girince başlar.
        Task { @MainActor in try? controller.startScanning() }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private var guide = LiveScanGuide()
        private let onStatus: (LiveScanGuide.Status) -> Void

        init(onStatus: @escaping (LiveScanGuide.Status) -> Void) {
            self.onStatus = onStatus
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(dataScanner, allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(dataScanner, allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(dataScanner, allItems)
        }

        /// Ekran koordinatlarındaki yazı kutuları 0…1'e indirgenir (TextBox, sol üst orijin).
        private func update(_ scanner: DataScannerViewController, _ items: [RecognizedItem]) {
            let size = scanner.view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let lines: [TextLine] = items.compactMap { item in
                guard case let .text(text) = item else { return nil }
                let b = text.bounds
                let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
                let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
                let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
                return TextLine(text: text.transcript,
                                box: TextBox(x: minX / size.width, y: minY / size.height,
                                             width: (maxX - minX) / size.width, height: (maxY - minY) / size.height))
            }
            onStatus(guide.observe(lines))
        }
    }
}
#endif
