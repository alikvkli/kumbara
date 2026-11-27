import Foundation

/// Alacak / borç (REQ-I4, specs/10 §4). Yalnız kullanıcının defteri; kimseyle paylaşılmaz.
///
/// İşaret kuralı: **pozitif = kişi bana borçlu**.
/// - `split`: bölünen giderde kişinin payı (+). Gider hesaptan tam çıkar; bütçeye yalnız kendi payın girer.
/// - `lent`: elden verdiğim borç (+). Hesaptan çıkan bir transferdir, bütçeye girmez.
/// - `borrowed`: aldığım borç (−). Hesaba giren transfer.
/// - `settlement`: kapanış; kişi bana öderse (−), ben ona ödersem (+). Bütçeye girmez.
public enum DebtKind: String, Sendable, Codable, CaseIterable {
    case split, lent, borrowed, settlement
}

public struct DebtEntry: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var personID: UUID
    public var kind: DebtKind
    /// İşaretli: + kişi bana borçlu.
    public var amount: Decimal
    public var date: Date

    public init(id: UUID = UUID(), personID: UUID, kind: DebtKind, amount: Decimal, date: Date) {
        self.id = id
        self.personID = personID
        self.kind = kind
        self.amount = amount
        self.date = date
    }
}

public enum DebtMath {
    /// Kişi başına net bakiye (+ alacak, − borç). Sıfırlananlar da döner (0).
    public static func balances(_ entries: [DebtEntry]) -> [UUID: Decimal] {
        entries.reduce(into: [:]) { $0[$1.personID, default: 0] += $1.amount }
    }

    /// Toplam alacak (pozitif bakiyeler) ve toplam borç (negatiflerin büyüklüğü).
    public static func totals(_ balances: [UUID: Decimal]) -> (receivable: Decimal, payable: Decimal) {
        balances.values.reduce(into: (Decimal(0), Decimal(0))) { result, value in
            if value > 0 { result.0 += value } else { result.1 -= value }
        }
    }

    /// Eşit bölme: toplam, sen dahil `participants` kişiye. Kuruş farkı sende kalır
    /// (₺1.000 / 3 → başkaları 333,33; sen 333,34).
    public static func equalShares(total: Decimal, others: Int) -> (mine: Decimal, each: Decimal) {
        guard others > 0 else { return (total, 0) }
        var raw = total / Decimal(others + 1)
        var each = Decimal()
        NSDecimalRound(&each, &raw, 2, .down)
        return (total - each * Decimal(others), each)
    }

    /// Yüzdeyle pay (0…100); 2 basamağa aşağı yuvarlanır.
    public static func share(of total: Decimal, percent: Decimal) -> Decimal {
        var raw = total * percent / 100
        var result = Decimal()
        NSDecimalRound(&result, &raw, 2, .down)
        return result
    }

    /// Kapatma kaydının işareti: kişinin bakiyesi pozitifse (bana borçlu) ödeme bakiyeyi düşürür.
    public static func settlement(amount: Decimal, balance: Decimal) -> Decimal {
        balance >= 0 ? -abs(amount) : abs(amount)
    }

    /// "Hatırlat" için hazır mesaj. Gönderen kullanıcıdır; uygulama göndermez.
    public static func reminderMessage(name: String, amount: String) -> String {
        "Selam \(name), aramızda \(amount) kalmıştı; uygun olunca gönderebilir misin? 🙂"
    }
}
