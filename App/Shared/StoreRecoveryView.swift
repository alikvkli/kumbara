import KumbaraData
import SwiftUI

/// Veri deposu açılamazsa (bozuk dosya, dolu disk, uyumsuz sürüm) uygulama kapanmaz; ne olduğunu
/// söyler ve veriyi korur (specs/06 §11, C1). Hiçbir eylem veri silmez.
struct StoreRecoveryView: View {
    let detail: String
    @State private var files = KumbaraContainer.storeFiles()
    @State private var didSetAside = false
    @State private var confirmsFreshStart = false
    @State private var setAsideFailed = false
    @State private var showsDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Kayıtların açılamadı").font(.largeTitle.weight(.bold))
                Text("Kumbara verilerini okurken bir sorun çıktı. Verilerin silinmedi; cihazında duruyor.")
                    .font(.body)

                if didSetAside {
                    Label("Eski veriler kenara alındı. Kumbara'yı kapatıp açınca boş bir başlangıç yapılır; eski dosyalar silinmez.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        step("1", "Önce Kumbara'yı tamamen kapatıp yeniden aç. Sorun geçici olabilir (ör. cihazda yer kalmaması).")
                        step("2", "Olmazsa veri dosyasının bir kopyasını kaydet; sonra güncelleme gelince geri yüklenebilir.")
                        step("3", "Hemen kullanmaya devam etmek istersen boş bir başlangıç yap. Eski dosyalar silinmez, kenara alınır.")
                    }

                    if !files.isEmpty {
                        ShareLink(items: files) {
                            Label("Veri dosyasının kopyasını kaydet", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button {
                        confirmsFreshStart = true
                    } label: {
                        Text("Boş bir başlangıç yap").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                DisclosureGroup("Teknik ayrıntı", isExpanded: $showsDetail) {
                    Text(verbatim: detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.footnote)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Boş bir başlangıç yapılsın mı?", isPresented: $confirmsFreshStart, titleVisibility: .visible) {
            Button("Kenara al ve yeniden başla") { setAside() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Mevcut veri dosyaları silinmez, aynı klasörde ayrı bir adla saklanır. Kumbara'yı kapatıp açınca boş başlar.")
        }
        .alert("Dosyalar kenara alınamadı", isPresented: $setAsideFailed) {
            Button("Tamam") {}
        } message: {
            Text("Cihazda yer olduğundan emin olup tekrar dene.")
        }
    }

    private func step(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: number).font(.headline).foregroundStyle(.tint)
            Text(text)
        }
    }

    private func setAside() {
        do {
            try KumbaraContainer.setAsideStore()
            didSetAside = true
        } catch {
            setAsideFailed = true
        }
    }
}
