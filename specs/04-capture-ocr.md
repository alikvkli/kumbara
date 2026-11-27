# 04 — Yakalama ve OCR

Amaç: kullanıcı bir görüntü verir → uygulama bir veya birkaç **taslak işlem**
önerir → kullanıcı onaylar. Tümü cihaz üzerinde (C2).

## 1. Giriş noktaları (REQ-C1, C2, C7)
| Giriş | iOS | macOS | API |
|---|---|---|---|
| Kamera ile fiş | ✓ | — | `VNDocumentCameraViewController` (kenar tespiti, perspektif düzeltme) |
| Canlı tarama (tutar vurgulama) | ✓ | — | `DataScannerViewController` (VisionKit) — v1.1 |
| Fotoğraf / ekran görüntüsü seç | ✓ | ✓ | `PhotosPicker` |
| Sürükle-bırak, yapıştır (⌘V) | iPad | ✓ | `Transferable` |
| Paylaş menüsü | ✓ | ✓ | Share Extension → App Group'taki gelen kutusuna yazar |
| PDF (e-fatura, e-arşiv) | ✓ | ✓ | `PDFKit` metin katmanı; yoksa sayfayı rasterleyip OCR |
| Kestirmeler | ✓ | ✓ | App Intents: `AddExpenseIntent`, `ScanImageIntent` |

## 2. Hat (pipeline)
```
Görüntü ─▶ OCR (Vision) ─▶ [TextLine] ─▶ Belge sınıflandırıcı ─▶ Ayrıştırıcı ─▶ [DraftTransaction]
                                         (fiş | banka listesi |
                                          bildirim | bilinmeyen)
```

1. **OCR:** `RecognizeTextRequest` (Vision, Swift API), `recognitionLevel =
   .accurate`, `recognitionLanguages = ["tr-TR", "en-US"]`, dil düzeltme açık.
   Çıktı: satır metni + bounding box + güven. Satırlar y-koordinatına göre
   gruplanır (aynı satırdaki sol etiket / sağ tutar eşleşmesi için).
2. **Sınıflandırma** (kural tabanlı, `KumbaraCore`):
   - *Fiş:* "TOPLAM", "KDV", "FİŞ NO", "Z NO", "TARİH … SAAT" anahtarları.
   - *Banka hareket listesi:* aynı sütun hizasında ≥3 tarih + tutar satırı.
   - *Bildirim/SMS:* "harcama yapılmıştır", "kartınızdan", "TL tutarında".
3. **Ayrıştırma** — saf Swift, `[TextLine]` girer, `[DraftTransaction]` çıkar:
   - **Tutar:** Türk biçimi `1.249,90`, `1249,90`, `*1.249,90`, `1.249,90 TL`, `₺1.249,90`;
     ayrıca İngilizce biçim `1,249.90` (ondalık ayırıcı = son ayırıcı ve sonrası 2 hane).
     Öncelik: "GENEL TOPLAM" > "TOPLAM" > "ÖDENECEK" > "TUTAR" satırının sağındaki
     sayı; "KDV", "ARA TOPLAM", "PARA ÜSTÜ", "NAKİT" satırları dışlanır.
     Yedek: en büyük tutar (güven düşük).
   - **Tarih:** `dd.MM.yyyy`, `dd/MM/yyyy`, `dd-MM-yy`, "27 Kasım 2026". Gelecek
     tarih veya > 1 yıl öncesi → güven düşük. Yoksa bugünün tarihi (güven düşük).
   - **Satıcı:** fişin ilk 3 satırından en uzun büyük harfli satır; bilinen
     zincir sözlüğü (Migros, BİM, A101, ŞOK, CarrefourSA, Shell, Opet, …) ile
     bulanık eşleme. Unvan ekleri ("A.Ş.", "TİC. LTD. ŞTİ.") temizlenir.
   - **Para birimi:** TL/₺ varsayılan; `$`, `USD`, `€`, `EUR` görülürse o.
   - **KDV:** "KDV" / "TOPKDV" satırı (bilgi amaçlı).
4. **Kategori önerisi:** (a) kullanıcının satıcı→kategori geçmişi (REQ-L6),
   (b) yerleşik zincir→kategori sözlüğü, (c) anahtar kelime (AKARYAKIT → Ulaşım).
5. **Opsiyonel akıllı katman:** Cihaz Apple Intelligence destekliyorsa
   Foundation Models framework ile `@Generable` bir `DraftTransaction` şeması
   doldurulur; sonuç kural tabanlı ayrıştırıcıyla çapraz kontrol edilir (tutar
   eşleşmezse kural tabanlı kazanır ve güven düşer). Desteklemeyen cihazda
   tamamen kural tabanlı çalışır. Yine tamamen cihaz üstüdür (C2).
   Uygulama (T3.7, `CrossCheck`): modele görüntü değil yalnız OCR metni verilir.
   Modelin hiçbir değeri fiş metninde karşılığı yoksa kullanılmaz (uydurma engeli).
   Anlaşma → güven artar; tutar/tarih çatışması → kural kalır, güven < 0,6 ve
   onay ekranı "iki okuma uyuşmadı" der; kuralların bulamadığı alanı metinde
   doğrulanan model değeri doldurur. Bilinen zincir satıcısına model dokunmaz.
   En fazla 5 sn beklenir; Ayarlar › Fiş okuma › Akıllı kontrol ile kapatılabilir.

## 3. Güven ve onay (REQ-C4)
Her alan `Confidence` (0–1) taşır. Onay ekranı:
- Görüntü üstte, tespit edilen kutu (tutar/tarih/satıcı) **görüntü üzerinde
  çerçeveyle** gösterilir — kullanıcı neyin neden seçildiğini görür.
- < 0,6 güvenli alan uyarı rengiyle işaretlenir ve odak oraya gider.
- Görüntüdeki başka bir sayıya dokunmak o alanı onunla değiştirir.
- Çoklu taslakta (banka listesi) satır satır onay / hepsini onayla.

## 4. Mükerrer kontrolü (REQ-C6)
Aynı hesap, |Δtutar| < 0,01, |Δtarih| ≤ 1 gün ve satıcı benzerliği > 0,8 →
"olası mükerrer" rozeti; kullanıcı yine de kaydedebilir.

## 5. Saklama
Fiş görüntüsü opsiyonel olarak işleme eklenir; HEIC, uzun kenar 2000 px'e
küçültülür. Ayarlardan "fiş görüntülerini sakla" kapatılabilir.

## 6. Test korpusu
`Tests/Fixtures/receipts/*.json`: gerçek fişlerden alınmış **OCR çıktıları**
(görüntü değil, satır + kutu), beklenen sonuçla birlikte. Hedef: v1'de ≥ 40 örnek
(market, akaryakıt, restoran, eczane, e-arşiv PDF, 4 farklı banka ekran görüntüsü,
SMS ekran görüntüsü). Başarı ölçütü: tutar doğruluğu ≥ %95, tarih ≥ %90,
satıcı ≥ %80. Ayrıştırıcı Linux'ta da test edilebilir (Vision bağımlılığı yok).
