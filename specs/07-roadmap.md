# 07 — Yol Haritası ve Görevler

Her görev bir veya daha fazla `REQ-…` maddesine bağlıdır. Bir görev, kabul kriteri
test/senaryo ile kanıtlanınca "bitti" sayılır.

## M0 — İskelet (1 hafta)

`[x]` bitti · `[~]` yazıldı, macOS CI (Xcode) doğrulaması bekliyor

- [x] T0.1 Xcode projesi: multiplatform app, `Packages/` yerel paketleri, Swift 6.
- [x] T0.2 `KumbaraCore`: `Money`, `CurrencyCode`, `Quantity`, `AssetCode`,
      TR biçimlendirici + testler (C3, REQ-X6).
- [x] T0.3 CI: Linux'ta `swift test` (Core), macOS'ta `xcodebuild test`.
- [x] T0.4 PR şablonu: REQ referansı + 06 §9 yasak listesi + 06 §11 kabul listesi.
- [x] T0.5 Uygulama kabuğu: iOS `TabView` (arama sekmesi, küçülen tab bar, alt
      aksesuar yer tutucu), macOS `NavigationSplitView` + inspector + `Commands` (06 §6–7).

## M1 — Defter (2 hafta)
- [x] T1.1 SwiftData modelleri: Account, Category, Transaction (REQ-L1, L2, L3).
- [x] T1.2 Varsayılan Türkçe kategori seti (REQ-L5).
- [x] T1.3 Hızlı ekleme sayfası, 2 dokunuş kuralı + UI testi (REQ-L4).
- [x] T1.4 İşlem listesi (iOS `List`, macOS `Table`), arama, filtre.
- [x] T1.5 Satıcı → kategori öğrenme (REQ-L6).
- [x] T1.6 Özet ekranı (REQ-B3, B4).

## M2 — Piyasa ve Birikim (2 hafta)
- [x] T2.0 Canlı piyasa şeridi alt aksesuarı (inline/expanded) (REQ-X8).
- [x] T2.1 Sağlayıcı ayrıştırıcıları + fixture testleri: truncgil, goldapi, tcmb,
      frankfurter, coingecko (02 §1).
- [x] T2.2 Yedekleme zinciri, zaman aşımı, devre kesici, akla yatkınlık kontrolü
      (02 §3–4, AC-M1-1).
- [x] T2.3 Portföy matematiği: ortalama maliyet, FIFO, P&L + test vektörleri (03).
- [x] T2.4 Asset/Trade modelleri, alım/satım formu, fiyat ön doldurma (REQ-P1, P5, P6).
- [x] T2.5 Birikim ekranı, fiyat tipi seçimi, makas bilgisi (REQ-P3, P4).
- [x] T2.6 PriceSnapshot ve grafik (REQ-P8, 02 §6).
- [x] T2.7 Çevrimdışı ve bayatlık etiketleri (C4, 02 §5, AC-C4).

Not: Arka plan yenilemesi (REQ-M2'nin `BGAppRefreshTask` kısmı) fiyat alarmıyla
birlikte M4'e (T4.5) taşındı; ön planda 60 sn yenileme M2'de tamam.

## M3 — Yakalama (3 hafta) ✓
- [x] T3.1 Fiş korpusu toplama (≥ 40 OCR çıktısı, 04 §6). 51 gerçek Vision çıktısı: 49 üretilmiş + 2 Commons (CC BY-SA). Kullanıcı fişleri (`device`) eklenecek.
- [x] T3.2 Ayrıştırıcılar: tutar, tarih, satıcı, sınıflandırıcı (Core, testli). Korpus: tutar %100, tarih %98, satıcı %100.
- [x] T3.3 Vision OCR sarmalayıcı, belge kamerası, PhotosPicker, sürükle-bırak.
- [x] T3.4 Onay ekranı: görüntü üstünde kutular, güven vurgusu (REQ-C4).
- [x] T3.5 Banka listesi → çoklu taslak (REQ-C5), mükerrer kontrolü (REQ-C6).
- [x] T3.6 Share Extension + gelen kutusu (REQ-C2). iOS + macOS; uzantı OCR yapmaz, App Group `Inbox/`'a atomik yazar. Cihazda deneme Team ID ister (Q10).
- [x] T3.7 Foundation Models opsiyonel katmanı + çapraz kontrol (04 §2.5). Karar mantığı Core'da test edildi; modelin kendisi yalnız Apple Intelligence'lı cihazda çalışır (CI'da yok).

## M4 — Bütçe ve otomasyon (2 hafta) — ayrıntı: 08
- [x] T4.1 Bütçeler ve yerel bildirimler (REQ-B1, B2).
- [ ] T4.2 Tekrarlayan işlemler → taslak (REQ-L7).
- [ ] T4.3 Taksit planı, kart ekstre dönemi (REQ-L8, L9).
- ~~T4.4 App Intents / Kestirmeler (REQ-C7)~~ → v1.x (2026-11-27 kararı).
- [ ] T4.5 Fiyat alarmı (REQ-M4) ve arka plan fiyat yenilemesi (REQ-M2, BGAppRefreshTask).

## M5 — Yayın hazırlığı (2 hafta)
- [ ] T5.1 iCloud eşitleme açma/kapama (REQ-X2).
- [ ] T5.2 Kilit + bulanık önizleme (REQ-X3).
- [ ] T5.3 CSV/JSON dışa aktarma, CSV içe aktarma (REQ-X4).
- [ ] T5.4 Widget'lar (tüm rendering modları), Denetim Merkezi kontrolleri,
      macOS menü çubuğu öğesi (REQ-X5, X8, X9).
- [ ] T5.5 Reel getiri: USD + TÜFE tablosu (REQ-P7).
- [ ] T5.6 Hedefler (REQ-P9), gelirden birikime ayır (REQ-P10).
- [ ] T5.7 Erişilebilirlik denetimi, İngilizce yerelleştirme, Icon Composer
      ile çok katmanlı Liquid Glass ikonu (06 §8), mağaza metni.

## Sonrası (v1.x adayları)
Kestirmeler / App Intents (REQ-C7), canlı tarama (DataScanner), BIST/fon fiyatları (kaynak bulunursa), ortak bütçe
(CloudKit paylaşımı), Apple Watch hızlı ekleme, Vision Pro yok.
