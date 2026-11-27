import Foundation
import KumbaraCore
import KumbaraData

/// İşlem listesi filtresi ve araması (T1.4). Eşleme Türkçe harf/aksan duyarsızdır
/// ("sok" → "ŞOK", "migros" → "MİGROS").
struct TransactionFilter: Equatable {
    var kind: TransactionKind?
    var accountID: UUID?
    var query = ""

    var isActive: Bool { kind != nil || accountID != nil }

    func matches(_ transaction: LedgerTransaction) -> Bool {
        if let kind, transaction.kind != kind { return false }
        if let accountID, transaction.account?.id != accountID, transaction.toAccount?.id != accountID { return false }
        let needle = MerchantKey.normalize(query)
        guard !needle.isEmpty else { return true }
        let haystacks = [
            transaction.merchantKey,
            MerchantKey.normalize(transaction.note),
            MerchantKey.normalize(transaction.category?.path ?? ""),
        ]
        return haystacks.contains { $0.contains(needle) }
    }
}

/// Günlere göre gruplanmış işlemler (yeniden eskiye).
struct TransactionDay: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]
    var id: Date { date }

    static func group(_ transactions: [LedgerTransaction], calendar: Calendar) -> [TransactionDay] {
        Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
            .map { TransactionDay(date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}
