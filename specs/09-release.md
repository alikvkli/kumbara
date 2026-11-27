# 09 — Yayın Hazırlığı (M5)

Durum: **taslak** (2026-11-27). Kapsam: REQ-X2, X3, X4, X5, X6, X7, X8, X9, P7, P9, P10.
İlkeler değişmez: her şey cihazda (C1), sunucu yok (C2), `Decimal` (C3), onaysız kayıt
yok (C5), dürüst arayüz (C6).

## 0. Ön koşul: veri deposu App Group'a taşınır
Widget'lar, Denetim Merkezi kontrolleri ve paylaş uzantısı aynı veriyi okumalı. SwiftData
deposu `group.com.alikvkli.kumbara` kapsayıcısına taşınır (`ModelConfiguration(groupContainer:)`).
İlk yayından önce olduğu için göç gerekmez (D10); geliştirme cihazındaki eski depo bir kez
kopyalanır. Bu iş T5.1–T5.4'ün önündedir.

## 1. iCloud eşitleme (T5.1 — REQ-X2)
- Ayarlar › iCloud: aç/kapa, varsayılan **kapalı**. Açıklama: "Verilerin Apple hesabındaki
  özel iCloud alanına şifreli gider; Kumbara'nın sunucusu yok, biz göremeyiz."
- Açınca: aynı yerel depo CloudKit private DB ile eşitlenir (`cloudKitDatabase: .private`).
  Model zaten CloudKit uyumlu (opsiyonel ilişkiler, `unique` yok; 08 §6).
- Kapatınca: yerel veri kalır, buluttaki kopya silinmez; "iCloud'daki kopyayı da sil" ayrı ve
  onaylı eylem.
- Değişiklik depo yeniden açılarak uygulanır ("Uygulama yeniden başlayacak").
- Durum satırı: "Son eşitleme az önce" / "iCloud hesabı yok" / "Depolama dolu". Hata
  sessizce yutulmaz.
- **Engel:** CloudKit kapsayıcısı Team ID ister (Q10). Kod yazılır, test cihazda Team ID
  gelince yapılır; CI imzasız derler.

## 2. Kilit (T5.2 — REQ-X3)
- Ayarlar › Kilit: kapalı (varsayılan) | Face ID / Touch ID (yedek: cihaz parolası,
  `deviceOwnerAuthentication`). Uygulamanın ayrı parolası yok.
- Kilitlenme zamanı: hemen | 1 dk | 5 dk sonra (arka planda geçen süre).
- Uygulama değiştirici önizlemesi her zaman bulanık (kilit kapalı olsa bile seçenekle:
  "Önizlemede tutarları gizle", varsayılan açık).
- Kilit ekranı: uygulama simgesi, "Kumbara kilitli", "Kilidi aç" düğmesi; otomatik Face ID
  istemi açılışta bir kez.
- Widget'lar ve kontroller kilitliyken de görünür; tutarları gizleme seçeneği widget
  ayarında (§4).

## 3. Dışa / içe aktarma (T5.3 — REQ-X4)
### 3.1 Dışa aktarma
- **CSV** (işlemler; Excel/Numbers): tarih, tür, tutar, para birimi, hesap, kategori,
  alt kategori, satıcı, not, durum. Ondalık ayırıcı ve alan ayırıcı yerel ayara göre
  (tr_TR: `;` ve `,`), UTF-8 BOM'lu (Excel Türkçe karakterleri bozmasın).
- **JSON** (tam yedek): hesaplar, kategoriler, işlemler, tekrarlar, bütçeler, alımlar,
  hedefler, alarmlar; sürüm alanı ile. Fiş görselleri dahil değil (boyut).
- Paylaş sayfası ile (Dosyalar, AirDrop, Mail); macOS'ta kaydet paneli.
### 3.2 İçe aktarma
- **JSON yedeği geri yükleme:** boş depoya tam; dolu depoya "birleştir" (aynı kimlik
  atlanır) ya da "değiştir" (onaylı, önce otomatik yedek alınır).
- **CSV (banka ekstresi):** dosya seç → önizleme (ilk 10 satır) → sütun eşleme (tarih,
  tutar, açıklama zorunlu; tür/kategori opsiyonel) → tarih biçimi ve ondalık ayırıcı
  otomatik tahmin, değiştirilebilir → hedef hesap → **taslak** olarak içe al (C5);
  kategoriler satıcı öğrenmesiyle (REQ-L5) önerilir.
- Aynı satır iki kez içe alınmaz (tarih + tutar + açıklama ile tekrar kontrolü; "12 satır
  zaten var, atlandı").

## 4. Widget'lar, kontroller, menü çubuğu (T5.4 — REQ-X5, X8, X9)
- **Küçük:** gram altın (seçilebilir varlık) fiyatı + günlük değişim + "az önce".
- **Orta:** birikim toplamı, kâr/zarar, en büyük 3 pozisyon.
- **Bütçe (küçük/orta):** bugün harcayabileceğin, ay ilerleme çubuğu.
- **Kilit ekranı:** dairesel (bütçe yüzdesi), satır içi (gram altın), dikdörtgen
  (bugün harcayabileceğin).
- Tüm rendering modları (tam renk, vurgulu, şeffaf); `.widgetAccentable()`; StandBy.
- Fiyatlar widget'ta da yenilenir: zaman çizelgesi 30 dk; eski fiyat "2 sa önce" der.
- Widget ayarı: "Tutarları gizle" (bütçe ve birikim widget'ları için).
- **Denetim Merkezi / kilit ekranı / Eylem Butonu:** "Harcama ekle" (hızlı ekleme açılır),
  "Fiş tara" (kamera açılır). `ControlWidget` + `OpenIntent`.
- **macOS menü çubuğu** (`MenuBarExtra`): gram altın + USD canlı; açılınca 4 fiyat, bugün
  harcayabileceğin, "Harcama ekle…", "Fiş içe aktar…", "Kumbara'yı aç". Ayarlardan
  kapatılabilir.

## 5. Reel getiri (T5.5 — REQ-P7, 03 §4)
- Pozisyon ve portföy ayrıntısında "Gerçekte ne kazandın" bölümü:
  - **Dolar karşısında:** aynı tarihlerde aynı TL ile USD alsaydın bugün kaç TL olurdu
    (alım anındaki `usdTRYAtTrade` zaten kayıtlı). "Altın dolardan %18 iyi gitti."
  - **Enflasyon karşısında:** TÜFE ile düzeltilmiş getiri. "Fiyatlar %31 arttı; birikimin
    %12 reel kazandı."
- TÜFE kaynağı: aylık TÜİK endeksi, **uygulamaya gömülü tablo** (anahtar gerektiren EVDS
  yerine); her uygulama güncellemesiyle yenilenir, tablonun son ayı ekranda yazar
  ("TÜFE: Ekim 2026'ya kadar"). Son aydan sonrası için tahmin yapılmaz, söylenir.
- Kısa süreli pozisyonda (< 1 ay) TÜFE karşılaştırması gösterilmez.

## 6. Hedefler ve birikime ayırma (T5.6 — REQ-P9, P10)
- **Hedef:** ad, tür (varlık miktarı "20 çeyrek" | TL tutarı "₺500.000"), opsiyonel
  tarih. İlerleme halkası, kalan, tarih varsa "ayda ₺X / 2 çeyrek ayırırsan yetişir".
- **Hangi birikim sayılır:** alım kaydında "Hedef" seçilir (varsayılan yok); hedefe atanmış
  alımların bugünkü değeri (TL hedefte) ya da miktarı (varlık hedefinde) ilerlemedir.
  Varlık hedefinde, aynı varlıktan hedefsiz pozisyon varsa "Elinde atanmamış 6 çeyrek
  daha var, ekle?" önerilir.
- **Birikime ayır (REQ-P10):** gelir kaydedilince bir kez "Bunun bir kısmını birikime
  ayıralım mı?" satırı (kapatılabilir): yüzde ya da tutar → varlık seç → alım editörü
  tutarı ve güncel fiyatla dolu açılır; kullanıcı onaylar (C5). Tutar gelir hesabından
  düşer (transfer değil; alım kaydı hesabı borçlandırır).
- Birikim sekmesinde en üstte hedefler (varsa), altında pozisyonlar.

## 7. Yerelleştirme, erişilebilirlik, ikon, mağaza (T5.7 — REQ-X6, X7)
- **İngilizce:** String Catalog (`Localizable.xcstrings`), tüm arayüz metni; kategori
  tohumları ve fiş anahtar sözcükleri dil başına. Sayı/para/tarih biçimi sistemden.
- **Erişilebilirlik denetimi:** her ekranda VoiceOver sırası ve etiketleri, Dynamic Type
  AX5'e kadar (kahraman rakamlar küçülür, kırpılmaz), Kontrast Artır, Hareketi Azalt,
  kâr/zarar ▲▼ ve işaretle. UI testlerine erişilebilirlik denetimi (`performAccessibilityAudit`).
- **İkon:** Icon Composer ile çok katmanlı Liquid Glass ikonu (06 §8): açık, koyu, şeffaf,
  renklendirilmiş varyantlar.
- **Mağaza:** TR + EN metin, 6.9" iPhone ve Mac ekran görüntüleri (mevcut ekran
  görüntüsü testinden), gizlilik etiketi "Veri toplanmaz", destek sayfası.

## 8. Sıra
1. §0 depo taşıma → 2. T5.3 dışa/içe aktarma (veri güvencesi önce) → 3. T5.2 kilit →
4. T5.6 hedefler → 5. T5.5 reel getiri → 6. T5.4 widget/kontrol/menü çubuğu →
7. T5.1 iCloud (Team ID ile) → 8. T5.7 yerelleştirme, erişilebilirlik, ikon, mağaza.

## 9. Kabul ölçütleri
- **AC-X3-1** Kilit açık, "1 dk": 30 sn arka planda kalıp dönünce kilit sorulmaz; 2 dk
  sonra sorulur. Uygulama değiştiricide tutarlar hiçbir zaman okunmaz.
- **AC-X4-1** 50 işlem CSV'ye aktarılıp boş depoya içe alınınca 50 taslak oluşur, toplamlar
  kuruşu kuruşuna aynı; ikinci içe alımda "50 satır zaten var" ve yeni kayıt yok.
- **AC-X4-2** JSON yedeği boş depoya geri yüklenince özet, bütçe ve birikim ekranları
  yedek alınan cihazdakiyle aynı.
- **AC-P7-1** 1 Ocak'ta ₺10.000 ile gram altın (USD/TRY 35) alındı; bugün USD/TRY 50: dolar
  karşılaştırması ₺14.285,71 üzerinden yapılır.
- **AC-P9-1** "20 çeyrek" hedefi, hedefe atanmış 8 çeyrek → %40, "12 çeyrek kaldı".
- **AC-X5-1** Widget vurgulu ve şeffaf modlarda okunur; kilit ekranında tutar gizleme
  açıkken tutar yerine "•••".

## 10. Karar bekleyenler
- **R1** Reel getiride TÜFE: gömülü tablo (öneri) mi, kullanıcının elle güncellediği tablo mu?
- **R2** Hedefe sayılan birikim: alıma hedef atama (öneri) mi, varlığın tamamı mı?
- **R3** CSV içe aktarmada banka hazır şablonları (Garanti, İş, Yapı Kredi, Akbank, Ziraat)
  v1'de olsun mu, yoksa yalnız genel sütun eşleme mi (öneri: genel, şablonlar v1.x)?
- **R4** Kilitte uygulamaya özel parola (Face ID'siz cihazlar / paylaşılan iPad) gerekli mi?
  Öneri: hayır, cihaz parolası yeterli.
- **Q9** Uygulama adı, **Q10** Team ID: iCloud, cihaz testi ve mağaza için gerekli.
