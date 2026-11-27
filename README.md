# Kumbara

iOS ve macOS için, sunucusu olmayan kişisel finans uygulaması: gelir–gider takibi,
birikim/yatırım portföyü (gram altın, döviz, kripto…) ve fiş/ekran görüntüsünden
otomatik harcama kaydı.

Proje **spec-driven** geliştirilir: önce `specs/` altındaki dokümanlar yazılır ve
onaylanır, kod her zaman bir spec maddesine (`REQ-…`) referans verir.

| Doküman | İçerik |
|---|---|
| [00-constitution](specs/00-constitution.md) | Değişmez ilkeler |
| [01-product](specs/01-product.md) | Kapsam, kullanıcı hikâyeleri, kabul kriterleri |
| [02-market-data](specs/02-market-data.md) | Ücretsiz piyasa verisi kaynakları, yedekleme zinciri |
| [03-portfolio-math](specs/03-portfolio-math.md) | Maliyet, kâr/zarar, reel getiri formülleri |
| [04-capture-ocr](specs/04-capture-ocr.md) | Kamera / ekran görüntüsü / OCR ile harcama yakalama |
| [05-architecture](specs/05-architecture.md) | Modüller, veri modeli, platform kararları |
| [06-design-language](specs/06-design-language.md) | Arayüz dili — "AI slop" olmayan tasarım kuralları |
| [07-roadmap](specs/07-roadmap.md) | Kilometre taşları ve görev listesi |
| [open-questions](specs/open-questions.md) | Karar bekleyen sorular |

## Geliştirme

Gereksinimler: Xcode 27 (iOS 27 / macOS 27 SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(yalnız proje üretimi için; uygulamaya bağımlılık olarak girmez).

```sh
brew install xcodegen
xcodegen generate          # project.yml → Kumbara.xcodeproj
open Kumbara.xcodeproj
```

Çekirdek iş kuralları (`Packages/KumbaraCore`) Xcode olmadan da test edilir (macOS veya Linux):

```sh
swift test --package-path Packages/KumbaraCore
```

### iCloud eşitlemeyi açma (Team ID gelince)

Eşitleme kodu hazırdır ama varsayılan derlemede kapalıdır: iCloud yetkisi Apple Developer hesabıyla
imzalama ister (specs/09 §1, Q10). Açmak için `project.yml`'de üç satır:

1. `settings.base.DEVELOPMENT_TEAM`: Team ID'n (ör. `"AB12CD34EF"`).
2. `targets.Kumbara.entitlements.path`: `Config/Kumbara-iCloud.entitlements` (App Group + CloudKit
   kapsayıcısı `iCloud.com.alikvkli.kumbara` + push). `properties:` bloğunu sil; dosya olduğu gibi kullanılır.
3. `targets.Kumbara.settings.base` altına: `SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ICLOUD"`.

Sonra `xcodegen generate`, Xcode'da Signing & Capabilities'te kapsayıcının oluştuğunu kontrol et ve
uygulamayı cihazda çalıştır: Ayarlar › iCloud görünür. Mağazaya göndermeden önce entitlements'taki
`aps-environment` değerini `production` yap. Bayrak olmadan derlenen sürümde ayar görünmez, veri yalnız cihazdadır.

Yapı:

```
App/                  SwiftUI uygulaması (tek multiplatform target)
  Features/           Bölümler (Özet, İşlemler, Birikim, Bütçe, Arama, Hızlı ekleme, Ayarlar)
  Platform/iOS        TabView, alt aksesuar, araç çubuğu (specs/06 §6)
  Platform/macOS      NavigationSplitView, denetçi, menü komutları (specs/06 §7)
Packages/KumbaraCore  Saf Swift: Money, CurrencyCode, AssetCode, Quantity, AmountParser, biçimlendirme
specs/                Spesifikasyonlar — önce burası değişir
```
