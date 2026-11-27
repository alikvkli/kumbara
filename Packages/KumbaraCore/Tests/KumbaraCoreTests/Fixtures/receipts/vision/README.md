# Gerçek OCR çıktıları

Bu klasördeki dosyalar **gerçek Apple Vision OCR'ının** çıktısıdır (CI `[corpus]` işi,
`kumbara-ocr`). Kaynak alanı:

- `vision-synthetic`: `Tools/corpus/generate.py` ile üretilmiş görüntüler; doğru cevap üreticiden.
- `commons`: Wikimedia Commons'taki açık lisanslı gerçek fişler (`license`, `attribution`, `url`
  alanlarında). Bu dosyalar CC BY-SA 4.0 ile paylaşılır.
- `device`: kullanıcının cihazından "OCR çıktısını paylaş" ile gelen, kişisel bilgisi temizlenmiş fişler.

Doğruluk tek tek değil toplu ölçülür (specs/04 §6): tutar ≥ %95, tarih ≥ %90, satıcı ≥ %80.
