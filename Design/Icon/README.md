# Uygulama ikonu

**Konsept:** Kumbaranın yuvasına giren altın sikke. Hem "biriktirme" hem de
uygulamanın altın/birikim takibini tek görüntüde anlatır. Düz petrol yeşili zemin,
geometrik formlar; metin, gradyan, emoji yok (specs/06 §8).

| Dosya | Ne |
|---|---|
| `layers/coin.svg`, `layers/body.svg` | Kaynak katmanlar (1024×1024 pt tuval) |
| `../../App/Resources/AppIcon.icon` | Icon Composer paketi: iki cam katman, düz zemin. Xcode bunu derler. |
| `export/*.png` | Önizleme ve yedek düz PNG'ler (açık, koyu, renklendirilmiş) |
| `compose.html` | Katmanları tarayıcıda birleştirip PNG üretmek için |

Renkler: zemin `#1F5E5B` (AccentColor), gövde `#F4EFE4`, yuva `#123F3D`,
sikke `#E2B13C` / halka `#B8862A`.

Reddedilen denemeler: sikke gövdenin üstünde tam daire olarak durduğunda
figür "baş + omuz" gibi okunuyordu; sikkeyi yuvaya gömmek bunu çözdü.

Icon Composer'da açıp kırılma (refraction) ve koyu/şeffaf varyant ince ayarı
bir Mac'te yapılabilir; katman yapısı buna hazır.
