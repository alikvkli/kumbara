import Foundation

/// İşlemin yönü (REQ-L2, L3).
public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case expense, income, transfer
}

/// Taslak kayıtlar kullanıcı onayına kadar toplamlara girmez (specs/00 C5).
public enum TransactionStatus: String, Sendable, Codable, CaseIterable {
    case draft, posted
}

/// Kaydın nereden geldiği (specs/05 §3).
public enum TransactionOrigin: String, Sendable, Codable, CaseIterable {
    case manual, ocr, recurring, `import`, intent
}

public enum AccountKind: String, Sendable, Codable, CaseIterable {
    case cash, bank, card, savings
}

public enum CategoryKind: String, Sendable, Codable, CaseIterable {
    case expense, income

    public init?(_ kind: TransactionKind) {
        switch kind {
        case .expense: self = .expense
        case .income: self = .income
        case .transfer: return nil
        }
    }
}

/// Kategori rengi: sistem paletinden 8 sakin ton (specs/06 §3). Uygulama sistem rengine eşler.
public enum CategoryColor: String, Sendable, Codable, CaseIterable {
    case gray, teal, green, mint, orange, brown, purple, indigo
}

/// Hesaplamalar için bir işlemin değer kopyası. Kalıcı model (SwiftData) bundan bağımsızdır.
public struct LedgerEntry: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Her zaman pozitif büyüklük; yön `kind` ile belirlenir.
    public var amount: Money
    public var kind: TransactionKind
    public var status: TransactionStatus
    public var accountID: UUID?
    public var toAccountID: UUID?
    public var categoryID: UUID?
    public var merchant: String?

    public init(id: UUID = UUID(), date: Date, amount: Money, kind: TransactionKind,
                status: TransactionStatus = .posted, accountID: UUID? = nil, toAccountID: UUID? = nil,
                categoryID: UUID? = nil, merchant: String? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.kind = kind
        self.status = status
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.categoryID = categoryID
        self.merchant = merchant
    }

    /// Gelir +, gider −, transfer 0 (toplam gelir/gidere girmez — REQ-L3).
    public var signedAmount: Money {
        switch kind {
        case .income: amount
        case .expense: -amount
        case .transfer: .zero(amount.currency)
        }
    }
}
