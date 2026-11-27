import Foundation

/// İşlemin yönü (REQ-L2, L3).
public enum TransactionKind: String, Sendable, Codable, CaseIterable {
    case expense, income, transfer
}

/// Taslak kayıtlar kullanıcı onayına kadar toplamlara girmez (specs/00 C5).
public enum TransactionStatus: String, Sendable, Codable, CaseIterable {
    case draft, posted
    /// Gelecek taksit: tarihi gelince kendiliğinden kesinleşir (specs/08 §3.2).
    case planned
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
    /// Bölünen giderde başkalarının payı (specs/10 §4). Hesaptan tamamı çıkar; bütçeye ve özete yalnız
    /// kendi payın (`ownAmount`) girer.
    public var sharedAmount: Decimal

    public init(id: UUID = UUID(), date: Date, amount: Money, kind: TransactionKind,
                status: TransactionStatus = .posted, accountID: UUID? = nil, toAccountID: UUID? = nil,
                categoryID: UUID? = nil, merchant: String? = nil, sharedAmount: Decimal = 0) {
        self.sharedAmount = sharedAmount
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

    /// Bütçe ve özet için tutar: giderde başkalarının payı düşülmüş (en az sıfır).
    public var ownAmount: Money {
        guard kind == .expense, sharedAmount > 0 else { return amount }
        return Money(max(amount.amount - sharedAmount, 0), amount.currency)
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
