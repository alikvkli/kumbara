import Foundation
import KumbaraCore
import SwiftData

/// Şema v1 (specs/05 §3).
///
/// CloudKit uyumu için: tüm özellikler varsayılan değerli veya opsiyonel, ilişkiler opsiyonel,
/// `unique` kısıtı yok. `Decimal` alanlar kanonik `String` olarak saklanır (specs/00 C3).
/// Enum alanlar `rawValue` String'i olarak saklanır; okunamayan değer güvenli varsayılana düşer.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [LedgerAccount.self, LedgerCategory.self, LedgerTransaction.self, MerchantMemory.self]
    }

    @Model
    public final class LedgerAccount {
        public var id: UUID = UUID()
        public var name: String = ""
        var kindRaw: String = AccountKind.cash.rawValue
        var currencyRaw: String = CurrencyCode.TRY.rawValue
        var openingBalanceRaw: String = "0"
        /// Kredi kartı ekstre kesim günü (REQ-L8, M4).
        public var statementDay: Int?
        public var isArchived: Bool = false
        public var sortIndex: Int = 0
        public var createdAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.account)
        public var transactions: [LedgerTransaction]? = []

        @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.toAccount)
        public var incomingTransfers: [LedgerTransaction]? = []

        public init(name: String, kind: AccountKind, currency: CurrencyCode,
                    openingBalance: Decimal = 0, sortIndex: Int = 0) {
            self.name = name
            self.kindRaw = kind.rawValue
            self.currencyRaw = currency.rawValue
            self.openingBalanceRaw = openingBalance.canonicalString
            self.sortIndex = sortIndex
        }
    }

    @Model
    public final class LedgerCategory {
        public var id: UUID = UUID()
        /// Varsayılan kategorinin kalıcı anahtarı (`DefaultCategories`); kullanıcı kategorisinde `nil`.
        public var seedKey: String?
        public var name: String = ""
        var kindRaw: String = CategoryKind.expense.rawValue
        /// SF Symbols adı; alt kategoride boşsa üstününki kullanılır.
        public var symbol: String = ""
        var colorRaw: String = CategoryColor.gray.rawValue
        public var sortIndex: Int = 0
        public var isArchived: Bool = false

        public var parent: LedgerCategory?

        @Relationship(deleteRule: .cascade, inverse: \LedgerCategory.parent)
        public var children: [LedgerCategory]? = []

        @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.category)
        public var transactions: [LedgerTransaction]? = []

        @Relationship(deleteRule: .cascade, inverse: \MerchantMemory.category)
        public var merchantMemories: [MerchantMemory]? = []

        public init(name: String, kind: CategoryKind, symbol: String, color: CategoryColor,
                    parent: LedgerCategory? = nil, seedKey: String? = nil, sortIndex: Int = 0) {
            self.name = name
            self.kindRaw = kind.rawValue
            self.symbol = symbol
            self.colorRaw = color.rawValue
            self.parent = parent
            self.seedKey = seedKey
            self.sortIndex = sortIndex
        }
    }

    @Model
    public final class LedgerTransaction {
        public var id: UUID = UUID()
        public var date: Date = Date.now
        /// Pozitif büyüklük, kanonik String.
        var amountRaw: String = "0"
        var currencyRaw: String = CurrencyCode.TRY.rawValue
        var kindRaw: String = TransactionKind.expense.rawValue
        var statusRaw: String = TransactionStatus.posted.rawValue
        var originRaw: String = TransactionOrigin.manual.rawValue
        public var merchant: String?
        /// `MerchantKey.normalize(merchant)`; arama ve öğrenme için.
        public var merchantKey: String = ""
        public var note: String = ""
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var account: LedgerAccount?
        public var toAccount: LedgerAccount?
        public var category: LedgerCategory?

        public init(date: Date, amount: Money, kind: TransactionKind,
                    status: TransactionStatus = .posted, origin: TransactionOrigin = .manual) {
            precondition(amount.amount > 0, "Tutar pozitif büyüklük olarak saklanır")
            self.date = date
            self.amountRaw = amount.amount.canonicalString
            self.currencyRaw = amount.currency.rawValue
            self.kindRaw = kind.rawValue
            self.statusRaw = status.rawValue
            self.originRaw = origin.rawValue
        }
    }

    /// Satıcı → kategori öğrenme kaydı (REQ-L6).
    @Model
    public final class MerchantMemory {
        public var key: String = ""
        public var displayName: String = ""
        public var lastUsed: Date = Date.now
        public var useCount: Int = 0
        public var category: LedgerCategory?

        public init(key: String, displayName: String, category: LedgerCategory, lastUsed: Date, useCount: Int) {
            self.key = key
            self.displayName = displayName
            self.category = category
            self.lastUsed = lastUsed
            self.useCount = useCount
        }
    }
}

public typealias LedgerAccount = SchemaV1.LedgerAccount
public typealias LedgerCategory = SchemaV1.LedgerCategory
public typealias LedgerTransaction = SchemaV1.LedgerTransaction
public typealias MerchantMemory = SchemaV1.MerchantMemory

public enum KumbaraMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
