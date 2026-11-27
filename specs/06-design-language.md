# 06 — Tasarım Dili

> Hedef: Bir bankacılık uygulamasının ciddiyeti, bir defterin sadeliği.
> "AI tarafından üretilmiş gibi" duran arayüzün tersini tanımlıyoruz.

## 1. Yasaklar (slop kontrol listesi)
PR'da bunlardan biri varsa reddedilir:
- Arka planda mor/mavi gradyan, "aurora" bulanıklıkları, dekoratif blob şekilleri.
- Her şeyi kartlara koymak; kart içinde kart; her kartta gölge.
- Emoji'yi ikon olarak kullanmak (💰📈). İkonlar yalnız SF Symbols, tek ağırlık.
- Anlamsız selamlama başlıkları ("Hoş geldin! 👋 Bugün harika bir gün").
- Her bölüm başlığına ikon koymak.
- Renkli kategori daireleri gökkuşağı. Kategori rengi en fazla 8 sakin tondan biri.
- Grafiklerde 3B, gölge, gradyan dolgu, animasyonlu sayaç ("0'dan sayarak artan rakam").
- "Pro tip", "✨ Yeni", rozet yağmuru; sahte boş durum illüstrasyonları.
- Gereksiz yuvarlaklık: köşe yarıçapı ≤ 10 pt (sistem kontrolleri hariç).
- Sistemin kendi materyali dışında cam (glass) efekti taklidi. iOS 26 Liquid Glass
  yalnız sistemin verdiği yerde (tab bar, toolbar) — içerikte değil.

## 2. İlkeler
1. **Rakam kahramandır.** Ekranın en büyük öğesi bir sayıdır. Rakamlar
   `.monospacedDigit()` ile hizalı; tutar sütunları sağa yaslı ve ondalık hizalı.
2. **Liste > kart.** Veri, iOS'ta `List` / sade bölümlü satırlar; macOS'ta `Table`.
   Ayırıcı çizgi, boşluk ve tipografi hiyerarşi kurar; kutular değil.
3. **Renk anlam taşır.** Nötr gri skala + tek vurgu rengi (koyu petrol yeşili,
   `#1F5E5B` açık / `#5FB3AC` koyu). Kâr / zarar için sistem yeşil/kırmızısının
   doygunluğu düşürülmüş tonları **ve** ▲/▼ işareti (REQ-X7). Uyarı = amber.
4. **Gerçek bilgi, ince yazı.** Kaynak, zaman damgası, kullanılan fiyat tipi
   küçük ikincil metinle her zaman görünür ("Bozdurma · Truncgil · 14:05").
5. **Yoğunluk saygısı.** iOS'ta satır yüksekliği 44 pt, ikincil bilgi aynı satırda.
   macOS'ta tablo yoğunluğu, klavye kısayolları (⌘N yeni işlem, ⌘F ara,
   ⌘⇧O fiş aç), kenar çubuğu, çoklu seçim, sağ tık menüsü.
6. **Hareket işlevseldir.** Animasyon yalnız durum değişimini anlatmak için
   (taslak → onaylandı). Fiyat değişiminde sayı yanıp sönmez; değişen hane kısa
   (0,3 sn) renk tonu alır, o kadar.
7. **Platforma yerli.** Sistem font (SF Pro / SF Mono rakamlar), sistem kontrolleri,
   sistem gezinme kalıpları. Özel tab bar, özel buton stilleri yok.

## 3. Tipografi ölçeği
| Rol | Stil |
|---|---|
| Kahraman sayı | `.largeTitle`, `.semibold`, monospacedDigit |
| Satır başlığı | `.body` |
| Satır tutarı | `.body`, monospacedDigit, sağa yaslı |
| İkincil | `.footnote`, `.secondary` |
| Bölüm başlığı | `.subheadline`, `.secondary`, büyük harf değil |

Tümü Dynamic Type ile ölçeklenir; XXL boyutta satırlar iki satıra kırılır,
sayı kesilmez.

## 4. Ana ekranlar (iOS) — tel kafes

**Özet**
```
┌──────────────────────────────┐
│ Kasım                    ⌄   │
│                              │
│ 18.420,50 ₺                  │  ← kalan (gelir − gider)
│ Gelir 62.000 · Gider 43.579  │
│ 4 gün kaldı · günlük 4.605 ₺ │
│──────────────────────────────│
│ Bütçeler                     │
│ Market      7.240 / 9.000  ▮▮▮▮▮▮▮▯▯ │
│ Ulaşım      2.110 / 2.500  ▮▮▮▮▮▮▮▮▯ │
│──────────────────────────────│
│ Son işlemler                 │
│ Migros       Market  −1.249,90│
│ Opet         Yakıt   −2.000,00│
│ Maaş         Gelir  +62.000,00│
└──────────────────────────────┘
 [Özet] [İşlemler] [ + ] [Birikim] [Ayarlar]
```

**Birikim**
```
┌──────────────────────────────┐
│ Birikim                      │
│ 412.870 ₺          ▲ %18,2   │
│ Bozdurma değeri · 14:05      │
│ USD'ye göre ▲ %4,1 · TÜFE ▼ %2,3│
│ ─────── grafik (1A 3A 1Y Tümü)│
│──────────────────────────────│
│ Gram altın    42,5 g          │
│   ort. 5.210  şimdi 5.925    ▲ 30.387 │
│ Çeyrek        8 adet          │
│   ort. 9.100  şimdi 9.969    ▲  6.952 │
│ USD           1.200           │
│   ort. 41,20  şimdi 50,77    ▲ 11.484 │
└──────────────────────────────┘
```

**Fiş onayı**: üst yarı görüntü (tespit edilen alanlar ince çerçeveli),
alt yarı form; düşük güvenli alan amber kenarlı ve odaklı.

## 5. macOS
`NavigationSplitView`: kenar çubuğu (Özet, İşlemler, Bütçeler, Birikim, Gelen
fişler, hesaplar listesi) · içerik `Table` · denetçi (inspector) panelinde
seçili kaydın detayı. Fişler pencereye sürüklenince "Gelen fişler"e düşer.

## 6. Uygulama ikonu
Tek renk zemin üzerinde geometrik, sade bir kumbara/yuva formu; metin yok,
gradyan yok. Tasarım M5'te ayrıca spesifiye edilecek.

## 7. Kabul
Her ekran için: açık + koyu tema ekran görüntüsü, Dynamic Type XXL, VoiceOver
etiket kontrolü ve §1 kontrol listesinin işaretlenmesi PR şablonunda zorunludur.
