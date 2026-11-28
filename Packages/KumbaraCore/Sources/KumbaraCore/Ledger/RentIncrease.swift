import Foundation

/// Kira artış sınırı (REQ-I9, specs/12).
///
/// TBK m.344: yenilenen kira yılında artış, **bir önceki kira yılında** TÜFE'nin on iki aylık
/// ortalamalara göre değişim oranını geçemez (konut ve işyeri aynı; %25 sınırı 1 Temmuz 2024'te
/// bitti). Uygulamada yenileme ayından bir önceki ayın oranı kullanılır: Aralık'ta yenilenen
/// kira için Kasım'ın oranı (TÜİK, 3 Aralık'ta açıklar).
///
/// On iki aylık ortalamalara göre değişim = (son 12 ayın endeks ortalaması) / (önceki 12 ayın
/// endeks ortalaması) − 1; TÜİK gibi yüzde olarak iki basamağa yuvarlanır. Gerekli aylardan biri
/// tabloda yoksa oran **hesaplanmaz**; eksik ay söylenir, tahmin edilmez.
public enum RentIncrease {
    public enum Role: String, Sendable, CaseIterable {
        case tenant, landlord
    }

    /// Yenileme ayı için kullanılacak TÜFE ayı.
    public static func referenceMonth(forRenewal month: LedgerMonth) -> LedgerMonth { month.previous }

    /// `month` için 12 aylık ortalamalara göre değişim (oran; 0,3203 = %32,03). Eksik ay varsa `nil`.
    public static func averageChange(for month: LedgerMonth, cpi: RealReturn.CPITable) -> Decimal? {
        var months: [LedgerMonth] = [month]
        for _ in 0..<23 { months.append(months[months.count - 1].previous) }
        let values = months.compactMap { cpi.index[$0] }
        guard values.count == 24 else { return nil }
        let recent = values[0..<12].reduce(0, +)
        let earlier = values[12..<24].reduce(0, +)
        guard earlier > 0 else { return nil }
        // Toplamların oranı = ortalamaların oranı.
        return (recent / earlier - 1).rounded(scale: 4)
    }

    /// TÜİK'in o ayın verisini açıkladığı gün: ertesi ayın 3'ü (yaklaşık; hafta sonu da açıklanır).
    public static func publicationDate(of month: LedgerMonth, calendar: Calendar) -> Date {
        let next = month.next
        return calendar.date(from: DateComponents(year: next.year, month: next.month, day: 3, hour: 10))!
    }

    /// Bir kira yılı yenilemesinin hesabı.
    public struct Quote: Hashable, Sendable {
        public enum Source: Hashable, Sendable {
            /// Uygulamayla gelen TÜFE tablosundan hesaplandı.
            case table
            /// Kullanıcı açıklanan oranı elle girdi (tabloda o ay henüz yok).
            case manual
        }

        public var renewal: Date
        /// Kaçıncı kira yılı başlıyor (sözleşmenin ilk yılı 1).
        public var year: Int
        public var referenceMonth: LedgerMonth
        public var currentRent: Decimal
        /// `nil`: oran bilinmiyor (`referenceMonth` verisi yok, elle de girilmedi).
        public var rate: Decimal?
        public var source: Source?

        /// Yeni kiranın üst sınırı, kuruşa yuvarlanır. Ortalama düştüyse artış yok (kira kendiliğinden düşmez).
        public var maximumRent: Decimal? { rate.map { (currentRent * (1 + max($0, 0))).rounded(scale: 2) } }
        public var maximumIncrease: Decimal? { maximumRent.map { $0 - currentRent } }
        /// 5 yılı dolduran sözleşmede yeni kira emsallere göre mahkemece belirlenebilir (TBK m.344/3).
        /// Hesaplanmaz; yalnız bilgi verilir.
        public var isPastFiveYears: Bool { year > 5 }

        /// Kararlaştırılan tutar sınırı aşıyor mu (oran biliniyorsa).
        public func exceeds(_ agreed: Decimal) -> Bool? { maximumRent.map { agreed > $0 } }
    }

    /// Sözleşme başlangıcından sonraki `n`. yıl dönümü (gün sonu taşmaları takvime bırakılır: 29 Şubat → 28 Şubat).
    public static func anniversary(_ n: Int, of start: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .year, value: n, to: calendar.startOfDay(for: start))!
    }

    /// Ekranda gösterilecek yenileme: son 45 gün içinde yenilendiyse o (tutarı güncellemek için),
    /// değilse sıradaki. Sözleşme henüz başlamadıysa ilk yenileme.
    public static func relevantRenewal(start: Date, now: Date, calendar: Calendar) -> (date: Date, year: Int) {
        let today = calendar.startOfDay(for: now)
        var n = 1
        while anniversary(n, of: start, calendar: calendar) <= today { n += 1 }
        // `n` sıradaki (bugünden sonraki) yıl dönümü; bir öncekine bak.
        if n > 1 {
            let last = anniversary(n - 1, of: start, calendar: calendar)
            if let days = calendar.dateComponents([.day], from: last, to: today).day, days <= 45 {
                return (last, n)
            }
        }
        return (anniversary(n, of: start, calendar: calendar), n + 1)
    }

    /// Yenileme hesabı. `manualRate` yalnız tablo o ayı bilmiyorsa ve aynı ay için girildiyse kullanılır;
    /// tablo biliyorsa tablo geçerlidir.
    public static func quote(start: Date, currentRent: Decimal, now: Date, cpi: RealReturn.CPITable,
                             manualRate: (month: LedgerMonth, rate: Decimal)? = nil, calendar: Calendar) -> Quote {
        let renewal = relevantRenewal(start: start, now: now, calendar: calendar)
        let reference = referenceMonth(forRenewal: LedgerMonth(containing: renewal.date, calendar: calendar))
        var quote = Quote(renewal: renewal.date, year: renewal.year, referenceMonth: reference,
                          currentRent: currentRent, rate: nil, source: nil)
        if let rate = averageChange(for: reference, cpi: cpi) {
            quote.rate = rate
            quote.source = .table
        } else if let manualRate, manualRate.month == reference, manualRate.rate >= 0 {
            quote.rate = manualRate.rate
            quote.source = .manual
        }
        return quote
    }
}
