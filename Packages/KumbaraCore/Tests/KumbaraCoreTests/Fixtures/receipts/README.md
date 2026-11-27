# Yakalama test korpusu (specs/04 §6)

Her dosya bir belgenin OCR çıktısıdır: `lines` = `[metin, x, y, güven]` (normalize, sol üst
orijin; yükseklik ve genişlik test yükleyicisinde tahmin edilir) ve beklenen sonuç `expect`.

**Şu an hepsi `"source": "synthetic"`**: Türk fiş, e-arşiv fatura, banka listesi ve SMS
biçimleri taklit edilerek elle yazıldı. Gerçek korpus (hedef ≥ 40, T3.1) uygulamadaki
"OCR çıktısını dışa aktar" aracıyla gerçek fişlerden toplanacak; o dosyalar
`"source": "device"` olur ve kişisel bilgiler (kart no, ad, adres) çıkarılarak eklenir.
