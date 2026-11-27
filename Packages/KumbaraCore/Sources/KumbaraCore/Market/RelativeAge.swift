import Foundation

/// Fiyatın yaşı, insanın okuyacağı biçimde (specs/06 §2.4): saat değil "az önce", "5 dk önce".
/// Kullanıcıya veri sağlayıcının adı gösterilmez; önemli olan fiyatın ne kadar taze olduğudur.
public enum RelativeAge: Equatable, Sendable {
    /// 1 dakikadan yeni (ya da saat farkından ötürü gelecekte görünen).
    case justNow
    case minutes(Int)
    /// Aynı gün içinde, 1 saatten eski.
    case hours(Int)
    /// Dün; saatiyle birlikte gösterilir ("dün 18:05").
    case yesterday(Date)
    /// Daha eski; gün, ay ve saat.
    case earlier(Date)

    public static func of(_ date: Date, now: Date, calendar: Calendar) -> RelativeAge {
        let age = now.timeIntervalSince(date)
        if age < 60 { return .justNow }
        if age < 3600 { return .minutes(Int(age / 60)) }
        if calendar.isDate(date, inSameDayAs: now) { return .hours(Int(age / 3600)) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday(date)
        }
        return .earlier(date)
    }

    /// Görünümün kendini ne sıklıkla yenilemesi gerektiği.
    public var refreshInterval: TimeInterval {
        switch self {
        case .justNow, .minutes: 30
        case .hours: 300
        case .yesterday, .earlier: 3600
        }
    }
}
