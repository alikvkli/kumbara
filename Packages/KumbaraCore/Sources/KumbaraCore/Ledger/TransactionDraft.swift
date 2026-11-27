import Foundation

/// Kullanıcının doldurduğu (veya OCR/kestirmenin önerdiği) işlem; kaydetmeden önce doğrulanır.
public struct TransactionDraft: Hashable, Sendable {
    public var kind: TransactionKind
    public var amount: Decimal?
    public var date: Date
    public var account: AccountRef?
    public var toAccount: AccountRef?
    public var category: CategoryRef?
    public var merchant: String
    public var note: String

    public struct AccountRef: Hashable, Sendable {
        public var id: UUID
        public var currency: CurrencyCode
        public init(id: UUID, currency: CurrencyCode) { self.id = id; self.currency = currency }
    }

    public struct CategoryRef: Hashable, Sendable {
        public var id: UUID
        public var kind: CategoryKind
        public init(id: UUID, kind: CategoryKind) { self.id = id; self.kind = kind }
    }

    public init(kind: TransactionKind = .expense, amount: Decimal? = nil, date: Date = .now,
                account: AccountRef? = nil, toAccount: AccountRef? = nil, category: CategoryRef? = nil,
                merchant: String = "", note: String = "") {
        self.kind = kind
        self.amount = amount
        self.date = date
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.merchant = merchant
        self.note = note
    }

    public enum Issue: Hashable, Sendable {
        case missingAmount
        case nonPositiveAmount
        case missingAccount
        case missingDestination
        case sameAccountTransfer
        /// v1'de transfer yalnız aynı para birimli hesaplar arasında (kur girişi M2 sonrası).
        case transferCurrencyMismatch
        case categoryKindMismatch
    }

    /// Boşsa kaydedilebilir.
    public var issues: [Issue] {
        var result: [Issue] = []
        switch amount {
        case nil: result.append(.missingAmount)
        case let value? where value <= 0: result.append(.nonPositiveAmount)
        default: break
        }
        if account == nil { result.append(.missingAccount) }
        if kind == .transfer {
            if let from = account, let to = toAccount {
                if from.id == to.id { result.append(.sameAccountTransfer) }
                if from.currency != to.currency { result.append(.transferCurrencyMismatch) }
            } else {
                result.append(.missingDestination)
            }
        }
        if let category {
            if CategoryKind(kind) != category.kind { result.append(.categoryKindMismatch) }
        }
        return result
    }

    public var isValid: Bool { issues.isEmpty }

    /// Kaydedilecek satıcı adı: baş/son boşluk atılmış, boşsa `nil`.
    public var trimmedMerchant: String? {
        let value = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
