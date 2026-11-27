import Foundation
import KumbaraData
import SwiftUI

/// iCloud eşitleme ayarı (REQ-X2, specs/09 §1). Varsayılan kapalı. Kod her derlemede vardır ama
/// eşitleme yalnız `ICLOUD` derleme bayrağıyla (iCloud yetkisi + Team ID ile imzalı derleme) açılabilir;
/// bayraksız derlemede ayar görünmez ve depo her zaman yalnız cihazdadır.
enum ICloudSync {
    static let enabledKey = "sync.iCloud"

    /// Bu derlemede iCloud kullanılabilir mi (yetki ile imzalandı mı).
    static var isAvailableInBuild: Bool {
        #if ICLOUD
        true
        #else
        false
        #endif
    }

    static var isEnabled: Bool { isAvailableInBuild && UserDefaults.standard.bool(forKey: enabledKey) }

    /// Cihazda bir iCloud hesabı açık mı. `ubiquityIdentityToken` yetki gerektirmeden güvenle okunur.
    static var hasAccount: Bool { FileManager.default.ubiquityIdentityToken != nil }
}

/// Ayarlar › iCloud.
struct ICloudSettingsView: View {
    @AppStorage(ICloudSync.enabledKey) private var enabled = false
    /// Açılışta geçerli olan durum; ayar değişince "yeniden aç" notu için.
    @State private var activeAtLaunch = ICloudSync.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("iCloud ile eşitle", isOn: $enabled)
                    .disabled(!ICloudSync.hasAccount && !enabled)
                LabeledContent("Durum") { status }
            } footer: {
                Text("Verilerin Apple hesabındaki özel iCloud alanına şifreli gider ve diğer cihazlarınla eşitlenir. Kumbara'nın sunucusu yok; biz göremeyiz.")
            }
            if enabled != activeAtLaunch {
                Section {
                    Label("Değişiklik Kumbara'yı kapatıp açınca geçerli olur.", systemImage: "arrow.clockwise")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Text("Eşitlemeyi kapatınca bu cihazdaki veri kalır; iCloud'daki kopya silinmez. Silmek için: Ayarlar › Apple Hesabı › iCloud › Depolamayı Yönet › Kumbara.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud")
    }

    @ViewBuilder
    private var status: some View {
        if !ICloudSync.hasAccount {
            Text("Bu cihazda iCloud hesabı yok").foregroundStyle(.orange)
        } else if activeAtLaunch {
            Text("Açık · arka planda eşitlenir")
        } else {
            Text("Kapalı · yalnız bu cihazda")
        }
    }
}
