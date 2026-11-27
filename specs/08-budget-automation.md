# 08 — Bütçe ve Otomasyon (M4)

Durum: **onaylandı** (2026-11-27). Kapsam: REQ-B1, B2, L7, L8, L9, M2, M4.
Kestirmeler (REQ-C7, eski T4.4) kullanıcı kararıyla v1.x'e ertelendi.
Tüm hesaplar `Decimal` (C3); hiçbir otomatik kayıt onaysız kesinleşmez (C5);
her şey cihazda, bildirimler yereldir (C1, C2).

## 1. Bütçeler (T4.1 — REQ-B1, B2)

### 1.1 Model
- **Bütçe** = (gider kategorisi | genel), aylık limit (`Money`, TRY), başlangıç ayı.
- Bir üst kategorinin bütçesi alt kategorilerinin harcamasını **içerir**
  (Market bütçesi = Gıda + Ev ihtiyaçları). Alt kategoriye ayrıca limit konabilir.
- **Genel bütçe** opsiyonel: tüm giderler. Tanımlıysa REQ-B4 "günlük ne
  harcayabilirim" bunu kullanır; yoksa bugünkü gibi gelir − gider.
- Devretme yok (v1): her ay sıfırdan. Kullanılmayan bütçe sonraki aya geçmez.
- Limit değişikliği yalnız o aydan itibaren geçerli; geçmiş aylar kendi limitini
  korur (aylık limit geçmişi tutulur, raporlar yanıltmasın).

### 1.2 Hesap
- Harcama = ayın kesinleşmiş (posted) giderleri; taslaklar sayılmaz.
- Transfer gider değildir. İade (gider kategorisinde gelir) harcamadan düşer.
- Taksitli alımda o aya düşen **taksit** sayılır, alımın tamamı değil (§3.2).
- Döviz cinsinden gider, işlem tarihindeki TRY karşılığıyla (kayıtlı kur; yoksa
  o günün TCMB kuru, `PriceBoard.usdTRY(on:)`).
- **Tempo:** `harcanan / limit` ile `geçen gün / ay günü` karşılaştırılır.
  Harcama tempoyu %10'dan fazla aşıyorsa satır "hızlı gidiyor" der
  (ör. ayın %40'ındasın, bütçenin %62'si gitti).

### 1.3 Bildirimler (REQ-B2)
- Eşikler: %80 ve %100. Her bütçe, her ay, her eşik için **en fazla bir kez**.
- Tetikleyici: eşiği geçiren işlem kaydedildiğinde (uygulama içinde, anında).
- Metin örneği: "Market bütçenin %80'i doldu · kalan ₺1.240, 9 gün".
- Bildirim izni ilk bütçe oluşturulurken, ne işe yarayacağı söylenerek istenir
  (uygulama açılışında değil). İzin yoksa bütçe yine çalışır, ekranda gösterilir.

### 1.4 Arayüz
- **Bütçe** sekmesi: ay seçici; genel bütçe halkası (kalan tutar, kalan gün,
  günlük hak); altında kategori satırları: ad, ilerleme çubuğu,
  `₺3.250 / ₺4.000`, tempo notu. Renk anlam taşır: normal (vurgu), %80+ (turuncu),
  %100+ (kırmızı), C6.
- Satıra dokununca o kategorinin o ayki işlemleri.
- Boş durumda: son 3 ayın ortalamasına göre **önerilen limitlerle** tek dokunuşla
  başlatma ("Son 3 ayda markete ortalama ₺3.900 harcadın").

## 2. Tekrarlayan işlemler (T4.2 — REQ-L7)

### 2.1 Kural
- Alanlar: tür (gider/gelir), tutar, hesap, kategori, satıcı, not, sıklık,
  başlangıç tarihi, opsiyonel bitiş (tarih ya da tekrar sayısı).
- Sıklık: her ay (gün N), her hafta (gün), her yıl, her N ay. Ayın 31'i gibi
  olmayan günde ayın **son günü** kullanılır; tatil/hafta sonu kaydırması yok.
- "Tutar değişebilir" işareti (fatura): taslak tutarsız gelir, kullanıcı doldurur.

### 2.2 Taslak üretimi (C5)
- Uygulama açılınca ve arka plan yenilemesinde: vadesi gelmiş (bugün dahil)
  ve henüz taslağı olmayan her tekrar için **bir taslak** oluşur.
  Kaçırılan aylar ayrı ayrı oluşur (3 ay açılmadıysa 3 kira taslağı).
- Aynı kural + aynı vade için ikinci taslak oluşmaz (idempotent; anahtar:
  kural kimliği + vade günü).
- Taslaklar **İşlemler**'in en üstünde "Onay bekleyenler" bölümünde; tek
  dokunuşla onayla, düzenle ya da atla. "Hepsini onayla" var.
- Vade günü sabahı yerel bildirim: "Kira ₺18.000 · onay bekliyor".
- Taslaklar bütçeye ve bakiyeye onaylanana kadar sayılmaz; Özet'te
  "yaklaşan" olarak ayrı görünür.

### 2.3 Öneri `[Ö]`
- Son 3 ayda aynı satıcıya ±%5 tutarla ayda bir yapılan ödeme → "Bunu tekrarlayan
  yapalım mı?" önerisi (bir kez sorulur, reddedilirse bir daha sorulmaz).

## 3. Kredi kartı: ekstre dönemi ve taksit (T4.3 — REQ-L8, L9)

### 3.1 Ekstre dönemi
- Kart hesabında **ekstre kesim günü** (var: `statementDay`) ve **son ödeme günü**
  (yeni; varsayılan kesimden 10 gün sonra).
- Dönem = önceki kesimin ertesi günü … bu kesim günü (kesim günü dahil).
- Kart ekranında: **bu dönem** harcaması, **son ekstre** tutarı ve son ödeme
  tarihi, kalan gün; gelecek dönemlere düşen taksitler toplamı.
- Son ödeme gününden 3 gün önce yerel bildirim (kullanıcı kapatabilir).
- Karta yapılan transfer "ödeme" sayılır ve ekstre borcundan düşer.

### 3.2 Taksit
- Gider girerken (kart hesabında) "Taksit: 2–36" seçilir.
- Bir **taksit planı** oluşur: toplam, sayı, ilk taksit tarihi. Her taksit
  ayrı bir işlemdir (`toplam / n`, kuruş farkı **ilk** taksite eklenir:
  ₺1.000 / 3 = 333,34 + 333,33 + 333,33).
- Taksit tarihleri: alımdan sonraki ilk ekstre döneminden başlayarak her dönem
  bir taksit (kesim günü yoksa alım günü, her ay).
- Gelecek taksitler **planlanmış** işlemdir: listede soluk ve "3/6" rozetiyle,
  tarihi gelince kendiliğinden kesinleşir (kullanıcının kendi girdiği bir alımın
  parçası olduğu için ayrıca onay istemez; C5'in "otomatik oluşturulan" kapsamı
  dışında, tek bir kullanıcı eylemidir).
- Bütçe ve aylık özet yalnız o aya düşen taksiti sayar.
- Planı düzenlemek/silmek: kalan taksitler birlikte değişir; geçmiş taksitler
  korunur.

## 4. Kestirmeler — ertelendi
REQ-C7 v1.x adayıdır (2026-11-27 kararı). `TransactionOrigin.intent` ileride kullanılmak üzere kalır.

## 5. Fiyat alarmı ve arka plan yenilemesi (T4.5 — REQ-M2, M4)

- Alarm = varlık, yön (üstüne çıkarsa | altına düşerse), eşik, fiyat tipi
  (bozdurma varsayılan, D6).
- Alarm **bir kez** çalar ve kapanır; bildirimde "tekrar kur" eylemi var.
  Aynı yönde kalan fiyat her yenilemede tekrar bildirim üretmez.
- Kontrol anları: her başarılı fiyat yenilemesi (ön plan 60 sn, arka plan
  `BGAppRefreshTask`, iOS fırsat buldukça; macOS'ta uygulama açıkken).
- Arayüz dürüstçe söyler: "Telefonun arka planda ne sıklıkla fiyat
  yenilemeye izin verdiğine bağlı; anlık değildir." (C6)
- Tahmini (ons fiyatından hesaplanan) fiyat alarm çaldırmaz; ilk gerçek
  fiyatla doğrulanır (yanlış alarmı önler).
- Varlık detayında "Alarm kur"; Piyasa sayfasında satırı basılı tutunca.

## 6. Veri modeli (SchemaV1 içinde genişletme; ilk yayından önce, D10)
- `Budget`: id, category?, limit geçmişi (`[ay: limit]` kanonik metin), oluşturulma.
- `RecurrenceRule`: id, şablon alanları, sıklık, başlangıç, bitiş, son üretilen vade.
- `LedgerTransaction` ek alanları: `recurrenceID?`, `dueDay?` (idempotens),
  `installmentPlanID?`, `installmentIndex?`, `statusRaw` = draft | posted | planned.
- `InstallmentPlan`: id, toplam, sayı, ilk tarih, hesap.
- `LedgerAccount`: `paymentDueDay?`.
- `PriceAlert`: id, varlık, yön, eşik, fiyat tipi, kuruldu, çaldı?.
- `NotificationLog`: (tür, nesne, dönem) → bir kez gönderim garantisi.
Hepsi CloudKit uyumlu (opsiyonel ilişkiler, `unique` yok).

## 7. Kabul ölçütleri
- **AC-B1-1** Market bütçesi ₺4.000; Gıda ₺2.500 + Ev ₺800 harcandı → Market
  satırı ₺3.300 / ₺4.000 (%82,5), turuncu; tam bir bildirim gönderildi.
- **AC-B2-1** Aynı ay %80'i geçen ikinci işlem yeni bildirim üretmez; %100'ü
  geçen işlem bir bildirim daha üretir.
- **AC-L7-1** Her ayın 31'i kira kuralı, Şubat'ta 28/29'unda taslak üretir.
- **AC-L7-2** Uygulama 3 ay açılmazsa açılışta 3 ayrı taslak; ikinci açılışta
  yeni taslak oluşmaz.
- **AC-L9-1** ₺1.000, 3 taksit → 333,34 + 333,33 + 333,33; toplam tam ₺1.000.
- **AC-L9-2** Kesim günü 15 olan kartta 20 Kasım alımının ilk taksiti 15 Aralık
  ekstresine düşer.
- **AC-L8-1** Kesim 15: 15 Kasım'daki harcama Kasım dönemine, 16 Kasım'daki
  Aralık dönemine yazılır.
- **AC-M4-1** Gram altın "6.100 üstü" alarmı: 6.120 gelince bir bildirim, 6.130'da
  yeni bildirim yok; tahmini fiyat 6.200 olsa bile bildirim yok.

## 8. Kararlar (2026-11-27)
- **K1** Bütçede taksitli alımın yalnız o aya düşen taksiti sayılır.
- **K2** (Kestirmeler ertelendi; karar gerekmedi.)
- **K3** Planlanmış taksitler tarihi gelince kendiliğinden kesinleşir.
- **K4** Bütçe devretme v1'de yok; her ay sıfırdan.
