# 02 — Piyasa Verisi

Tüm kaynaklar 2026-11-27 tarihinde bu ortamdan canlı test edildi; anahtar
gerektirmiyor. Hiçbiri SLA vermez → tasarım **kaynak bağımsız** ve **yedekli**.

## 1. Kaynaklar

| ID | Kaynak | Uç nokta | Verdiği | Not |
|---|---|---|---|---|
| `truncgil` | Truncgil Finans | `https://finans.truncgil.com/v4/today.json` | Gram/has/çeyrek/yarım/tam/cumhuriyet/ata/reşat/gremse/beşli, 14/18/22 ayar, gümüş, platin, paladyum, ~40 döviz, alış+satış+değişim% | **Altın için birincil.** Kapalıçarşı tipi alış/satış makası verir. |
| `goldapi` | gold-api.com | `https://api.gold-api.com/price/{XAU,XAG,XPT}` | Ons fiyatı (USD) | Gram altın **türetmek** için yedek. |
| `tcmb` | TCMB | `https://www.tcmb.gov.tr/kurlar/today.xml` | Resmî döviz alış/satış (efektif + döviz) | Döviz için yedek; günde bir güncellenir. |
| `frankfurter` | Frankfurter (ECB) | `https://api.frankfurter.dev/v1/latest?base=USD` | Döviz orta kur, **tarihsel** | Geçmiş tarihli kur için (03 §4). |
| `coingecko` | CoinGecko | `https://api.coingecko.com/api/v3/simple/price?ids=…&vs_currencies=try,usd` | Kripto | Kripto için birincil; ~30 istek/dk sınırı. |

Doğrulama örneği (aynı dakika): `goldapi` XAU = 3.627 USD, `truncgil` USD satış
= 50,79 → türetilmiş gram = 3627 / 31,1035 × 50,79 ≈ **5.922 ₺**;
`truncgil` GRA satış = **5.926 ₺**. Türetme yedek olarak güvenilir.

## 2. Sağlayıcı soyutlaması

```swift
protocol PriceProvider: Sendable {
    var id: ProviderID { get }
    var supported: Set<AssetCode> { get }
    func fetch(_ assets: Set<AssetCode>) async throws -> [Quote]
}

struct Quote: Sendable, Hashable {
    let asset: AssetCode          // .gramGold, .quarterGold, .fx("USD"), .crypto("bitcoin")
    let bid: Decimal?             // kuyumcu/banka ALIŞ  = senin bozdurma fiyatın
    let ask: Decimal?             // kuyumcu/banka SATIŞ = senin alım fiyatın
    let mid: Decimal              // (bid+ask)/2, yalnız tek fiyat varsa = o fiyat
    let quoteCurrency: CurrencyCode  // TRY
    let asOf: Date                // kaynağın bildirdiği zaman (yoksa çekim zamanı)
    let source: ProviderID
    let derived: Bool             // türetilmiş mi (ör. ons→gram)
}
```

Sağlayıcı ayrıştırıcıları `KumbaraCore` içinde saf fonksiyondur; ağ katmanı
ayrıdır. Testler gerçek yanıtlardan alınmış fixture JSON/XML dosyalarıyla yazılır.

## 3. Yedekleme zinciri (REQ-M1)

| Varlık grubu | Sıra |
|---|---|
| Altın türleri, gümüş, platin | `truncgil` → türetme(`goldapi` × USD/TRY) |
| Döviz | `truncgil` → `tcmb` → `frankfurter` |
| Kripto | `coingecko` → (yok: son bilinen) |
| Serbest varlık | Kullanıcının girdiği son fiyat |

- Her sağlayıcıya 10 sn zaman aşımı. Bir sağlayıcı 3 kez üst üste hata verirse
  15 dk "devre kesici" ile atlanır.
- **Türetilmiş çeyrek/yarım/tam altın yoktur**: bunlar ziynet olup gram fiyatına
  sabit katsayıyla bağlanmaz (işçilik/makas). Truncgil yoksa son bilinen fiyat +
  bayat etiketi gösterilir. Sadece gram, has, gümüş, platin türetilebilir.
- Türetilmiş fiyatta makas bilinmediği için `bid = ask = mid` ve arayüzde
  "yaklaşık" etiketi bulunur.

## 4. Akla yatkınlık kontrolü
Gelen fiyat, son bilinen fiyattan %15'ten fazla saparsa (ve son fiyat < 24 saat
ise) kabul edilmeden ikinci kaynakla karşılaştırılır; ikinci kaynak doğrulamazsa
reddedilir ve log'a yazılır. `0` veya negatif değerler geçersizdir (Truncgil bazı
alanlarda `0` dönüyor: `ONS`, `BRENT` — bunlar "veri yok" kabul edilir).

## 5. Yenileme ve bayatlık
- Ön planda: 60 sn'de bir (yalnız portföy/fiyat ekranı görünürken), ekran
  açılışında ve pull-to-refresh'te.
- Arka planda: `BGAppRefreshTask` (iOS), macOS'ta uygulama açıkken zamanlayıcı.
- Bayatlık: hafta içi 09:00–18:00 arası > 15 dk → "gecikmeli", > 24 saat →
  "bayat" etiketi. Hafta sonu piyasa kapalı olduğundan eşik 72 saat.

## 6. Yerel fiyat geçmişi (REQ-P8)
Ücretsiz kaynakların çoğu geçmiş vermez. Bu yüzden her başarılı çekimde
**varlık başına günde en fazla 1 kapanış + 1 son değer** yerel olarak saklanır
(`PriceSnapshot`). Grafikler bu veriden çizilir; uygulamanın kurulumundan önceki
dönem için grafik, kullanıcının işlem fiyatlarından (alım noktaları) oluşur.
Döviz için `frankfurter` tarihsel uç noktası ile geçmiş doldurulabilir.

## 7. Kullanım koşulları
Truncgil ve CoinGecko'nun kullanım şartları yayın öncesi yeniden okunacak; uygulama
içi "Veri kaynakları" ekranında kaynaklar listelenip atıf verilecek. İstekler
cihaz başına ve seyrek olduğundan yük düşüktür. User-Agent genel bir değer
(`Kumbara/1.0`) olur; kullanıcıya ait bilgi taşımaz (C1).
