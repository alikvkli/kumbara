import KumbaraCore
import SwiftUI

/// Ayarlar. iOS'ta sayfa, macOS'ta `Settings` sahnesi.
struct SettingsView: View {
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid
    @AppStorage(SettingsKey.costMethod) private var costMethod: CostMethod = .averageCost

    var body: some View {
        Form {
            Section {
                Picker("Değerleme fiyatı", selection: $priceKind) {
                    ForEach(PriceKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Maliyet yöntemi", selection: $costMethod) {
                    ForEach(CostMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Birikim")
            } footer: {
                Text("Bozdurma fiyatı, birikimini bugün satsan eline geçecek tutardır; en dürüst değer budur.")
            }
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
