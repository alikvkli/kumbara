# 03 — Portföy Matematiği

Tüm hesaplar `Decimal`, tam hassasiyet (C3). Gösterimde TL 2 hane, gram 3 hane,
kripto 8 haneye yuvarlanır.

## 1. Tanımlar
Bir pozisyon = tek bir varlığa ait, tarih sırasına dizilmiş işlemler listesi:
`Buy(q, p, fee, t)` ve `Sell(q, p, fee, t)`; `q` miktar, `p` birim fiyat (TRY),
`fee` toplam ek maliyet (işçilik, komisyon).

## 2. Maliyet yöntemi
Varsayılan: **ağırlıklı ortalama maliyet** (Türkiye'de kuyumcu/kullanıcı sezgisine
en yakın). Alternatif (ayarlardan): FIFO.

Ortalama maliyet, her işlemden sonra:
- `Buy`: `Q' = Q + q`, `C' = C + q·p + fee`, `avg = C'/Q'`
- `Sell`: `realized += q·(p − avg) − fee`, `Q' = Q − q`, `C' = C − q·avg`
  (`avg` satışta değişmez)
- `q > Q` olan satış reddedilir (validasyon hatası).

## 3. Anlık değer ve kâr/zarar
- `price` = kullanıcının seçtiği fiyat tipi: `bid` (varsayılan, bozdurma),
  `ask` veya `mid` (REQ-P4).
- `value = Q · price`
- `unrealized = value − C`
- `unrealized% = unrealized / C` (C = 0 ise gösterilmez)
- `spreadCost = Q · (ask − bid)` → "Şimdi alıp hemen satsan kaybın" bilgisi.
- `total P&L = realized + unrealized`

Örnek (AC-P3-1): Buy(10, 5000), Buy(5, 5600) → Q=15, C=78.000, avg=5.200.
bid=5.925 → value=88.875, unrealized=10.875 (%13,94).

## 4. Reel getiri (REQ-P7)
Nominal TL kârı enflasyon ortamında yanıltıcıdır. Her `Buy` için alternatif
senaryo hesaplanır:

- **USD karşılaştırması:** `q·p + fee` tutarı alım tarihindeki USD/TRY ile USD'ye
  çevrilmiş sayılır → bugünkü USD/TRY ile TL'ye geri çevrilir. Tüm alımlar için
  toplam = `C_usd_bugün`. `vsUSD = value − C_usd_bugün`.
  Geçmiş kur: `frankfurter` tarihsel uç noktası; alım sırasında kur kaydedilir
  (`Transaction.fxAtTrade`), sonradan tekrar çekilmez.
- **TÜFE karşılaştırması:** `C_tufe = Σ (q·p + fee) · CPI(bugün) / CPI(alım ayı)`.
  `vsCPI = value − C_tufe`.
  CPI kaynağı: ücretsiz ve anahtarsız güvenilir bir API yok (TCMB EVDS anahtar
  ister). v1'de **uygulamayla birlikte gelen aylık TÜFE tablosu** (TÜİK açıklanan
  endeks), her sürümde güncellenir; kullanıcı son ayları elle ekleyebilir.
  → open-questions Q3.

Gösterim: "Nominal +%13,9 · USD'ye göre +%4,1 · Enflasyona göre −%2,3".

## 5. Portföy toplamı
- `total = Σ value_i` (TRY). Dövizli gösterim seçilirse bugünkü kurla bölünür.
- Dağılım yüzdesi `value_i / total`.
- Serbest varlık (elle fiyat) toplamda yer alır ama fiyat yaşı ayrıca gösterilir.

## 6. Ziynet altın birimleri
Çeyrek/yarım/tam vb. **adet** olarak tutulur, gram'a çevrilmez (fiyatları ayrıdır).
İsteğe bağlı "has altın karşılığı" bilgisi gösterilir (çeyrek ≈ 1,75 g × 22 ayar
= 1,604 g has); bu yalnız bilgi amaçlıdır, değerlemede kullanılmaz.

## 7. Test vektörleri
`KumbaraCore/Tests/PortfolioMathTests` içinde en az: tek alım, çoklu alım,
kısmi satış, tam satış, fazla satış hatası, ücretli alım, FIFO ile ortalamanın
farklı sonuç verdiği senaryo, USD ve TÜFE karşılaştırması.
