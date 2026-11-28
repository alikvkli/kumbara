# 12 — Kira Artış Hesabı

Durum: **uygulandı, kullanıcı onayı bekliyor** (2026-11-28). Kapsam: REQ-I9 (yeni).
İlkeler değişmez: her şey cihazda (C1), sunucu yok (C2), `Decimal` (C3), onaysız kayıt
yok (C5), dürüst arayüz (C6). Yeni ağ isteği ya da izin yok; TÜFE uygulamayla gelen
tablodan (D3, `CPIData`).

## 1. Kural (TBK m.344)
- Yenilenen kira yılında artış, **bir önceki kira yılında TÜFE'nin on iki aylık
  ortalamalara göre değişim oranını** geçemez. Konut ve işyeri için aynı. Konutlardaki
  %25 sınırı 1 Temmuz 2024'te bitti; sonrasında tek ölçüt bu oran.
- Uygulamadaki karşılığı: yenileme ayından **bir önceki ayın** oranı. Ör. Temmuz 2026
  yenilemesi → Haziran 2026 oranı %32,03 (TÜİK, 3 Temmuz'da açıklar).
- Oran = (son 12 ayın endeks ortalaması) / (önceki 12 ayın endeks ortalaması) − 1, yüzde
  olarak iki basamağa yuvarlanır (TÜİK'in yayımladığı gibi). Yeni kira üst sınırı =
  kira × (1 + oran), kuruşa yuvarlanır. Ortalama düştüyse artış 0 (kira kendiliğinden düşmez).
- Sınır bir üst limittir; taraflar daha düşüğünde anlaşabilir. Sınırı aşan artış
  anlaşması geçersizdir; ekran bunu uyarı olarak söyler, karar vermez.
- **5 yıl:** 5 yılı dolduran sözleşmede yeni kira emsal ve hakkaniyete göre mahkemece
  belirlenebilir (TBK m.344/3). **Hesaplanmaz**, yalnız bilgi satırı.
- Döviz cinsinden kiralar kapsam dışı; ekranda bir satırla belirtilir.

Doğrulama: gömülü tablo TÜİK'in açıkladığı oranları birebir veriyor (test):
Haziran 2024 %65,07 · Aralık 2024 %58,51 · Aralık 2025 %34,88 · Haziran 2026 %32,03.

## 2. Veri yoksa
- Gereken 24 aydan biri tabloda yoksa oran **hesaplanmaz, tahmin edilmez**.
- Ay henüz açıklanmadıysa: "Bu yenileme Kasım 2026 oranıyla hesaplanır; TÜİK bu veriyi
  3 Aralık günü açıklar."
- Açıklandı ama uygulama güncellenmediyse: kullanıcı TÜİK bülteninden oranı elle girer.
  Elle oran yalnız o referans ay için geçerlidir; tablo o ayı içerince tablo kullanılır.
  Yeni kira kaydedilince elle oran silinir.

## 3. Yenileme günü
- Sözleşme başlangıcının yıl dönümleri (29 Şubat → 28 Şubat).
- Ekranda: son 45 gün içinde yenilendiyse o yenileme (tutarı güncellemek için), değilse
  sıradaki. Kaçıncı kira yılı başladığı yazılır.

## 4. Ekranlar
- **Bütçe › Kira artışı** (Ödeme takvimi / Abonelikler / Alabilir miyim? bölümünde;
  sağda en yakın yenileme günü).
- Liste: sözleşme adı, yenileme günü, "en fazla ₺X" ya da "oran bekleniyor". Boşken
  açıklama ve "Sözleşme ekle".
- Ayrıntı: kahraman sayı "Yeni kira en fazla" (kiracı) / "İsteyebileceğin kira en fazla"
  (ev sahibi); kira yılı ve tarih; şu anki kira, oran, en fazla artış; oranın dayanağı
  ("Ekim 2026 TÜFE 12 aylık ortalamalara göre değişim"). Oran yoksa "Açıklanan oran"
  alanı. "Kararlaştırılan kira" alanı: sınırı aşarsa turuncu uyarı; "Yeni kirayı kaydet".
  Altta 5 yıl satırı (gerekirse) ve "bilgi amaçlıdır, hukuki danışmanlık yerine geçmez".
- Düzenleyici: ad, taraf (Kiracı / Ev sahibi), sözleşme başlangıcı, şu anki aylık kira,
  isteğe bağlı tekrarlayan işlem bağlantısı (kira / kira geliri kategorisindekiler önde;
  yeni sözleşmede kira kuralı varsa önceden seçili ve tutar, başlangıç, taraf ondan dolar).
  Altta canlı hesap.

## 5. Kayıtlar ve hatırlatma
- `RentContract` (SchemaV1 içinde genişletme, D10): ad, taraf, başlangıç, kira, bağlı kural
  kimliği, elle oran (ay + oran). JSON yedekte `rents` (opsiyonel, eski yedekler okunur).
- "Yeni kirayı kaydet": sözleşmenin kirası ve bağlı kuralın tutarı güncellenir; sonraki
  taslaklar yeni tutarla gelir, geçmiş kayıtlar değişmez (C5).
- Hatırlatma: yenilemeden 30 gün önce 10:00 ("Kira yenilemesi yaklaşıyor"); oran tabloda
  yoksa TÜİK'in açıklama günü 11:00 ("Kira artış oranı açıklandı"). Sözleşme silinince kalkar.

## 6. Kabul ölçütleri
- **AC-I9-1** Gömülü TÜFE tablosu §1'deki dört yayımlanmış oranı verir.
- **AC-I9-2** 15 Temmuz 2025 başlangıçlı ₺20.000 kira, 1 Temmuz 2026'da → 2. kira yılı,
  Haziran oranı %32,03, en fazla ₺26.406; ₺27.000 sınırı aşar.
- **AC-I9-3** Aralık 2026 yenilemesi (Kasım verisi tabloda yok) → oran yok, tutar yok;
  Kasım için elle girilen %31,05 → ₺15.000 → ₺19.657,50; başka ay için girilen oran
  kullanılmaz; tablo biliyorsa elle oran yok sayılır.
- **AC-I9-4** Örnek veri: 1 Kasım'da 3. yılı başlayan ₺22.500 ev kirası, Ekim oranıyla;
  yeni kira kaydedilince bağlı kira kuralının tutarı da değişir. Yedekten aynen döner.

## 7. Kararlar (uygulama sırasında; gözden geçirilecek)
- **R1** Giriş Bütçe ekranında (kira bir gider/gelir kalemi). Ayrı sekme ya da Özet satırı yok.
- **R2** Referans ay = yenileme ayından önceki ay (yaygın uygulama). Yenileme ayının 1–2'sinde
  oran henüz açıklanmamış olabilir; ekran açıklanacağı günü söyler.
- **R3** Tablo eksikse elle oran girilir; tahmin ya da internetten çekme yok (C2).
- **R4** Kiracı ve ev sahibi aynı hesap; yalnız başlık metni değişir. Ev sahibinin kira
  geliri kuralı da bağlanabilir.
- **R5** Ödeme takvimine ayrı kalem eklenmedi; kira zaten tekrarlayan işlem olarak orada.
