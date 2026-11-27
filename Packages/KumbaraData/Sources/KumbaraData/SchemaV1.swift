import Foundation
import KumbaraCore
import SwiftData

/// Şema v1 (specs/05 §3). İlk yayına kadar yerinde genişletilir; yayından sonra donar ve her
/// değişiklik yeni `VersionedSchema` + göç aşamasıyla yapılır.
///
/// CloudKit uyumu için: tüm özellikler varsayılan değerli veya opsiyonel, ilişkiler opsiyonel,
/// `unique` kısıtı yok. `Decimal` alanlar kanonik `String` olarak saklanır (specs/00 C3).
/// Enum alanlar `rawValue` String'i olarak saklanır; okunamayan değer güvenli varsayılana düşer.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [LedgerAccount.self, LedgerCategory.self, LedgerTransaction.self, MerchantMemory.self,
         AssetTrade.self, CustomAsset.self, PriceSnapshot.self, Budget.self, NotificationLog.self]
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

        /// Kategori silinince bütçesi de gider.
        @Relationship(deleteRule: .cascade, inverse: \Budget.category)
        public var budgets: [Budget]? = []

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

extension SchemaV1 {
    /// Varlık alımı/satımı (REQ-P1). Fiyat ve ücret TRY.
    @Model
    public final class AssetTrade {
        public var id: UUID = UUID()
        /// `AssetCode.id` (`gold.gram24`, `custom.<uuid>`).
        public var assetID: String = ""
        var sideRaw: String = Trade.Side.buy.rawValue
        var quantityRaw: String = "0"
        var unitPriceRaw: String = "0"
        var feeRaw: String = "0"
        public var date: Date = Date.now
        /// İşlem anındaki USD/TRY (reel getiri, specs/03 §4).
        var usdTRYRaw: String?
        public var note: String = ""
        public var createdAt: Date = Date.now

        public init(trade: Trade, note: String = "") {
            self.id = trade.id
            self.note = note
            apply(trade)
        }

        func apply(_ trade: Trade) {
            assetID = trade.asset.id
            sideRaw = trade.side.rawValue
            quantityRaw = trade.quantity.canonicalString
            unitPriceRaw = trade.unitPrice.canonicalString
            feeRaw = trade.fee.canonicalString
            date = trade.date
            usdTRYRaw = trade.usdTRYAtTrade?.canonicalString
        }
    }

    /// Fiyatı elle girilen varlık: fon, hisse, mevduat… (REQ-P2).
    @Model
    public final class CustomAsset {
        public var id: UUID = UUID()
        public var name: String = ""
        var manualPriceRaw: String?
        public var manualPriceDate: Date?
        public var createdAt: Date = Date.now

        public init(name: String) {
            self.name = name
        }
    }

    /// Günlük fiyat kaydı (specs/02 §6): varlık başına günde bir satır, günün son fiyatı.
    @Model
    public final class PriceSnapshot {
        public var assetID: String = ""
        /// Günün başlangıcı (yerel takvim).
        public var day: Date = Date.now
        var bidRaw: String?
        var askRaw: String?
        var midRaw: String = "0"
        var sourceRaw: String = ProviderID.manual.rawValue
        public var asOf: Date = Date.now
        public var isDerived: Bool = false

        public init(quote: Quote, day: Date) {
            self.assetID = quote.asset.id
            self.day = day
            apply(quote)
        }

        func apply(_ quote: Quote) {
            bidRaw = quote.bid?.canonicalString
            askRaw = quote.ask?.canonicalString
            midRaw = quote.mid.canonicalString
            sourceRaw = quote.source.rawValue
            asOf = quote.asOf
            isDerived = quote.isDerived
        }
    }
}

extension SchemaV1 {
    /// Aylık bütçe (specs/08 §1). `category == nil && isOverall` genel bütçedir.
    @Model
    public final class Budget {
        public var id: UUID = UUID()
        public var category: LedgerCategory?
        public var isOverall: Bool = false
        /// `BudgetLimitHistory.canonical`
        var historyRaw: String = ""
        public var createdAt: Date = Date.now

        public init(category: LedgerCategory?, history: BudgetLimitHistory) {
            self.category = category
            self.isOverall = category == nil
            self.historyRaw = history.canonical
        }

        public var history: BudgetLimitHistory {
            get { BudgetLimitHistory(canonical: historyRaw) ?? BudgetLimitHistory() }
            set { historyRaw = newValue.canonical }
        }

        public var spec: BudgetSpec {
            BudgetSpec(id: id, categoryID: isOverall ? nil : category?.id, history: history)
        }
    }

    /// Bir kez gönderilecek bildirimlerin kaydı (specs/08 §6): anahtar "tür:nesne:dönem:eşik".
    @Model
    public final class NotificationLog {
        public var key: String = ""
        public var sentAt: Date = Date.now

        public init(key: String) {
            self.key = key
        }
    }
}

public typealias Budget = SchemaV1.Budget
public typealias NotificationLog = SchemaV1.NotificationLog
public typealias AssetTrade = SchemaV1.AssetTrade
public typealias CustomAsset = SchemaV1.CustomAsset
public typealias PriceSnapshot = SchemaV1.PriceSnapshot
public typealias LedgerAccount = SchemaV1.LedgerAccount
public typealias LedgerCategory = SchemaV1.LedgerCategory
public typealias LedgerTransaction = SchemaV1.LedgerTransaction
public typealias MerchantMemory = SchemaV1.MerchantMemory

public enum KumbaraMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
