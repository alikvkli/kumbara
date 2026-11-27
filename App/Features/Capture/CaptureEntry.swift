import KumbaraCapture
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Yakalama giriş noktaları (REQ-C1): kamera (iOS), Fotoğraflar, dosya/PDF, sürükle-bırak.
/// Kök görünüme bir kez uygulanır; araç çubuğu ve menü komutları `CaptureSession.requestedSource` ayarlar.
struct CaptureEntry: ViewModifier {
    @Environment(CaptureSession.self) private var session
    @State private var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        @Bindable var session = session

        content
            .photosPicker(isPresented: binding(for: .photos), selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        session.errorMessage = String(localized: "Fotoğraf yüklenemedi.")
                        return
                    }
                    await session.process(data: data, contentType: item.supportedContentTypes.first)
                }
            }
            .fileImporter(isPresented: binding(for: .files), allowedContentTypes: [.image, .pdf]) { result in
                guard case .success(let url) = result else { return }
                Task { await session.process(fileURL: url) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: binding(for: .camera)) {
                DocumentScanner { pages in
                    session.requestedSource = nil
                    guard let first = pages.first else { return }
                    Task { await session.process(data: first, contentType: .jpeg) }
                }
                .ignoresSafeArea()
            }
            #endif
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                Task { await session.process(fileURL: url) }
                return true
            }
            .sheet(item: $session.review) { review in
                CaptureReviewView(review: review)
            }
            .overlay {
                if session.isProcessing {
                    ProgressView("Okunuyor…")
                        .padding(20)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .alert("Okunamadı", isPresented: Binding(
                get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(verbatim: session.errorMessage ?? "")
            }
    }

    private func binding(for source: CaptureSession.Source) -> Binding<Bool> {
        Binding(
            get: { session.requestedSource == source },
            set: { if !$0, session.requestedSource == source { session.requestedSource = nil } }
        )
    }
}

/// Araç çubuğundaki fiş menüsü (iOS): tek dokunuşla kaynak seçimi.
struct CaptureMenu: View {
    @Environment(CaptureSession.self) private var session

    var body: some View {
        Menu {
            #if os(iOS)
            if DocumentScanner.isSupported {
                Button("Kamerayla tara", systemImage: "camera") { session.requestedSource = .camera }
            }
            #endif
            Button("Fotoğraflardan seç", systemImage: "photo") { session.requestedSource = .photos }
            Button("Dosyadan (PDF, görüntü)", systemImage: "doc") { session.requestedSource = .files }
        } label: {
            Label("Fiş tara", systemImage: "doc.viewfinder")
        }
    }
}

#if os(iOS)
import VisionKit

/// Belge kamerası: kenar tespiti ve perspektif düzeltme (specs/04 §1). Sayfalar JPEG olarak döner.
struct DocumentScanner: UIViewControllerRepresentable {
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    let onFinish: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        init(onFinish: @escaping ([Data]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.85) }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
#endif
