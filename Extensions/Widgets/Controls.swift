#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

/// Denetim Merkezi, kilit ekranı ve Eylem Butonu kontrolleri (REQ-X8, specs/06 §6.2).
/// Uygulamayı ilgili ekranla açar; kayıt her zaman uygulamada, kullanıcının onayıyla yapılır (C5).
struct AddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alikvkli.kumbara.control.add") {
            ControlWidgetButton(action: OpenURLIntent(DeepLinkURL.add)) {
                Label("Harcama ekle", systemImage: "plus.circle")
            }
        }
        .displayName("Harcama ekle")
        .description("Kumbara'yı hızlı ekleme ile açar.")
    }
}

struct ScanReceiptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alikvkli.kumbara.control.scan") {
            ControlWidgetButton(action: OpenURLIntent(DeepLinkURL.scan)) {
                Label("Fiş tara", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Fiş tara")
        .description("Kumbara'yı kamerayla fiş taramaya açar.")
    }
}
#endif
