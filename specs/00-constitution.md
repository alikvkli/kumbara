# 00 — Anayasa (Değişmez İlkeler)

Bu ilkeler her spec ve her PR için geçerlidir. Bir ilkeyle çelişen öneri, önce bu
dokümanın değiştirilmesini gerektirir.

## C1 — Sunucu yok
- Kumbara'nın kendine ait bir backend'i, hesabı, analitiği **yoktur**.
- Tüm veri cihazda tutulur. Cihazlar arası eşitleme yalnızca kullanıcının **kendi
  iCloud özel veritabanı** (CloudKit private DB) üzerinden ve **isteğe bağlı** olur.
- Dışarıya giden tek trafik: herkese açık, anahtarsız piyasa verisi uç noktaları
  (bkz. 02). Bu isteklerde kullanıcıya ait hiçbir bilgi (portföy, miktar, kimlik)
  gönderilmez.

## C2 — Mahremiyet
- OCR ve metin ayrıştırma tamamen cihaz üzerinde yapılır (Apple Vision, opsiyonel
  Apple Foundation Models). Görüntü cihazdan çıkmaz.
- Üçüncü parti SDK (analitik, reklam, crash reporting) eklenmez.
- Uygulama kilidi (Face ID / Touch ID) bulunur.

## C3 — Para bir kayan nokta değildir
- Tüm tutarlar `Decimal` ile tutulur, `Double` sadece grafik çiziminde kullanılır.
- Her tutar bir para birimi / varlık birimi ile birlikte saklanır (`Money`,
  `Quantity`). Birimsiz sayı kalıcı katmana yazılmaz.
- Yuvarlama yalnızca gösterimde yapılır; hesaplama tam hassasiyetle yapılır.

## C4 — Önce çevrimdışı
- Uygulama ağ olmadan tamamen kullanılabilir. Fiyatlar son bilinen değerle ve
  **zaman damgası açıkça görünerek** gösterilir ("14:05 itibarıyla").
- Fiyat bayatsa (bkz. 02 §Bayatlık) bu durum arayüzde belirtilir; hiçbir zaman
  bayat fiyat güncelmiş gibi gösterilmez.

## C5 — Kullanıcı verisinin sahibi kullanıcıdır
- CSV/JSON dışa aktarma ve içe aktarma ilk sürümden itibaren vardır.
- Otomatik oluşturulan hiçbir kayıt (OCR, tekrarlayan işlem) kullanıcı onayı
  olmadan kesinleşmez; "taslak" olarak bekler.

## C6 — Dürüst arayüz
- Tasarım kuralları 06'da tanımlıdır. Süs için gradyan, cam efekti, emoji, rastgele
  illüstrasyon yoktur. Renk anlam taşır (kâr/zarar, uyarı), dekor değildir.
- Kâr/zarar her zaman **hangi fiyatla** hesaplandığını söyler (alış/satış makası).

## C7 — Test edilebilir çekirdek
- İş kuralları (para, portföy matematiği, OCR metin ayrıştırma, fiyat sağlayıcı
  ayrıştırma) UI ve Apple framework'lerinden bağımsız saf Swift paketi
  `KumbaraCore` içindedir ve birim testleriyle kapsanır.
- Her `REQ-…` maddesinin en az bir testi veya manuel kabul senaryosu vardır.
