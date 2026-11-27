# 05 — Mimari

## 1. Platform kararları
| Karar | Seçim | Gerekçe |
|---|---|---|
| UI | SwiftUI, tek multiplatform target, Xcode 27 SDK, min iOS/macOS 26 | Liquid Glass standart bileşenlerle otomatik (06); platforma özgü düzen `#if os` yerine ayrı `View` dosyalarıyla |
| Sistem yüzeyleri | WidgetKit (`ControlWidget` dahil), App Intents, `MenuBarExtra` | REQ-X5, X8, X9 |
| Kalıcılık | SwiftData | CloudKit private DB ile yerleşik eşitleme (REQ-X2), backend yok (C1) |
| Eşzamanlılık | Swift 6 strict concurrency | Fiyat sağlayıcıları `actor` / `Sendable` |
| OCR | Vision + VisionKit | Cihaz üstü, Türkçe destekli |
| Akıllı ayrıştırma | Foundation Models (opsiyonel) | Cihaz üstü LLM; yoksa kural tabanlı |
| Grafik | Swift Charts | Yerel, erişilebilir |
| Widget | WidgetKit + App Group | Paylaşılan SwiftData store okuma |
| Bağımlılık | **Sıfır** üçüncü parti paket | C2, bakım yükü |

## 2. Modüller
```
Kumbara.xcodeproj
├── App/                    SwiftUI uygulaması (iOS + macOS)
│   ├── Features/Ledger, Budget, Portfolio, Capture, Settings
│   └── Platform/iOS, macOS          ← platforma özgü düzenler
├── Extensions/
│   ├── ShareExtension/              REQ-C2
│   └── Widgets/                     REQ-X5
└── Packages/
    ├── KumbaraCore/        Saf Swift, Foundation dışında bağımlılık yok, Linux'ta test edilir
    │   ├── Money/          Money, CurrencyCode, Quantity, AssetCode, biçimlendirme
    │   ├── Portfolio/      Ortalama maliyet, FIFO, P&L, reel getiri (03)
    │   ├── Market/         Quote, sağlayıcı yanıt ayrıştırıcıları, yedekleme zinciri mantığı
    │   ├── Capture/        TextLine → DraftTransaction ayrıştırıcıları (04 §2.3)
    │   └── Budget/         Bütçe, tekrarlama kuralları, taksit planı
    ├── KumbaraData/        SwiftData @Model'ler, CloudKit, Core ↔ Model eşleme
    ├── KumbaraMarket/      URLSession ağ katmanı, zamanlayıcı, devre kesici, BGTask
    └── KumbaraCapture/     Vision/VisionKit/PDFKit sarmalayıcıları → [TextLine]
```
Bağımlılık yönü: `App → Data/Market/Capture → Core`. `Core` hiçbir şeye bağlı değildir.

## 3. Veri modeli (SwiftData)
CloudKit kısıtları gereği: tüm ilişkiler opsiyonel, `@Attribute(.unique)` yok,
varsayılan değerler tanımlı. `Decimal` alanlar CloudKit uyumu için
`String` (kanonik `"1234.56"`) olarak saklanır ve hesaplanmış özellikle açılır.

```
Account        id, name, kind(cash|bank|card|savings), currency, openingBalance,
               statementDay?, archived, sortIndex
Category       id, name, parent?, kind(income|expense), symbol(SF Symbol), color token
Transaction    id, date, amount, currency, direction(in|out|transfer), account,
               toAccount?, category?, merchant?, note, attachment?, status(draft|posted),
               origin(manual|ocr|recurring|import|intent), recurrence?, installment?
RecurrenceRule id, template fields, cadence(daily|weekly|monthly|yearly), interval,
               dayOfMonth?, nextDue, endDate?
Installment    id, total, count, index, groupID
Budget         id, category, monthlyLimit, currency, startMonth
Asset          id, code(AssetCode), displayName, unit(gram|piece|unit), manualPrice?
Trade          id, asset, side(buy|sell), quantity, unitPrice, fee, date,
               fxUSDTRYAtTrade, paidFrom(Account)?, note
PriceSnapshot  asset, day, bid, ask, mid, source, asOf     (02 §6)
Goal           id, name, target(Money | Quantity of asset), deadline?, linkedAssets
MerchantRule   normalizedMerchant, category, lastUsed      (REQ-L6)
```
Fiş görüntüsü: `@Attribute(.externalStorage) Data`.

## 4. Durum ve akış
- Her feature için `@Observable` bir model; view'lar SwiftData `@Query` ile okur,
  yazma işlemleri feature modelindeki fonksiyonlardan geçer (doğrulama Core'da).
- `MarketService` (actor): yedekleme zinciri, önbellek, yayınlama
  (`AsyncStream<[Quote]>`). UI son fiyatları `@Observable PriceBoard`'dan okur.
- Share Extension görüntüyü App Group'taki `Inbox/` klasörüne yazar; uygulama
  açılınca işler ve taslak oluşturur (extension'da ağır OCR yapılmaz — bellek sınırı).

## 5. Güvenlik
- SwiftData store dosyası `FileProtectionType.complete`.
- `LocalAuthentication` ile kilit; `scenePhase == .background` → bulanık kaplama.
- Ağ istekleri yalnız 02'deki alan adlarına (ATS varsayılan, HTTPS).

## 6. Test stratejisi
| Katman | Araç | Kapsam |
|---|---|---|
| Core | XCTest / Swift Testing, Linux CI'da da | Para, portföy, ayrıştırıcılar, fixture tabanlı |
| Market | URLProtocol stub | Yedekleme, zaman aşımı, devre kesici |
| Data | In-memory ModelContainer | Eşleme, göç |
| UI | XCUITest (kritik akışlar) | REQ-L4 (2 dokunuş), OCR onay akışı |
| Görsel | Snapshot (Xcode önizleme ekran görüntüsü) | Açık/koyu, Dynamic Type XXL |

CI: GitHub Actions — `KumbaraCore` için `ubuntu` + `swift test`; uygulama için
`macos` runner + `xcodebuild test`.
