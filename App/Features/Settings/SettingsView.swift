import SwiftUI

/// Ayarlar. iOS'ta sayfa, macOS'ta `Settings` sahnesi.
struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AccountsView()
                } label: {
                    Label("Hesaplar", systemImage: "building.columns")
                }
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Kategoriler", systemImage: "square.grid.2x2")
                }
            }
            Section("Veri kaynakları") {
                LabeledContent("Altın ve döviz", value: "Truncgil Finans")
                LabeledContent("Ons fiyatı", value: "gold-api.com")
                LabeledContent("Resmî kur", value: "TCMB")
                LabeledContent("Kripto", value: "CoinGecko")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
    }
}
