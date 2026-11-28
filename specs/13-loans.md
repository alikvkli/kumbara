# 13 — Kredi takibi

Durum: **taslak, uygulandı; kararlar onay bekliyor** (2026-11-28). Kapsam: REQ-I10 (yeni).
İlkeler değişmez: her şey cihazda (C1), sunucu yok (C2), `Decimal` (C3), onaysız kayıt
yok (C5), dürüst arayüz (C6). Hesaplar KumbaraCore'da saf fonksiyon (`Ledger/Loan.swift`),
Linux'ta test edilir.

## 1. Amaç
İhtiyaç, taşıt ve konut kredisinin ödeme planını tutmak:
- kalan anaparayı ve sıradaki taksiti göstermek,
- ödenen taksiti deftere yazmak,
- erken kapamanın bugün kaça mal olacağını ve ne kazandıracağını göstermek.

Taksitler ödeme takvimine düşer. Banka sözleşmesindeki plan esastır; Kumbara'nın planı bir
tahmindir ve ekranda öyle anlatılır.

## 2. Kurallar
**Eşit taksit (anüite).**
- Taksit formülü: `P × r_e / (1 − (1 + r_e)^−n)`, kuruşa yuvarlanır.
  - `r_e = r × (1 + v)` vergi dahil efektif aylık orandır.
  - `r` aylık akdi faizdir; `v` faiz üzerinden alınan vergidir.
- Her satırda faiz kalan anaparanın `r` katıdır, vergi faizin `v` katıdır; ikisi de kuruşa yuvarlanır.
- Anapara payı, taksitten faiz ve vergi düşülerek bulunur.
- Son taksit kalan anaparayı kapatır, bu yüzden kuruş farkıyla değişebilir.
- Vadeler ilk taksit gününden itibaren her ay aynı gündür. Kısa ayda ayın son günü kullanılır, sonraki vadeler kaymaz.
- İlk dönemin gün sayısına göre farklı hesaplanan ilk taksit modellenmez (karar L5).

**Vergi.**
- İhtiyaç ve taşıt kredisinde faize KKDF %15 ve BSMV %15 eklenir; varsayılan `v = 0,30`.
- Konut kredisi ikisinden de muaftır (`v = 0`).
- Oran formda değiştirilebilir, çünkü oranlar Cumhurbaşkanı kararıyla değişebilir.

**Taksitten faiz.** Kullanıcı çoğu zaman yalnız taksiti bilir.
- `r_e` ikiye bölme yöntemiyle 10⁻¹⁰ hassasiyetle bulunur, sonra `r = r_e / (1 + v)` alınır.
- Sonuç 6 basamağa yuvarlanır.
- Taksit, tutarın vadeye bölümünden küçükse sonuç `nil` olur ve formda açıklanır.
- Bankanın taksiti saklanır, plan o taksitle kurulur (kuruş farkı olmasın).

**Erken kapama** (6502 s. Kanun m.37; Konut Finansmanı Sözleşmeleri Yönetmeliği):
- Tutar şunların toplamıdır:
  - kalan anapara,
  - işlemiş faiz: kalan anapara × r × gün / 30; gün, son vadeden (ilk taksitten önceyse ilk vadeden bir ay önceden) bugüne, en çok 30,
  - işlemiş faizin vergisi,
  - tazminat.
- **Tazminat** yalnız sabit faizli konut kredisinde alınır:
  - kalan vade ≤ 36 ay ise kalan anaparanın %1'i,
  - kalan vade > 36 ay ise %2'si,
  - en çok yapılacak faiz indirimi kadar.
- Tüketici kredisinde (ihtiyaç, taşıt) ve değişken faizli konut kredisinde tazminat yoktur.
- "Daha az ödersin" farkı: kalan taksitlerin toplamı eksi kapama tutarı.
- Ekranda "kesin tutarı bankandan iste" notu yer alır.

Kaynaklar (2026-11-28'de bakıldı):
- 6502 s. Tüketicinin Korunması Hakkında Kanun m.37, Konut Finansmanı Sözleşmeleri Yönetmeliği (tazminat %1 / %2, 36 ay; değişken faizde yok): ticaret.gov.tr "Erken ödemeye ilişkin belirsizlik ortadan kalkıyor"; lawinsider.com yönetmelik metni; hukukcularevi.com (Eylül 2026).
- Tüketici kredisinde tazminat yok, yalnız faiz indirimi (m.37): aynı kaynaklar.
- İhtiyaç kredisinde KKDF %15 ve BSMV %15 (faiz üzerinden): yapikredi.com.tr ürün ücretleri sayfasında oranlar "KKDF ve BSMV hariç" gösteriliyor; takvim.com.tr, hemenhesap.com ve muhasebenews.com hesaplama sayfaları. Resmî Gazete metni bu aramada doğrudan bulunamadı; oran bu yüzden formda değiştirilebilir.

## 3. Ekran
**Özet › Krediler**
- Toplam kalan anapara ve aylık taksitler toplamı.
- Açık krediler; her satırda "5 / 12 taksit · sıradaki 5 Aralık" ve taksit. Vadesi geçmişse turuncu.
- Kapanan krediler ayrı bölümde.
- Boş durumda tek bir "Kredi ekle" düğmesi.

**Kredi ekranı**
- Kalan anapara ve ilerleme.
- **Sıradaki taksit:** faiz, vergi ve anapara kırılımıyla.
  - "Ödendi" iki seçenek sunar: "<hesap> hesabından", taksiti gider olarak yazar; "Deftere yazmadan işaretle".
  - "Son ödemeyi geri al".
- **Erken kapama:** kalem kalem tutar, "bugün kapatırsan ₺X daha az ödersin" ve "Erken kapattım".
  - "Erken kapattım" kapama tutarını gider yazar ya da yazmadan kapatır.
  - Kapanış geri alınabilir.
- Koşullar ve tam ödeme planı (ödenen satırlar işaretli).

**Form**
- Ad ve tür.
- Çekilen tutar ve vade (ay).
- "Bildiğin": taksit ya da aylık faiz.
- KKDF + BSMV oranı, konutta "değişken faizli" anahtarı.
- Canlı hesap: bulunan faiz (aylık, yıllık) ya da taksit; toplam geri ödeme; toplam faiz ve vergi.
- İlk taksit günü. "Ödenmiş taksit" geçmiş vadelerden önerilir ve değiştirilebilir.
- Ödeme hesabı (nakit/banka) ve kategori (varsayılan "Diğer").

**Ödeme takvimi.** Ödenmemiş taksitler `UpcomingPayment.Source.loan` olarak gösterilir.

**Hatırlatma.** Sıradaki vadeden 1 gün önce 10:00'da: "<ad> taksiti yarın · ₺… · 6. taksit / 12". Dokununca ödeme takvimi açılır.

**Yedek.** JSON yedeğinde `loans` alanı opsiyoneldir; eski yedekler okunur.

## 4. Kabul ölçütleri
- **AC-I10-1:** ₺100.000, aylık %3,49, vergi %30, 12 ay için taksit ₺10.989,84; toplam faiz ₺24.521,63, vergi ₺7.356,50; son taksit ₺10.989,89.
- **AC-I10-2:** Taksit ₺10.989,84 girilince aylık faiz %3,49 bulunur. Konut kredisinde ₺2.000.000, 120 ay, taksit ₺57.932,14 için %2,79 bulunur.
- **AC-I10-3:** Aynı krediyi 3 taksit sonra, 3. vadeden 15 gün sonra kapatmak ₺81.559,03 tutar:
  - anapara ₺79.749,90, faiz ₺1.391,64, vergi ₺417,49;
  - kalan 9 taksitten ₺17.349,58 daha azdır.
  - Sabit faizli konut kredisinde kalan vade 108 ayken tazminat %2, 24 ayken %1; değişken faizde 0.
- **AC-I10-4:** "Ödendi" seçilen hesaptan gider yazar ve bütçeye girer. Satıcı anahtarı boş kalır; kayıt aboneliklere ve hızlı ekleme önerilerine karışmaz. "Geri al" gideri siler. Uygulamaya eklenmeden önce ödenmiş sayılan taksitlerin kaydı yoktur.
- **AC-I10-5:** Taksit ödeme takviminde kendi gününde görünür. Kapanan kredi takvimden çıkar. Kredi yedekten aynen geri gelir.

## 5. Kararlar (kullanıcı onayı bekliyor)
| # | Karar |
|---|---|
| L1 | Ödenen taksit **gider** olarak yazılır ve bütçeye girer. Anapara payı da dahildir: aylık nakit çıkışı budur, "Alabilir miyim?" ve aylık rapor bunu görür. Kredinin çekildiği gün gelir ya da transfer yazılmaz. |
| L2 | "Ödendi" otomatik değil, kullanıcı dokununca yazılır (C5). Vadesinde taslak üretilmez; hatırlatma gelir. |
| L3 | Uygulamaya eklenmeden önce ödenmiş taksitler yalnız sayılır, deftere geriye dönük gider yazılmaz. |
| L4 | Kart ile ödeme seçeneği yok; ödeme hesabı nakit ya da banka. |
| L5 | İlk dönem tam ay sayılır. Bankalar ilk taksiti kullanım gününden itibaren gün sayısıyla hesapladığı için ilk taksit birkaç lira farklı olabilir; banka taksiti girilirse plan onunla kurulur. |
| L6 | Erken kapamada işlemiş faiz gün / 30 ile hesaplanır. Kısmi erken ödeme (ara ödeme) v1'de yok. |
| L7 | Kredi silinince deftere yazılmış taksit giderleri kalır, çünkü gerçekten ödendiler. |
| L8 | Taksit hatırlatmasına dokununca ödeme takvimi açılır; ayrı bir derin bağlantı eklenmedi. |
| L9 | Varsayılan kategori "Diğer". Yeni bir "Kredi" kategorisi eklenmedi; varsayılan set değişmesin diye. |
