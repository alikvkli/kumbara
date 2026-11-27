import KumbaraCapture
import KumbaraCore
import SwiftUI

/// Ayarlar. iOS'ta sayfa, macOS'ta `Settings` sahnesi.
struct SettingsView: View {
    #if os(macOS)
    @AppStorage("menubar.enabled") private var showsMenuBar = true
    #endif
    @AppStorage(SettingsKey.priceKind) private var priceKind: PriceKind = .bid
    @AppStorage(SettingsKey.costMethod) private var costMethod: CostMethod = .averageCost
    @AppStorage(SettingsKey.smartCheck) private var smartCheck = true

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
                Toggle("Akıllı kontrol", isOn: $smartCheck)
                    .disabled(!SmartReader.isAvailable)
            } header: {
                Text("Fiş okuma")
            } footer: {
                if SmartReader.isAvailable {
                    Text("Fişler, kurallara ek olarak Apple Intelligence ile cihazında bir kez daha okunur; iki sonuç uyuşmazsa uyarırım. Fiş cihazından çıkmaz.")
                } else {
                    Text("Bu cihazda Apple Intelligence kullanılamıyor; fişler yalnızca kurallarla okunur.")
                }
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
                NavigationLink {
                    RecurringRulesView()
                } label: {
                    Label("Tekrarlayan işlemler", systemImage: "repeat")
                }
                NavigationLink {
                    PriceAlertsView()
                } label: {
                    Label("Fiyat alarmları", systemImage: "bell")
                }
            }
            Section {
                if ICloudSync.isAvailableInBuild {
                    NavigationLink {
                        ICloudSettingsView()
                    } label: {
                        Label("iCloud", systemImage: "icloud")
                    }
                }
                NavigationLink {
                    LockSettingsView()
                } label: {
                    Label("Kilit", systemImage: "lock")
                }
                NavigationLink {
                    DataExchangeView()
                } label: {
                    Label("Dışa aktar ve yedekle", systemImage: "arrow.up.arrow.down.square")
                }
            }
            #if os(macOS)
            Section {
                Toggle("Menü çubuğunda göster", isOn: $showsMenuBar)
            } footer: {
                Text("Gram altın fiyatı menü çubuğunda; tıklayınca fiyatlar ve hızlı ekleme.")
            }
            #endif
            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("Hakkında", systemImage: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
    }
}

/// Sürüm, gizlilik ve veri kaynakları. Kaynak adları yalnız burada, atıf için yer alır;
/// ana arayüzde fiyatın tazeliği gösterilir (REQ-M3).
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Sürüm", value: version)
            } footer: {
                // TODO(Q10): iCloud eşitleme açılınca "ve kendi iCloud hesabında" eklenecek.
                Text("Kumbara'nın sunucusu yok. Kayıtların yalnızca cihazında durur; fiş görüntüleri de cihazında okunur.")
            }
            Section {
                LabeledContent("Altın ve döviz", value: "Truncgil Finans")
                LabeledContent("Ons fiyatı", value: "gold-api.com")
                LabeledContent("Resmî kur", value: "TCMB")
                LabeledContent("Yedek kur", value: "Frankfurter (ECB)")
                LabeledContent("Kripto", value: "CoinGecko")
            } header: {
                Text("Veri kaynakları")
            } footer: {
                Text("Fiyatlar ücretsiz, herkese açık kaynaklardan alınır ve bilgi amaçlıdır; kuyumcu ve banka fiyatları farklı olabilir.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hakkında")
    }
}
