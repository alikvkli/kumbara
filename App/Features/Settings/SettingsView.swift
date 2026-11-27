import SwiftUI

/// Ayarlar. iOS'ta sayfa, macOS'ta `Settings` sahnesi. İçerik M5'te gelir.
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Veri kaynakları") {
                LabeledContent("Altın ve döviz", value: "Truncgil Finans")
                LabeledContent("Ons fiyatı", value: "gold-api.com")
                LabeledContent("Resmî kur", value: "TCMB")
                LabeledContent("Kripto", value: "CoinGecko")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}
