# 06 — Tasarım Dili

> Hedef: Apple'ın güncel tasarım dili (**Liquid Glass**, iOS 27 / macOS 27
> "Golden Gate") ile tam uyumlu, sistemin bir parçası gibi hissettiren; rakamı
> ön plana koyan, sakin ve hızlı bir deneyim. "AI tarafından üretilmiş gibi"
> duran arayüzün tersi: özel süs yok, sistemin kendi malzemesi doğru yerde.

Referans platform: **iOS 27 / iPadOS 27 / macOS 27** SDK'sı (Xcode 27).
Minimum sürüm iOS 26 / macOS 26 (Liquid Glass'ın ilk sürümü); 27'deki
iyileştirmeler (camın içeriği daha iyi dağıtması, koyu kenar, kaydırma altında
düz araç çubuğu, tutarlı köşe yarıçapı) standart bileşen kullanan uygulamalara
**otomatik** uygulandığı için tek tasarım iki sürümde de doğru görünür. Bu yüzden
kural #1: **standart bileşen kullan, taklit etme.**

---

## 1. Temel model: içerik katmanı + cam katmanı

Liquid Glass'ın temel ilkesi, uygulamamızın da temel ilkesidir:

| Katman | Ne içerir | Malzeme |
|---|---|---|
| **İçerik** | Rakamlar, listeler, tablolar, grafikler, fiş görüntüsü | Opak, sistem arka planı (`.background`, grouped background). **Asla cam değil.** |
| **İşlev (cam)** | Gezinme ve kontroller: tab bar, araç çubukları, kenar çubuğu, sayfalar (sheet), yüzen eylem kontrolleri | Sistemin Liquid Glass'ı; özel bileşende `glassEffect` |

- Cam, içeriğin **üstünde yüzer**; içerik onun altından kayar. Cam üstüne cam
  konmaz (kontrol grupları `GlassEffectContainer` ile tek yüzey olur).
- Liste satırı, özet kartı, portföy satırı **cam değildir**. "Glassmorphism kart"
  bu projede yasaktır (§9).
- Kullanıcının Liquid Glass şeffaflık ayarına (iOS/macOS 27 Ayarlar'daki çubuk),
  *Şeffaflığı Azalt* ve *Karşıtlığı Artır* ayarlarına saygı: cam bileşenlerin
  arkasına sabit opak/yarı saydam katman eklenmez, opaklık elle ayarlanmaz;
  sistem karar verir.

## 2. Biçim: eşmerkezlilik (concentricity)

- Sabit köşe yarıçapı yazılmaz. Kapsayıcı içindeki şekiller
  `ConcentricRectangle()` / `.rect(corners: .concentric)` ile ebeveyninin
  köşesine eşmerkezli olur. Kapsül (`Capsule`) dokunma hedefi olan kontroller için.
- macOS 27'de pencere köşe yarıçapı sistemce tutarlı hale getirildi; özel pencere
  kromu, özel başlık çubuğu yapılmaz.
- Liste/tablo içerikleri sistem `List` / `Table` stillerini kullanır (inset grouped
  iOS'ta, sidebar/inset macOS'ta).

## 3. Renk

- **Nötr içerik + tek vurgu (tint).** Vurgu: derin petrol yeşili — açık `#1F5E5B`,
  koyu `#5FB3AC`; Asset Catalog'da `AccentColor` olarak, *Karşıtlığı Artır* için
  yüksek karşıtlık varyantıyla.
- Tint yalnız **birincil eylemde** (ör. "Kaydet", `.glassProminent`) ve seçili
  durumda. Tüm butonları renklendirmek camın hiyerarşisini bozar.
- Tek vurgu tonu. `.glassProminent` buton yazısının rengini sistem zemine göre
  seçer: koyu modda açık vurgu (`#5FB3AC`) üstünde **siyah** yazı (8.5:1), açık
  modda koyu vurgu (`#1F5E5B`) üstünde beyaz (7.6:1) — ekran görüntüsünden ölçüldü.
  Butona elle tint/yazı rengi verilmez. Birincil buton her yerde
  `.primaryActionStyle()` ile çizilir.
- Kâr/zarar: sistem `green`/`red` (koyu/yüksek karşıtlık varyantları otomatik) +
  her zaman işaret (▲/▼ veya +/−). Renk tek başına anlam taşımaz (REQ-X7).
- Kategori renkleri: sistem paletinden en fazla 8 ton, yalnız küçük SF Symbol
  rozetinde ve grafikte; satır arka planında değil.
- Koyu mod ve açık mod eşit önemde; tüm renkler semantik (`.primary`,
  `.secondary`, `.tertiary`, `Color(.systemGroupedBackground)`).

## 4. Tipografi ve rakamlar

- Sistem fontu (SF Pro); rakamlarda `.monospacedDigit()`. Özel font yok.
- iOS 26+ büyük, sola yaslı başlıklar (`.navigationTitle` + `.large`) kullanılır.
- **Kahraman sayı** ekranın en büyük öğesi: `.largeTitle.weight(.semibold)`,
  ondalık kısmı `.secondary` ve bir boy küçük (`₺18.420`**`,50`**).
- Tutar sütunları sağa yaslı, ondalık hizalı; para birimi sembolü yerel ayara göre.
- Canlı fiyat değiştiğinde yalnız `.contentTransition(.numericText(value:))`
  — sistemin rakam geçişi. Sayaç animasyonu, yanıp sönme, renk patlaması yok.
- Dynamic Type her boyutta; AX boyutlarında satırlar dikey yığına geçer
  (`ViewThatFits` / `dynamicTypeSize` ile), sayı asla `…` ile kesilmez.

| Rol | Stil |
|---|---|
| Kahraman sayı | `.largeTitle`, semibold, monospacedDigit |
| Satır başlığı | `.body` |
| Satır tutarı | `.body`, monospacedDigit, sağa yaslı |
| İkincil (fiyat tipi, tazelik) | `.footnote`, `.secondary` |
| Bölüm başlığı | sistem `Section` başlığı |

## 5. İkonografi ve hareket

- Yalnız **SF Symbols 7**, sistem rendering modları (hiyerarşik; kategori
  rozetinde palet). Emoji ikon yok.
- Sembol animasyonları anlam taşıdığında: kayıt onaylandığında bir kez
  `checkmark` için `.symbolEffect(.drawOn)`; yenileme sırasında `.rotate`
  yalnız aktifken. Dekoratif sürekli animasyon yok.
- Geçişler sistemin: bir araç çubuğu butonundan açılan sayfa
  `matchedTransitionSource` + `.navigationTransition(.zoom(...))` ile **butondan
  morph** eder (Liquid Glass'ın imza hareketi). Cam kontrol grupları arasında
  durum değişimi `glassEffectID` + `@Namespace` ile morph eder.
- Dokunsal geri bildirim: `.sensoryFeedback(.success, trigger:)` kayıtta,
  `.selection` segment değişiminde. Başka yerde yok.
- *Hareketi Azalt* açıksa zoom/morph geçişleri çapraz geçişe düşer (sistem
  davranışı; özel animasyon ekleyip bunu bozmayız).

## 6. iOS / iPadOS bileşen haritası

### 6.1 Gezinme
```swift
TabView {
    Tab("Özet", systemImage: "square.text.square") { SummaryView() }
    Tab("İşlemler", systemImage: "list.bullet.rectangle") { LedgerView() }
    Tab("Birikim", systemImage: "chart.line.uptrend.xyaxis") { PortfolioView() }
    Tab("Bütçe", systemImage: "chart.pie") { BudgetView() }
    Tab(role: .search) { SearchView() }          // ayrık arama sekmesi
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory { MarketTickerAccessory() }
.tabViewStyle(.sidebarAdaptable)                 // iPad: kenar çubuğuna dönüşür
```
- **Ortada "+" sekmesi yok** (sekme gezinme içindir, eylem değil).
- **Alt aksesuar = canlı piyasa şeridi:** `Gram 5.925 ▲%1,9 · USD 50,79 · 14:05`.
  `tabViewBottomAccessoryPlacement` `.inline` iken (tab bar küçülmüş) yalnız
  gram altın; `.expanded` iken 2–3 fiyat. Dokununca piyasa sayfası açılır.
  Kullanıcı Ayarlar'dan hangi fiyatların görüneceğini seçer veya kapatır.

### 6.2 Hızlı ekleme (REQ-L4: ≤ 2 dokunuş)
- Her sekmenin araç çubuğunda sağda `+` (`ToolbarItem(placement: .primaryAction)`)
  ve yanında fiş tarama `doc.viewfinder`; ikisi `ToolbarItemGroup` içinde tek cam
  kapsülde. 1. dokunuş → sayfa butondan morph ederek açılır, tutar alanı odaklı.
- Sayfa: `.presentationDetents([.medium, .large])`; `.medium`'da tutar + kategori
  + kaydet sığar. iOS 26+ yarı yükseklik sayfa sistem camıyla gelir; arka plan
  rengi verilmez.
- Kilit ekranı / Denetim Merkezi / Eylem Butonu: `ControlWidget` ile
  "Harcama ekle" ve "Fiş tara" kontrolleri (App Intent tabanlı, REQ-C7).

### 6.3 Kaydırma kenarları
- Uzun listelerde sistem kaydırma kenar efekti (`.scrollEdgeEffectStyle(.soft, for: .top)`);
  iOS 27'nin kaydırma altında düz araç çubuğu davranışı standart toolbar ile
  otomatik gelir — üstüne özel blur/gradyan eklenmez.
- Kahraman bölgenin arkasında hiçbir zaman görsel/gradyan yoktur; içerik sade
  zemin üzerindedir, cam altından kayan şey gerçek içeriktir.

### 6.4 Butonlar
| Durum | Stil |
|---|---|
| Sayfadaki birincil eylem (Kaydet, Onayla) | `.buttonStyle(.glassProminent)` + tint |
| Yüzen ikincil kontroller (kamera, OCR araçları) | `.buttonStyle(.glass)` |
| Liste/form içi eylemler | sistem varsayılanı (borderless / bordered) |
| Yıkıcı (Sil) | `role: .destructive`, onay `confirmationDialog` |

### 6.5 Özel cam kullanımı (yalnız bu üç yer)
1. **Fiş onay ekranı**: fiş görüntüsü tam ekran içerik; altta yüzen
   `GlassEffectContainer` içinde tespit edilen alan kapsülleri
   (`Tutar 1.249,90` · `Tarih 27.11` · `Migros`) + Onayla. Bir kapsüle dokununca
   düzenleme alanına `glassEffectID` ile morph eder.
2. **Kamera tarama kontrolleri**: deklanşör, flaş, galeri — `.glass` interactive.
3. **Grafik kazıyıcı (scrub) etiketi**: grafiğe basılı tutunca üstte yüzen değer
   etiketi `glassEffect(.regular, in: .capsule)`.

## 7. macOS 27 bileşen haritası

- **Pencere:** `NavigationSplitView` — kenar çubuğu pencere kenarına kadar uzanır
  (macOS 27 varsayılanı); içerik sütunu `Table`; sağda `.inspector` ile seçili
  kaydın detayı. Kenar çubuğu ikonları sistem rengiyle (macOS 27'de renkli kenar
  çubuğu ikonları geri geldi) — kategori rengi değil, sistem.
- **Kenar çubuğu:** Özet · İşlemler · Bütçeler · Birikim · Gelen fişler (rozet
  sayısıyla) — ayrıca "Hesaplar" bölümü.
- **Araç çubuğu:** macOS 27'nin birleşik araç çubuğu; gruplar `ToolbarSpacer`
  ile ayrılır: [Yeni işlem | Fiş içe aktar] — boşluk — [Dönem seçici] —
  `.searchable` araç çubuğunda. Özel araç çubuğu arka planı yok.
- **İçerik genişlemesi:** Birikim grafiği ve fiş görüntüsü kenar çubuğunun
  altına `.backgroundExtensionEffect()` ile uzar.
- **Menüler ve klavye:** tüm eylemler `Commands` ile menü çubuğunda; macOS 27'nin
  menü öğesi ikon API'si ile ana eylemlere ikon (API adı Xcode 27 SDK'sından
  doğrulanacak). Kısayollar: ⌘N yeni işlem, ⌘⇧N yeni alım/satım, ⌘O fiş aç,
  ⌘F ara, ⌘1–4 bölümler, ⌫ sil (onaylı), Space Quick Look ile fiş önizleme.
- **Menü çubuğu öğesi:** `MenuBarExtra` (opsiyonel): gram altın / USD ve portföy
  toplamı; içinden "Harcama ekle". `[Ö]`
- **Ayarlar:** `Settings` sahnesi, sekmeli sistem ayar penceresi.
- **Sürükle-bırak:** pencereye görüntü/PDF bırakınca "Gelen fişler"e düşer;
  `Table` satırları CSV olarak dışarı sürüklenebilir.

## 8. Widget'lar, ikon, sistem yüzeyleri

- **Uygulama ikonu:** Icon Composer ile **çok katmanlı Liquid Glass ikonu**
  (iOS/macOS 27): arka plan katmanı düz petrol yeşili; ön katmanda geometrik
  kumbara formu, yuva kesiğinde seçici kırılma (refraction). Açık, koyu, şeffaf
  (clear) ve renklendirilmiş (tinted) varyantlar Icon Composer önizlemesinde
  kontrol edilir. Metin, gradyan, emoji yok.
- **Widget'lar (REQ-X5):** `widgetRenderingMode` desteği — tam renk, vurgulu
  (accented) ve şeffaf modlarda okunur kalmalı; vurgulanacak öğeler
  `.widgetAccentable()`. Boyutlar: küçük (gram altın), orta (portföy + günlük
  değişim), kilit ekranı dairesel/satır içi (bu ay harcama / bütçe), StandBy.
- **Denetim Merkezi kontrolleri:** §6.2.

## 9. Yasaklar (slop kontrol listesi)
PR'da biri varsa reddedilir:
- İçerik öğelerinde cam: "glassmorphism kart", cam liste satırı, cam özet kutusu.
- Cam üstüne cam; `GlassEffectContainer` dışında yan yana birden fazla
  `glassEffect`.
- Özel tab bar, özel navigation bar, özel pencere kromu; sistemin kaydırma
  kenarı yerine elle blur/gradyan.
- Dekoratif gradyan, aurora/blob arka plan, kahraman bölgenin arkasında görsel.
- Kart içinde kart; gölgeli kart yığınları. Tek satırlı bölümlerden oluşan inset
  grouped liste de kart yığınıdır: gün gruplu listeler `.plain` + yapışkan başlık.
- Emoji ikon; her bölüm başlığına ikon.
- Sabit köşe yarıçapı (`cornerRadius(12)` vb.) — eşmerkezli şekil kullan.
- Her butonu tint'lemek; birden fazla `.glassProminent` aynı ekranda.
- Sayaç animasyonu, yanıp sönen fiyat, konfeti, "✨ Yeni" rozetleri,
  selamlama başlıkları ("Hoş geldin 👋"), boş durum illüstrasyonları
  (boş durum = `ContentUnavailableView` + tek eylem).
- Şeffaflık/karşıtlık ayarını yok sayan elle opaklık.

## 10. Ekranlar — tel kafes (iOS)

**Özet**
```
┌──────────────────────────────────┐
│ Özet                 ( + ⌕fiş )  │ ← cam kapsül araç grubu
│ Kasım ⌄                          │
│                                  │
│ ₺18.420,50                       │ ← kahraman sayı, içerik katmanı
│ Gelir 62.000 · Gider 43.579,50   │
│ 4 gün kaldı · günlük 4.605 ₺     │
│                                  │
│ BÜTÇELER                         │ ← sistem Section, inset grouped
│ Market      7.240 / 9.000   %80  │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━──── │ ← sistem ProgressView/Gauge
│ Ulaşım      2.110 / 2.500   %84  │
│                                  │
│ SON İŞLEMLER                     │
│ (cart) Migros   Market  −1.249,90 │ ← (…) = SF Symbol adı
│ (fuel) Opet     Yakıt   −2.000,00 │
│ (in)   Maaş     Gelir  +62.000,00 │
│                                  │
│ ╭──────────────────────────────╮ │
│ │ Gram 5.925 ▲%1,9 · USD 50,79 │ │ ← tabViewBottomAccessory (cam)
│ ╰──────────────────────────────╯ │
│ ╭──────────────────────────╮ ╭─╮ │
│ │ Özet İşlem Birikim Bütçe │ │⌕│ │ ← sistem tab bar + arama sekmesi
│ ╰──────────────────────────╯ ╰─╯ │
└──────────────────────────────────┘
```

**Birikim**
```
┌──────────────────────────────────┐
│ Birikim                  ( + )   │
│ ₺412.870                ▲ %18,2  │
│ Bozdurma · 5 dk önce             │
│ USD'ye göre ▲ %4,1 · TÜFE ▼ %2,3 │
│ [1A][3A][1Y][Tümü]               │ ← segmented Picker
│ ╱╲__╱‾‾╲_╱‾‾‾ (Swift Charts)      │
│                                  │
│ Gram altın   42,5 g     ▲ 30.387 │
│   ort. 5.210 · şimdi 5.925       │
│ Çeyrek       8 adet     ▲  6.952 │
│   ort. 9.100 · şimdi 9.969       │
│ USD          1.200      ▲ 11.484 │
│   ort. 41,20 · şimdi 50,77       │
└──────────────────────────────────┘
```

**Fiş onayı**
```
┌──────────────────────────────────┐
│ ✕                        Fiş     │
│ ┌──────────────────────────────┐ │
│ │  MİGROS TİC. A.Ş.  ┌───────┐ │ │ ← görüntü (içerik), tespit edilen
│ │  ...               │Migros │ │ │   alanlar ince tint çerçeveyle
│ │  TOPLAM  ┌───────────────┐  │ │
│ │          │ *1.249,90     │  │ │
│ │          └───────────────┘  │ │
│ └──────────────────────────────┘ │
│ ╭────────────────────────────────╮│
│ │(₺1.249,90)(27 Kas)(Migros)    ││ ← GlassEffectContainer kapsülleri
│ │(Market ⌄)         [ Onayla ]   ││   düşük güven = amber kenar
│ ╰────────────────────────────────╯│
└──────────────────────────────────┘
```

## 11. Kabul (her ekran için PR şablonunda zorunlu)
- [ ] iOS 27 ve iOS 26 simülatöründe ekran görüntüsü (açık + koyu).
- [ ] Liquid Glass şeffaflık çubuğu iki uçta (en şeffaf / tam renkli) okunabilir.
- [ ] *Şeffaflığı Azalt*, *Karşıtlığı Artır*, *Hareketi Azalt* açıkken kontrol.
- [ ] Dynamic Type XXL ve AX3; VoiceOver etiketleri ve rotor.
- [ ] macOS: pencere en dar ve en geniş boyutta; klavyeyle tüm akış.
- [ ] §9 kontrol listesi tek tek işaretlendi.

## 12. Doğrulanacaklar (SDK açılınca)
Bu spec WWDC25/WWDC26 açıklamalarına dayanır. Xcode 27 SDK'sında şunlar
doğrulanıp gerekirse spec güncellenecek: macOS 27 menü ikonu API adı,
`ConcentricRectangle` imzası, `tabViewBottomAccessory` placement davranışı,
iOS 27 kaydırma kenarı varsayılanları, Icon Composer kırılma ek açıklamaları.

## 11. Metin dili (CX, 2026-11-27 gözden geçirmesi)
- **Ses:** Kullanıcıya "sen" diye, sıcak ama kısa. Uygulama kendinden "ben" diye söz etmez
  ("hatırlatırım" değil "hatırlatma gelir"; "okudum" değil "okundu").
- **Bakış açısı her yerde kullanıcınınki:** "Bozdurma" = kuyumcuya/bankaya satınca eline geçen,
  "Satın alma" = alırken ödediğin. Kuyumcu tabelasındaki "Alış/Satış" (dükkânın bakışı) kullanılmaz;
  kayıtlarda "Aldım/Sattım", listede "Alım/Satım".
- **Jargon yok:** "mükerrer" → "daha önce kaydedilmiş olabilir"; "serbest varlık" → "diğer varlık";
  dosya biçimi (CSV) yalnız parantezde, eylemin adı önce ("İşlemleri tabloya aktar (CSV)").
- **Dürüst ve somut:** Tahmini fiyat, gecikme, eksik veri her zaman yazılır, nedeniyle birlikte
  ("Tahmini fiyat: ons altın ve dolar kurundan hesaplandı"). Söz verilemeyen şey vaat edilmez
  ("anlık değildir").
- **Eylem söyleyen hata:** Ne oldu + ne yapabilirsin ("Görüntüde toplam tutar bulunamadı. İşlemi elle
  ekleyebilirsin."). Teknik ayrıntı ve hata kodu gösterilmez.
- **Türkçe ekler:** Değişken sayı/ad sonrasına ek getirilmez (%80'i / %40'ı sorunu); cümle eki
  gerektirmeyecek biçimde kurulur ("Market bütçesi: %80 kullanıldı").
- **Belirsiz kelime yok:** Aynı yerde iki anlama gelen sözcük kullanılmaz ("Kur" düğmesi → "Alarmı kur",
  çünkü "kur" döviz kuru da demek).
- Geliştirici araçları (OCR çıktısı paylaşma) yalnız DEBUG derlemesinde.
