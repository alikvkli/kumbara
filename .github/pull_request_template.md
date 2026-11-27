## Ne değişti

<!-- Kısa açıklama -->

## Spec referansı

<!-- Bu PR hangi maddeleri karşılıyor? Örn: REQ-L4, T1.3. Spec değiştiyse hangi dosya? -->

## Test

- [ ] Core birim testleri eklendi/güncellendi (`swift test --package-path Packages/KumbaraCore`)
- [ ] Kabul senaryosu (AC-…) doğrulandı veya UI testi eklendi

## Arayüz kabulü (specs/06 §11) — arayüz değiştiyse zorunlu

- [ ] iOS 27 ve iOS 26 simülatörü, açık + koyu ekran görüntüsü
- [ ] macOS 27, en dar ve en geniş pencere
- [ ] Liquid Glass şeffaflık çubuğu iki uçta okunabilir
- [ ] Şeffaflığı Azalt · Karşıtlığı Artır · Hareketi Azalt
- [ ] Dynamic Type XXL ve AX3, VoiceOver
- [ ] macOS: tüm akış klavyeyle

## Yasak listesi (specs/06 §9)

- [ ] İçerikte cam yok (kart, satır, özet kutusu)
- [ ] Cam üstüne cam yok; yan yana camlar `GlassEffectContainer` içinde
- [ ] Özel tab bar / navigation bar / pencere kromu / elle blur yok
- [ ] Dekoratif gradyan, emoji ikon, kart içinde kart yok
- [ ] Sabit köşe yarıçapı yok (eşmerkezli şekil)
- [ ] Ekranda en fazla bir `.glassProminent`
- [ ] Sayaç animasyonu, yanıp sönen fiyat, rozet yağmuru yok

## Ekran görüntüleri

<!-- açık / koyu, iOS / macOS -->
