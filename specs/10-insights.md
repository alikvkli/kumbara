# 10 — İçgörüler ve Araçlar (M6)

Durum: **onaylandı** (2026-11-27). Kapsam: REQ-I1 … REQ-I7 (yeni).
İlkeler değişmez: her şey cihazda (C1), sunucu yok (C2), `Decimal` (C3), onaysız kayıt
yok (C5), dürüst arayüz (C6). Hiçbir özellik yeni bir ağ isteği, hesap ya da izin
gerektirmez; tek istisna §6'daki isteğe bağlı konum (karar K3).

Ortak kural: bir içgörü **yeterli veri yoksa gösterilmez**; uydurma ya da "henüz" diye
boş kart yok. Her sayının yanında neye dayandığı yazar ("son 3 ay", "6 ödeme").
Hesaplar KumbaraCore'da saf fonksiyon olarak yazılır, Linux'ta test edilir.

## 1. Aylık rapor (T6.1 — REQ-I1)
Ay kapanınca (ayın 1'i sabahı) tek sayfalık özet; Özet sekmesinde en üstte bir kart
olarak 7 gün durur, sonra "Raporlar" listesine geçer (Özet › Geçmiş aylar).

İçerik (yalnız verisi olan satırlar):
- **Toplam:** gelir, gider, net; önceki aya ve son 3 ay ortalamasına göre fark.
- **Bütçe:** "Bütçenin %92'sini kullandın" / "₺2.400 aştın"; kategori bazında aşanlar.
- **En çok değişen 3 kategori** (tutar ve yüzde; ₺500'den küçük farklar sayılmaz).
- **En büyük 3 harcama** ve en çok gidilen satıcı.
- **Birikim:** ay başı → ay sonu bozdurma değeri, aya yapılan alımlar ayrılarak
  ("₺8.000 ekledin, fiyat etkisi +₺3.150"). Aynı dönemde TÜFE (veri varsa).
- **Tek cümlelik özet** başta; kural tabanlı, en belirgin bulguyu seçer
  (ör. "Kasım'da ₺37.806 harcadın, Ekim'den %4 fazla; artış çoğunlukla markette.").

Paylaşma: "Görsel olarak paylaş" → `ImageRenderer` ile 1080×1350 PNG. Varsayılan
olarak **tutarlar gizli**, yalnız yüzdeler (gizlilik); "Tutarları göster" anahtarı.
Bildirim: "Kasım raporu hazır" (ayarlardan kapatılabilir, varsayılan açık).

## 2. Abonelikler (T6.2 — REQ-I2)
08 §2.3'teki ertelenmiş öneri burada yapılır.

Algılama (`SubscriptionDetector`):
- Aynı satıcı (Merchant normalleştirmesi) için en az **3 ödeme**, aralıklar 28–35 gün
  (aylık) ya da 360–370 gün (yıllık); her ödeme bir öncekine göre ±%15 içinde. Zincirde
  bir kez, en çok +%50'lik zam adımına izin verilir (zamlanan abonelik kaybolmasın).
- Beklenen günden 40 gün sonra hâlâ ödeme yoksa abonelik bitmiş sayılır, listelenmez.
- Zaten tekrarlayan kural olan ödemeler "tanımlı" olarak listelenir, yeniden önerilmez.
- Taksitler ve transferler hariç.

Ekran (Bütçe › Abonelikler):
- Toplam: "Aylık ₺1.230 · yılda ₺14.760", yıllıklar aylığa bölünerek eklenir.
- Her satır: satıcı, son tutar, sıradaki tahmini tarih, "6 ödeme" dayanağı.
- **Fiyat artışı:** son tutar bir öncekinden %3+ fazlaysa işaret: "₺229 → ₺279 (+%22)";
  bir kez bildirim.
- **Kesilmiş olabilir:** beklenen tarihten 10 gün geçti ve ödeme yok → gri "Bu ay görünmedi".
- Eylemler: "Tekrarlayan yap" (08 §2 kuralı oluşturur, onaylı), "Abonelik değil"
  (satıcı bir daha önerilmez).

## 3. "Alabilir miyim?" (T6.3 — REQ-I3)
Bütçe sekmesinde ve hızlı eklemede "Hesapla" girişi. Kullanıcı tutar, ödeme şekli
(peşin / N taksit, kart seçimi) ve isteğe bağlı kategori girer; **kayıt oluşmaz**.

Sonuç, yan yana iki-üç senaryo (peşin, 3 taksit, 6 taksit):
- Bu ayın bütçesine etkisi: "Bu ay ₺2.400 açık verirsin" ya da "Günlük harcayabileceğin
  ₺640'tan ₺210'a düşer".
- Sonraki aylar: taksit bütçeye hangi ay ne kadar girer (08 §3.2 kuralıyla aynı).
- Kart: ekstre kesimine göre ilk taksitin hangi ekstreye düştüğü, kart limitinin
  kalanı (limit tanımlıysa).
- Hedefler: aylık birikim hızı bu tutar kadar düşerse en yakın hedefin kaç ay
  gecikeceği ("Düğün hedefi 1 ay gecikir"). Hız = son 3 ayın ortalama net birikimi.
- Dil tavsiye vermez, yalnız sonucu söyler (C6): "alma" ya da "al" denmez.
- "Bunu kaydet" ile işlem taslağı olarak eklenebilir (C5).

## 4. Alacak / borç (T6.4 — REQ-I4)
Arkadaşla bölünen harcamalar ve verilen/alınan borçlar. Paylaşım yok; yalnız senin
defterin.

- **Kişi:** ad (ve isteğe bağlı rehberden seçim; rehber izni yalnız seçici ile,
  `CNContactPicker`, kalıcı izin istemez).
- **Bölme:** bir giderde "Böl" → kişiler ve paylar (eşit / tutar / yüzde). Bütçeye
  yalnız **kendi payın** girer; kalan kişiye alacak yazılır.
- **Elden borç:** "Ayşe'ye ₺1.000 verdim" / "Mehmet'ten ₺500 aldım" (hesaptan çıkar /
  girer, bütçeye girmez).
- **Kapatma:** "Ödedi" → tam ya da kısmi; seçilen hesaba gelir (bütçeye girmez).
- Ekran (Özet › Alacak ve borçlar): kişi başı net bakiye, "Toplam alacağın ₺1.450".
- Hatırlatma: kişi başına isteğe bağlı tarih, yerel bildirim. "Hatırlat" eylemi
  hazır metinle paylaş sayfasını açar ("Selam, yemekten ₺450 kalmıştı 🙂"); mesajı
  kullanıcı gönderir.
- Dışa aktarma ve yedek (09 §3) kişileri ve payları da kapsar.

## 5. Ödeme takvimi (T6.5 — REQ-I5)
Gelecekteki tüm bilinen ödemeler tek görünümde (Bütçe › Takvim):
- Kaynaklar: tekrarlayan işlemler, kart son ödemeleri (ekstre tutarıyla; dönem
  sürüyorsa "şu ana kadar"), taksitler, abonelik tahminleri (§2, "tahmini" etiketiyle),
  alacak hatırlatmaları (§4), maaş gibi tekrarlayan gelirler.
- Ay görünümü + altında liste; varsayılan "önümüzdeki 30 gün". Gün hücresinde ödeme başına
  nokta (en çok 3), gelir için yeşil nokta; ayın en büyük 3 ödeme günü (₺1.000 ve üstü) kısa
  tutarla ("₺22,5 B") yazılır (2026-11-28).
- Üst satır: "Önümüzdeki 7 günde ₺21.400 ödeme var · maaşa 5 gün". Hesap bakiyesi
  tanımlıysa "Ödemelerden sonra hesapta ₺3.200 kalır"; eksiye düşüyorsa turuncu.
- Kayıt oluşturmaz; dokununca kaynağına gider (kural, kart, kişi).
- Widget: orta boy "Yaklaşan ödemeler" (sıradaki 3 ödeme).

## 6. Hızlı ekleme önerisi (T6.6 — REQ-I6)
Yeni işlem ekranı açıldığında, alışkanlığa uyan 1–3 öneri çipi en üstte:
"☕ Kahve Dünyası ₺185" → tek dokunuş formu doldurur (kaydetmek yine kullanıcıda, C5).

- Model (`QuickAddSuggester`): son 90 gündeki giderler; satıcı + kategori + tutar
  medyanı. Puan = haftanın günü ve saat penceresi (±60 dk) eşleşmesi × sıklık ×
  yakınlık. En az **4 tekrar** olmadan öneri yok.
- Tutar: medyan; son 3 tutar aynıysa o tutar.
- Kontrol Merkezi kontrolü ve widget'tan açılan hızlı eklemede de görünür.
- "Bunu önerme" uzun basışla; Ayarlar › Öneriler'den tamamen kapatılabilir.
- Konum: bkz. K3.

## 7. Altın birikim planı (T6.7 — REQ-I7)
Düzenli alım kuralı: "Her ayın 15'inde 2 gram altın" ya da "Her maaşta ₺5.000'lik
çeyrek". Portföy › Planlar.

- Kural: varlık, miktar **ya da** tutar, sıklık (aylık gün / haftalık gün / maaş
  gelince), isteğe bağlı hedef bağlantısı (09 hedefleri).
- Gün gelince yerel bildirim: "2 gram altın alma günü · şu an ₺6.120 (satış)".
  Dokununca alım formu o anki **satış** fiyatıyla (kullanıcının ödediği) dolu açılır;
  fiyat kuyumcunun verdiğiyle değiştirilebilir, kayıt onayla (C5).
- "Maaş gelince" tetikleyicisi: maaş kategorisinde gelir onaylanınca, 09'daki
  "birikime ayır" sayfası planla dolu açılır.
- Plan ekranı: uyum ("12 ayın 10'unda aldın"), plan ortalama maliyeti ile şu anki
  fiyat, toplam biriken miktar, bağlı hedefe kalan süre.
- **Dürüst karşılaştırma:** "Planla aldıkların ortalama ₺4.850'den; aynı parayı her ay
  dolara koysaydın bugün ₺X olurdu" (03'teki gerçek getiri hesabı yeniden kullanılır).
  Atlanan aylar ceza gibi gösterilmez, yalnız sayılır.

## 8. Veri modeli (SchemaV1 içinde genişletme; ilk yayından önce, D10)
- `Person` (ad, rehber kimliği?, hatırlatma tarihi?)
- `Split` (işlem, kişi, pay tutarı, kapanan tutar) — işlemde `ownShare` hesabı buradan.
- `Debt` (kişi, yön, tutar, tarih, hesap, kapanış kayıtları)
- `SavingsPlan` (varlık, miktar/tutar, sıklık, gün, hedef?, aktif)
- "Abonelik değil" / "Bunu önerme": bildirim defterinde (`NotificationLog`) anahtar olarak
  (`dismiss:subscription:<satıcı>`); ayrı model yok.
- `MonthlyReport` saklanmaz; her açılışta hesaplanır (yalnız "görüldü" bayrağı
  UserDefaults'ta).
- Yedek sürümü 1 kalır; yeni alanlar opsiyonel (09 §3 ile geriye uyumlu).

## 9. Sıra
1. T6.2 Abonelikler ve T6.1 Aylık rapor (mevcut veriyle, en görünür etki)
2. T6.5 Ödeme takvimi (abonelik tahminlerini kullanır)
3. T6.3 Alabilir miyim?
4. T6.7 Altın birikim planı
5. T6.4 Alacak / borç (en çok yeni model)
6. T6.6 Hızlı ekleme önerisi

Her adım: KumbaraCore hesap + testler → KumbaraData modeli → iOS/macOS ekranı →
demo veriye örnek → ekran görüntüsü turu.

## 10. Kabul ölçütleri
- **AC-I1-1** Ekim ₺36.350, Kasım ₺37.806 gider → rapor "%4 fazla" der; ₺500'den
  küçük kategori farkı "en çok değişen"e girmez. Paylaşılan görselde varsayılan
  olarak ₺ tutarı yok.
- **AC-I2-1** Netflix 3 ay ₺229, 4. ay ₺279 → abonelik listede, "+%22" işaretli, bir
  bildirim. 2 ödemeli satıcı listede yok.
- **AC-I2-2** Tekrarlayan kuralı olan kira "tanımlı" görünür, öneri olarak gelmez.
- **AC-I3-1** ₺12.000, 6 taksit, kesim 20'si, alım 22 Kasım → Kasım bütçesine ilk taksit ₺2.000
  girer (08 §3.2: ilk taksit alım ayında); ilk taksit 20 Aralık ekstresinde (son ödeme 30 Aralık);
  hiçbir kayıt oluşmaz.
- **AC-I4-1** ₺900 yemek, 3 kişi eşit → bütçeye ₺300; Ayşe ve Mehmet'ten ₺300'er
  alacak; Ayşe ₺300 ödeyince bütçe değişmez, hesap +₺300.
- **AC-I5-1** Kira (1'i), kart son ödemesi (7'si), Netflix tahmini (9'u) → 1 Aralık'ta
  "Önümüzdeki 7 günde" kira + kart; Netflix "tahmini" etiketli 30 gün listesinde.
- **AC-I6-1** Son 6 hafta her hafta içi 08:00–09:00 kahve ₺185 → Salı 08:30'da ilk
  öneri; Cumartesi 08:30'da yok. 3 tekrarlı satıcı önerilmez.
- **AC-I7-1** "Her ayın 15'i 2 gram" → 15'inde bir bildirim; form satış fiyatıyla dolu,
  kaydetmeden işlem yok. 12 ayda 10 alım → "12 ayın 10'unda".

## 11. Kararlar (2026-11-27, önerildiği gibi onaylandı)
Uygulama sırasında verilen küçük kararlar (kullanıcı uyurken, spec'in ruhuna göre; gözden geçirilecek):
- **U1** "Alabilir miyim?" Bütçe ekranından açılır; hızlı eklemeye ayrı giriş konmadı (form kalabalıklaşmasın).
- **U2** Alacak/borçta elden borç ve kapanış tek taraflı **transfer** olarak kaydedilir (karşı taraf kişi);
  böylece hesap bakiyesi doğru kalır, bütçeye girmez. Kartla borç verme/ödeme sunulmaz.
- **U3** Bölme, kaydedilmiş giderin düzenleme ekranındaki "Böl" ile yapılır; gider silinince alacak da düşer.
- **U4** Plan uyumu "Alım: 10 / 12 vade" biçiminde (değişkenden sonra ek yok, 06 §11); vadeden 3 gün önceki
  alım o vadeye sayılır.
- **U5** Kartla ödenen abonelik ve tekrarlar ödeme takviminde ayrı kalem değil, kart son ödemesinin içinde.
- **U6** Kart limiti alanı olmadığı için "limit yetmiyor" uyarısı şimdilik gösterilmez (hesap modelinde limit yok).
- **K1 Rapor zamanı:** ✱ ayın 1'i 09:00 bildirim + Özet'te 7 gün kart. (Alternatif: yalnız
  Geçmiş aylar listesi, bildirimsiz.)
- **K2 Paylaşılan rapor görseli:** ✱ varsayılan tutarlar gizli, yalnız yüzdeler.
- **K3 Hızlı eklemede konum:** ✱ v1'de **yalnız saat ve gün**; konum izni istenmez.
  Konum (cihazda, "Kullanırken") ayrı bir sonraki adım olarak değerlendirilir.
- **K4 Alacak/borçta rehber:** ✱ yalnız sistem kişi seçici (kalıcı izin yok); elle ad
  yazmak her zaman mümkün.
- **K5 Abonelik eşiği:** ✱ en az 3 ödeme, ±%15 tutar, fiyat artışı uyarısı %3+.
- **K6 "Alabilir miyim?" birikim hızı:** ✱ son 3 ayın ortalama net birikimi; 3 aydan az
  veri varsa hedef etkisi gösterilmez.
