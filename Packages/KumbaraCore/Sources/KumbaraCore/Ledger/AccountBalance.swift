import Foundation

/// Hesap bakiyesi = açılış + gelir − gider − giden transfer + gelen transfer.
/// Taslaklar dahil edilmez (C5). Hesabın para birimi dışındaki kayıtlar programlama hatasıdır
/// (her hesabın tek para birimi vardır — REQ-L1).
public enum AccountBalance {
    public static func compute(accountID: UUID, opening: Money, entries: some Sequence<LedgerEntry>) -> Money {
        var balance = opening
        for entry in entries where entry.status == .posted {
            switch entry.kind {
            case .income where entry.accountID == accountID:
                balance += entry.amount
            case .expense where entry.accountID == accountID:
                balance -= entry.amount
            case .transfer:
                if entry.accountID == accountID { balance -= entry.amount }
                if entry.toAccountID == accountID { balance += entry.amount }
            default:
                break
            }
        }
        return balance
    }
}
