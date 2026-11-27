# 01 — Ürün Spesifikasyonu

## 1. Vizyon
Türkiye'deki bireysel kullanıcının "param nereye gidiyor" ve "biriktirdiğim şey
gerçekten değer kazanıyor mu" sorularına tek yerde, dürüst ve hızlı cevap veren,
sunucusuz bir cüzdan defteri.

## 2. Hedef kullanıcı
- **P1 — Birikimci:** Maaşının bir kısmını gram altın / çeyrek / döviz olarak
  biriktiriyor. Birden fazla zamanda farklı fiyatlardan almış; "ortalamam ne,
  şu an bozdursam ne eder" sorusunu soruyor.
- **P2 — Harcama takipçisi:** Aylık bütçesini kontrol etmek istiyor ama her
  harcamayı elle girmeye üşeniyor. Fişin ya da banka uygulamasının ekran
  görüntüsünü atmak istiyor.
- **P3 — Mac kullanıcısı:** Ay sonunda büyük ekranda tablo görünümünde düzenleme,
  toplu kategori atama ve dışa aktarma yapıyor.

## 3. Kapsam

### Kapsam içi (v1)
Gelir/gider kayıtları, hesaplar, kategoriler, bütçeler, tekrarlayan işlemler,
portföy (altın türleri, döviz, kripto, gümüş, serbest varlık), canlı fiyat,
kâr/zarar, OCR ile yakalama, iCloud eşitleme (opsiyonel), dışa/içe aktarma,
widget, uygulama kilidi.

### Kapsam dışı (v1)
Banka entegrasyonu / açık bankacılık (backend gerektirir), BIST hisse senedi
(ücretsiz ve güvenilir anlık kaynak yok — bkz. open-questions Q4), çok kullanıcılı
ortak bütçe, vergi hesaplama.

## 4. Gereksinimler

Biçim: EARS ("…olduğunda, sistem … yapacaktır"). `[Ö]` işaretli maddeler
benim önerilerimdir; onayına bağlıdır.

### 4.1 Hesaplar ve işlemler (LEDGER)
- **REQ-L1** Kullanıcı birden çok hesap oluşturabilir (Nakit, Banka, Kredi kartı).
  Her hesabın tek bir para birimi vardır.
- **REQ-L2** İşlem = tarih, tutar, yön (gelir/gider/transfer), hesap, kategori,
  not, opsiyonel satıcı, opsiyonel ek (fiş görüntüsü).
- **REQ-L3** Transfer iki hesap arasında tek bir kayıttır; toplam gelir/giderde
  sayılmaz.
- **REQ-L4** Yeni işlem ekleme, uygulama açıldıktan sonra **en fazla 2 dokunuşta**
  başlatılabilir ve tutar alanı klavye açık şekilde odaklanmış gelir.
- **REQ-L5** Kategoriler iki seviyelidir (ör. Market › Gıda). Varsayılan Türkçe
  kategori seti gelir; kullanıcı düzenleyebilir.
- **REQ-L6** `[Ö]` Satıcı → kategori eşlemesi öğrenilir: aynı satıcı ikinci kez
  girildiğinde son kullanılan kategori önerilir.
- **REQ-L7** `[Ö]` Tekrarlayan işlemler (kira, maaş, abonelik): kural tanımlanır,
  vadesi gelen işlem **taslak** olarak oluşur, kullanıcı onaylar (C5).
- **REQ-L8** Kredi kartı hesabında "ekstre kesim günü" tanımlanabilir; dönem
  harcaması ayrıca gösterilir. `[Ö]`
- **REQ-L9** `[Ö]` Taksitli harcama: toplam tutar ve taksit sayısı girildiğinde
  gelecek aylara taksit kayıtları planlanır. (Türkiye'de çok yaygın.)

### 4.2 Bütçe ve rapor (BUDGET)
- **REQ-B1** Kategori bazında aylık bütçe limiti tanımlanabilir.
- **REQ-B2** Harcama limitin %80'ine ve %100'üne ulaştığında yerel bildirim gönderilir.
- **REQ-B3** Aylık özet: toplam gelir, gider, net, kategori dağılımı, önceki aya göre fark.
- **REQ-B4** `[Ö]` "Bu ay günlük ne harcayabilirim": kalan bütçe ÷ kalan gün.

### 4.3 Portföy (PORTFOLIO)
- **REQ-P1** Kullanıcı varlık alımı/satımı kaydeder: varlık, miktar, birim fiyat,
  tarih, opsiyonel komisyon/işçilik, opsiyonel ödeme hesabı.
- **REQ-P2** Desteklenen varlık türleri: gram altın (24 ayar), has altın,
  çeyrek/yarım/tam/cumhuriyet/ata/reşat/beşli, 22 ayar bilezik (gram),
  14/18 ayar (gram), gümüş (gram), platin, döviz (USD, EUR, GBP, CHF…),
  kripto (BTC, ETH, …), **serbest varlık** (fiyatı elle girilen: fon, hisse, mevduat).
- **REQ-P3** Her pozisyon için gösterilir: toplam miktar, ortalama maliyet,
  toplam maliyet, güncel değer, kâr/zarar (tutar ve %). Formüller 03'te.
- **REQ-P4** Güncel değer **varsayılan olarak "bozdurma" (kuyumcunun alış)
  fiyatıyla** hesaplanır; kullanıcı satış/orta fiyatı seçebilir. Ekranda hangi
  fiyatın kullanıldığı ve makas tutarı yazar. (C6)
- **REQ-P5** Alım kaydı girilirken birim fiyat alanına o anki satış fiyatı ön
  doldurulur; kullanıcı kuyumcunun verdiği gerçek fiyatı yazabilir.
- **REQ-P6** Satış kaydında gerçekleşmiş kâr/zarar hesaplanır ve saklanır.
- **REQ-P7** `[Ö]` **Reel getiri:** Her pozisyon için "aynı parayla o gün USD
  alsaydın" ve "TÜFE'ye göre" karşılaştırması. (Türkiye'de nominal TL kârı
  yanıltıcıdır.) Yöntem 03 §4.
- **REQ-P8** Portföy toplamı, varlık dağılımı ve zaman içindeki değer grafiği.
  Geçmiş değer, uygulamanın kaydettiği fiyat anlık görüntülerinden çizilir (02 §6).
- **REQ-P9** `[Ö]` Hedef: "Düğün için 20 çeyrek", "Ev için 500.000 ₺" gibi
  birikim hedefi ve ilerleme çubuğu.
- **REQ-P10** `[Ö]` Gelir kaydından tek dokunuşla "bunun %X'ini birikime ayır"
  akışı (maaş geldi → 3 gram altın aldım).

### 4.4 Piyasa verisi (MARKET)
- **REQ-M1** Fiyatlar ücretsiz, anahtarsız kaynaklardan çekilir; birincil kaynak
  başarısız olursa yedek kaynağa geçilir (02).
- **REQ-M2** Uygulama ön plandayken fiyatlar en sık 60 sn'de bir yenilenir;
  arka planda BGAppRefresh ile fırsat buldukça.
- **REQ-M3** Her fiyatın kaynağı ve zaman damgası görüntülenebilir.
- **REQ-M4** `[Ö]` Fiyat alarmı: "Gram altın 5.500 ₺ altına düşerse haber ver"
  (arka plan yenilemesinde kontrol; garanti anlık değildir, arayüz bunu söyler).

### 4.5 Yakalama / OCR (CAPTURE)
- **REQ-C1** Kamera ile fiş tarama (iOS), galeriden/ekran görüntüsünden seçme
  (iOS, macOS), sürükle-bırak ve yapıştırma (macOS).
- **REQ-C2** Paylaş menüsü uzantısı: banka uygulamasında / mailde ekran görüntüsü
  veya PDF "Kumbara'ya gönder" ile taslak oluşturur.
- **REQ-C3** OCR sonucu şu alanları önerir: toplam tutar, tarih, satıcı,
  para birimi, (varsa) KDV; ve satıcıdan kategori.
- **REQ-C4** Önerilen her alan güven skoruyla gelir; düşük güvenli alan vurgulanır.
  Kayıt kullanıcı onayıyla kesinleşir (C5).
- **REQ-C5** Bir ekran görüntüsünde birden fazla işlem varsa (banka hareketleri
  listesi) her satır ayrı taslak olarak önerilir. `[Ö]`
- **REQ-C6** Aynı tutar + tarih + satıcı ile mevcut kayıt varsa "olası mükerrer"
  uyarısı verilir.
- **REQ-C7** `[Ö]` Kestirmeler (App Intents): "Kumbara'ya 250 lira market ekle",
  ve Kestirmeler otomasyonuyla ekran görüntüsünü doğrudan işleme.

### 4.6 Platform ve veri (PLATFORM)
- **REQ-X1** Minimum iOS 26 / macOS 26, hedef SDK iOS 27 / macOS 27 (Xcode 27).
  Tek SwiftUI kod tabanı, platforma özgü düzenler. Arayüz Liquid Glass tasarım
  diline tam uyumludur (06).
- **REQ-X2** iCloud eşitleme opsiyoneldir, varsayılan kapalı; açılınca CloudKit
  private DB kullanılır.
- **REQ-X3** Face ID / Touch ID / parola kilidi; uygulama arka plana geçince
  ekran önizlemesi bulanıklaştırılır.
- **REQ-X4** CSV ve JSON dışa aktarma; CSV içe aktarma (sütun eşleme ekranı ile).
- **REQ-X5** Widget'lar: portföy toplamı, gram altın fiyatı, bu ayki harcama/bütçe.
- **REQ-X6** Arayüz Türkçe ve İngilizce; sayı ve tarih biçimi yerel ayara göre
  (`1.234,56 ₺`).
- **REQ-X8** iOS: alt aksesuar olarak canlı piyasa şeridi; Denetim Merkezi /
  kilit ekranı / Eylem Butonu için "Harcama ekle" ve "Fiş tara" kontrolleri (06 §6).
- **REQ-X9** `[Ö]` macOS: menü çubuğu öğesi (canlı fiyat + hızlı ekleme), tam
  menü/klavye desteği, pencereye sürükle-bırak ile fiş içe aktarma (06 §7).
- **REQ-X7** Erişilebilirlik: Dynamic Type, VoiceOver etiketleri, renk körlüğü
  için kâr/zarar yalnız renkle değil işaretle de (▲▼ / +/−) ifade edilir.

## 5. Kabul senaryoları (örnek)
- **AC-P3-1** 10 g'ı 5.000 ₺'den, 5 g'ı 5.600 ₺'den alan kullanıcı için
  ortalama maliyet 5.200 ₺/g, toplam maliyet 78.000 ₺ gösterilir. Bozdurma fiyatı
  5.925 ₺ iken değer 88.875 ₺, kâr 10.875 ₺ (%13,94).
- **AC-C3-1** "TOPLAM *1.249,90" satırı içeren Migros fişinden tutar 1249.90,
  satıcı "Migros", kategori "Market" önerilir.
- **AC-M1-1** Birincil kaynak 10 sn içinde cevap vermezse yedekten alınan fiyat
  gösterilir ve kaynak etiketi değişir.
- **AC-C4** Ağ kapalıyken uygulama açılır, son fiyatlar zaman damgasıyla ve
  "çevrimdışı" etiketiyle görünür.
