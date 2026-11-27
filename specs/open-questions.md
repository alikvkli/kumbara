# Açık Sorular

Spec onaylanmadan önce cevaplanması gerekenler. Cevaplanan sorular ilgili spec'e
işlenip buradan silinir.

| # | Soru | Önerim |
|---|---|---|
| Q1 | Minimum OS sürümü? | **iOS 26 / macOS 26.** Foundation Models, yeni Vision Swift API ve Liquid Glass sistem bileşenleri için. iOS 18'e inmek ~%15 daha fazla kullanıcı ama akıllı OCR katmanı kaybolur. |
| Q2 | iCloud eşitleme v1'de olsun mu? | Evet, opsiyonel ve kapalı başlasın. Mac ↔ iPhone kullanımının temel şartı. |
| Q3 | TÜFE verisi nasıl gelsin? | Uygulamayla gelen tablo + elle ekleme. Alternatif: kullanıcı kendi TCMB EVDS anahtarını girerse otomatik çekilsin. |
| Q4 | BIST hisse / yatırım fonu? | v1'de "serbest varlık" (elle fiyat). TEFAS fon fiyatları için ücretsiz bir uç nokta araştırılacak; yahoo benzeri resmî olmayan kaynaklar kırılgan olduğu için önermiyorum. |
| Q5 | Uygulama ücretli mi, tek seferlik mi, ücretsiz mi? | Backend maliyeti olmadığı için tek seferlik ücret veya tamamen ücretsiz. Abonelik önermiyorum. |
| Q6 | Kâr/zararda varsayılan fiyat "bozdurma (alış)" olsun mu? | Evet (REQ-P4). En dürüst rakam bu; bazı uygulamalar satış fiyatı göstererek kârı şişirir. |
| Q7 | Ortalama maliyet mi FIFO mu varsayılan? | Ağırlıklı ortalama (03 §2). |
| Q8 | Dil: yalnız Türkçe mi, Türkçe + İngilizce mi? | İkisi; kod ve spec kimlikleri İngilizce, arayüz metni String Catalog ile. |
| Q9 | Uygulama adı "Kumbara" kesin mi? App Store'da çakışma kontrolü yapılacak. | — |
| Q10 | Apple Developer hesabı ve bundle ID? CloudKit container adı buna bağlı. | — |
