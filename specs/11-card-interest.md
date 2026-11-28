# 11 — Kredi Kartı Faiz Hesabı (M7)

Durum: **taslak, uygulandı; kullanıcı onayı bekliyor** (2026-11-28). Kapsam: REQ-I8 (yeni).
İlkeler değişmez: cihazda (C1), sunucu yok (C2), `Decimal` (C3), kayıt oluşturmaz (C5), dürüst arayüz
ve tavsiye yok (C6). Yeni ağ isteği, izin ya da şema değişikliği yok.

## 1. Amaç
Ekstre borcu olan kartta "Asgariyi ödersen ne olur?" sorusunu rakamla yanıtlamak: gelecek ekstreye
eklenecek faiz ve vergi, ve hep asgari ödenirse borcun kaç ayda, kaç lira maliyetle kapanacağı.

## 2. Kurallar ve oranlar
- **Azami faiz (TCMB):** aylık, dönem borcu dilimine göre. Uygulamayla gelen tablo
  (`CardInterestRates.history`), tarihe göre seçilir; her sürümde güncellenir.

  | Geçerlilik | ≤ ₺30.000 | ₺30.000–180.000 | > ₺180.000 |
  |---|---|---|---|
  | 1 Aralık 2026 → | akdi %3,08 · gecikme %3,38 | %3,58 · %3,88 | %4,08 · %4,38* |
  | → 30 Kasım 2026 | %3,25 · %3,55 | %3,75 · %4,05 | %4,25 · %4,55 |

  Kaynak: TCMB "Kredi Kartı İşlemlerinde Uygulanacak Azami Faiz Oranları" (24 Kasım 2026
  duyurusu, haberlerden doğrulandı). *Son dilimin yeni gecikme oranı haberlerde geçmiyor; diğer
  dilimlerdeki 0,30 puanlık fark korunarak yazıldı, **TCMB sayfasından doğrulanmalı.**
  Kurumsal kart, nakit avans ve yabancı para kart kapsam dışı.
- **Vergi:** faizin %15'i KKDF + %15'i BSMV.
- **Asgari ödeme (BDDK, 1 Ekim 2026):** kart limiti ₺100.000 ve altı → dönem borcunun %20'si,
  üstü → %40. Hesaplarda limit alanı olmadığı için kullanıcı ekranda seçer (varsayılan %20).
- **Faiz:** asgari ya da fazlası ödenirse ödenmeyen kısma akdi faiz. Asgariden az ödenirse eksik
  kalan (asgari − ödenen) kısma gecikme faizi, geri kalana akdi faiz.
- **Kartın kendi oranı:** bankalar tavanın altında faiz alabilir; kullanıcı ekstredeki aylık
  akdi oranı yazarsa tavan yerine o kullanılır, gecikme oranı tavandaki farkla (0,30 puan) türetilir.

## 3. Hesap (`CardInterest`, KumbaraCore)
- `outcome(balance:payment:rule:rates:rate:)`: asgari, ödenmeyen, akdi/gecikme faizi, KKDF, BSMV,
  gelecek ekstreye devreden.
- `payoff(balance:plan:rule:rates:rate:)`: `.minimum` ya da `.fixed(tutar)` ile ay ay
  simülasyon → ay sayısı, toplam ödenen, toplam faiz ve vergi, kapanıyor mu (360 ay sınırı).
- Varsayımlar (ekranda yazar): iki ekstre arası 30 gün, yeni harcama yok, oranlar sabit, her adımda
  kuruşa yuvarlama. Kalan borç **₺100 ve altına** inince o ay tamamı ödenir (asgari kuyruğu sonsuza
  uzamasın).

## 4. Ekran (Özet › kart › "Asgari ödersen")
Yalnız TL kartta ve ödenmemiş ekstre varken; bağlantıda "+₺641 faiz".
- Üstte ekstre borcu, asgari, son ödeme; kesimden sonra ödeme yapıldıysa "₺X ödendi".
- **Gelecek ekstreye:** Tamamını ödersen (faiz yok) · Asgariyi ödersen (+faiz ve vergi) ·
  Ödeme yapmazsan (gecikme faizli; yalnız asgari henüz ödenmediyse).
- **Başka bir tutar:** yazılan tutara göre faiz, devreden; asgarinin altındaysa turuncu uyarı.
- **Hep böyle ödersen:** her ay asgari / her ay yazılan tutar → "23 ayda kapanır · ₺4.120 faiz ve vergi".
- **Oranlar:** kart limiti seçimi (asgari %20 / %40) ve kartın aylık akdi faizi; boşsa TCMB tavanı
  ve geçerlilik ayı yazar. Ayarlar kart kimliğine göre UserDefaults'ta (`card.interest`), şema ve
  yedek değişmez.

## 5. Kabul ölçütleri
- **AC-I8-1:** 28 Kasım 2026'da ≤ ₺30.000 dilimi %3,25; 5 Aralık 2026'da %3,08; ₺30.000,01 → %3,58.
  Limit ₺100.000 → %20, ₺100.001 → %40.
- **AC-I8-2:** ₺20.000 ekstre, Aralık 2026 oranı, asgari ₺4.000 ödenirse: akdi ₺492,80, KKDF ve
  BSMV ₺73,92'şer, toplam ₺640,64; devreden ₺16.640,64.
- **AC-I8-3:** Aynı ekstre hiç ödenmezse: gecikme ₺135,20 (₺4.000 × %3,38) + akdi ₺492,80; vergiyle ₺816,40.
- **AC-I8-4:** ₺1.000, asgari %40, kartın oranı %10: 7 ayda kapanır, toplam ₺1.218,72 ödenir, ₺218,72 maliyet.
- **AC-I8-5:** Tamamı ödenirse faiz yok; borçtan fazla yazılan tutar borçla sınırlanır.

## 6. Kart limiti (2026-11-28, kullanıcı onayı)
- Kart hesabında isteğe bağlı **limit** alanı (Ayarlar › Hesaplar). Yedekte (`creditLimit`), eski yedeklerde yok.
- **Kalan limit** = limit − bugünkü borç − planlı taksitler (taksitli alımda tutarın tamamı limitten
  düşer; ödenen taksit limiti açar). Kart ayrıntısında çubukla; eksiye düşerse turuncu "Limit ₺X aşıldı".
- Limit tanımlıysa asgari oran ondan seçilir (≤ ₺100.000 %20, üstü %40); "Asgari ödersen"
  ekranındaki elle seçim yalnız limit yokken görünür (F2 bununla kapanır).
- "Alabilir miyim?" kalan limiti kullanır: tutar kalan limiti aşarsa "Kart limiti bu tutara yetmiyor".
- Son ödeme günü geçmiş ama asgari ödenmişse kart "geçti" yerine "asgari ödendi" der; faiz ekranı
  yalnız ödenen tutarın sonucunu gösterir.

## 7. Kullanıcı onayına sunulan kararlar
- **F1:** Giriş yalnız kart ayrıntısında (Özet › kart). Ödeme takvimindeki kart satırına bağlantı eklenmedi.
- **F2:** Limit alanı hesaplara eklenmedi (şema değişmesin); asgari oranı ekranda seçiliyor.
- **F3:** Kartın oranı ve limit seçimi yedeğe girmiyor (UserDefaults).
- **F4:** ₺100 kapanış eşiği ve 30 günlük dönem varsayımı (bankalar faizi gün gün ve kesimden
  kesime hesaplar; sonuç "yaklaşık").
- **F5:** Son dilim gecikme faizi %4,38 doğrulanmadı (§2).
