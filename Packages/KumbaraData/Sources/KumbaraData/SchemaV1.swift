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
         AssetTrade.self, CustomAsset.self, PriceSnapshot.self, Budget.self, NotificationLog.self, RecurringRule.self, PriceAlert.self,
         Goal.self, SavingsPlan.self, Person.self, DebtRecord.self,
         RentContract.self, Loan.self]
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
        /// Son ödeme günü (ayın günü); yoksa kesimden 10 gün sonra (specs/08 §3.1).
        public var paymentDueDay: Int?
        /// Kredi kartı limiti (specs/11 §6); boşsa tanımsız.
        var creditLimitRaw: String?
        public var isArchived: Bool = false
        public var sortIndex: Int = 0
        public var createdAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.account)
        public var transactions: [LedgerTransaction]? = []

        @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.toAccount)
        public var incomingTransfers: [LedgerTransaction]? = []

        @Relationship(deleteRule: .nullify, inverse: \RecurringRule.account)
        public var recurringRules: [RecurringRule]? = []

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

        @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category)
        public var recurringRules: [RecurringRule]? = []

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
        /// Tekrar kuralından üretildiyse kuralın kimliği ve vade günü (idempotens, specs/08 §2.2).
        public var recurrenceID: UUID?
        public var dueDay: Date?
        /// Taksitli alımın parçasıysa: plan kimliği, sıra (1'den) ve taksit sayısı (specs/08 §3.2).
        public var installmentPlanID: UUID?
        public var installmentIndex: Int?
        public var installmentCount: Int?
        /// Bölünen giderde başkalarının payı toplamı (specs/10 §4); yoksa `nil`.
        var sharedRaw: String?

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
        /// Hangi birikim hedefi için (specs/09 §6, R2); `nil` = hedefsiz.
        public var goalID: UUID?

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

extension SchemaV1 {
    /// Tekrarlayan işlem kuralı (specs/08 §2). Vadesi gelen her tekrar bir **taslak** üretir (C5).
    @Model
    public final class RecurringRule {
        public var id: UUID = UUID()
        var kindRaw: String = TransactionKind.expense.rawValue
        var amountRaw: String = "0"
        /// Fatura gibi: taslak son tutarla gelir ama "kontrol et" der.
        public var isAmountVariable: Bool = false
        public var account: LedgerAccount?
        public var category: LedgerCategory?
        public var merchant: String?
        public var note: String = ""
        var frequencyRaw: String = ""
        public var start: Date = Date.now
        public var end: Date?
        public var maxCount: Int?
        /// En son taslak üretilen vade (günün başlangıcı).
        public var lastDue: Date?
        public var isPaused: Bool = false
        public var createdAt: Date = Date.now

        public init(kind: TransactionKind, amount: Decimal, frequency: RecurrenceFrequency, start: Date) {
            self.kindRaw = kind.rawValue
            self.amountRaw = amount.canonicalString
            self.frequencyRaw = frequency.canonical
            self.start = start
        }

        public var kind: TransactionKind {
            get { TransactionKind(rawValue: kindRaw) ?? .expense }
            set { kindRaw = newValue.rawValue }
        }

        public var amount: Decimal {
            get { Decimal(canonical: amountRaw) ?? 0 }
            set { amountRaw = newValue.canonicalString }
        }

        public var frequency: RecurrenceFrequency? {
            get { RecurrenceFrequency(canonical: frequencyRaw) }
            set { frequencyRaw = newValue?.canonical ?? "" }
        }

        public var schedule: RecurrenceSchedule? {
            frequency.map { RecurrenceSchedule(frequency: $0, start: start, end: end, maxCount: maxCount) }
        }
    }
}

extension SchemaV1 {
    /// Fiyat alarmı (REQ-M4, specs/08 §5). Bir kez çalar; kullanıcı yeniden kurabilir.
    @Model
    public final class PriceAlert {
        public var id: UUID = UUID()
        var assetID: String = ""
        var directionRaw: String = PriceAlertRule.Direction.above.rawValue
        var thresholdRaw: String = "0"
        var priceKindRaw: String = PriceKind.bid.rawValue
        /// Son gerçek fiyattaki durum (geçiş tespiti için); `nil` = henüz fiyat görülmedi.
        public var lastSatisfied: Bool?
        public var isActive: Bool = true
        public var firedAt: Date?
        public var firedPrice: String?
        public var createdAt: Date = Date.now

        public init(rule: PriceAlertRule) {
            self.assetID = rule.asset.id
            self.directionRaw = rule.direction.rawValue
            self.thresholdRaw = rule.threshold.canonicalString
            self.priceKindRaw = rule.priceKind.rawValue
        }

        public var rule: PriceAlertRule? {
            guard let asset = AssetCode(id: assetID), let threshold = Decimal(canonical: thresholdRaw) else { return nil }
            return PriceAlertRule(asset: asset, direction: PriceAlertRule.Direction(rawValue: directionRaw) ?? .above,
                                  threshold: threshold, priceKind: PriceKind(rawValue: priceKindRaw) ?? .bid)
        }
    }

    /// Birikim hedefi (REQ-P9, specs/09 §6). İlerleme, `goalID`'si bu hedef olan alımlardan hesaplanır.
    @Model
    public final class Goal {
        public var id: UUID = UUID()
        public var name: String = ""
        /// `quantity` | `amount`.
        var kindRaw: String = "amount"
        var assetID: String?
        var targetRaw: String = "0"
        public var deadline: Date?
        public var isArchived: Bool = false
        public var createdAt: Date = Date.now

        public init(_ goal: SavingsGoal) {
            self.id = goal.id
            apply(goal)
        }

        func apply(_ goal: SavingsGoal) {
            name = goal.name
            deadline = goal.deadline
            switch goal.target {
            case let .quantity(asset, quantity):
                kindRaw = "quantity"
                assetID = asset.id
                targetRaw = quantity.canonicalString
            case let .amount(amount):
                kindRaw = "amount"
                assetID = nil
                targetRaw = amount.canonicalString
            }
        }

        public var goal: SavingsGoal? {
            guard let target = Decimal(canonical: targetRaw) else { return nil }
            if kindRaw == "quantity" {
                guard let asset = assetID.flatMap(AssetCode.init(id:)) else { return nil }
                return SavingsGoal(id: id, name: name, target: .quantity(asset, target), deadline: deadline)
            }
            return SavingsGoal(id: id, name: name, target: .amount(target), deadline: deadline)
        }
    }
}

public typealias Goal = SchemaV1.Goal
public typealias SavingsPlan = SchemaV1.SavingsPlan
public typealias Person = SchemaV1.Person
public typealias DebtRecord = SchemaV1.DebtRecord
public typealias RentContract = SchemaV1.RentContract
public typealias PriceAlert = SchemaV1.PriceAlert
public typealias RecurringRule = SchemaV1.RecurringRule
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

extension SchemaV1 {
    /// Düzenli alım planı (REQ-I7, specs/10 §7). Kayıt üretmez; vadesinde hatırlatır.
    @Model
    public final class SavingsPlan {
        public var id: UUID = UUID()
        public var assetID: String = ""
        /// `q:2` | `a:5000` (SavingsPlanRule.targetCanonical).
        var targetRaw: String = ""
        /// `s:m:15:1` | `salary`.
        var triggerRaw: String = ""
        public var start: Date = Date.now
        public var goalID: UUID?
        public var isActive: Bool = true
        public var createdAt: Date = Date.now

        public init(_ rule: SavingsPlanRule) {
            self.id = rule.id
            apply(rule)
        }

        public func apply(_ rule: SavingsPlanRule) {
            assetID = rule.asset.id
            targetRaw = rule.targetCanonical
            triggerRaw = rule.triggerCanonical
            start = rule.start
            goalID = rule.goalID
        }

        public var rule: SavingsPlanRule? {
            guard let asset = AssetCode(id: assetID), let target = SavingsPlanRule.target(canonical: targetRaw),
                  let trigger = SavingsPlanRule.trigger(canonical: triggerRaw) else { return nil }
            return SavingsPlanRule(id: id, asset: asset, target: target, trigger: trigger, start: start, goalID: goalID)
        }
    }
}

extension SchemaV1 {
    /// Alacak/borç defterindeki kişi (specs/10 §4). Rehberden seçildiyse yalnız kimliği tutulur.
    @Model
    public final class Person {
        public var id: UUID = UUID()
        public var name: String = ""
        public var contactID: String?
        /// İsteğe bağlı hatırlatma günü.
        public var remindAt: Date?
        public var isArchived: Bool = false
        public var createdAt: Date = Date.now

        public init(name: String, contactID: String? = nil) {
            self.name = name
            self.contactID = contactID
        }
    }

    /// Alacak/borç kaydı. İşaret: + kişi bana borçlu (DebtEntry ile aynı).
    @Model
    public final class DebtRecord {
        public var id: UUID = UUID()
        public var personID: UUID = UUID()
        var kindRaw: String = DebtKind.split.rawValue
        var amountRaw: String = "0"
        public var date: Date = Date.now
        /// Bölünen gider ya da kapanış/borç transferi.
        public var transactionID: UUID?
        public var note: String = ""
        public var createdAt: Date = Date.now

        public init(personID: UUID, kind: DebtKind, amount: Decimal, date: Date, transactionID: UUID?) {
            self.personID = personID
            self.kindRaw = kind.rawValue
            self.amountRaw = amount.canonicalString
            self.date = date
            self.transactionID = transactionID
        }

        public var kind: DebtKind { DebtKind(rawValue: kindRaw) ?? .split }
        public var amount: Decimal {
            get { Decimal(canonical: amountRaw) ?? 0 }
            set { amountRaw = newValue.canonicalString }
        }
        public var entry: DebtEntry { DebtEntry(id: id, personID: personID, kind: kind, amount: amount, date: date) }
    }
}

extension SchemaV1 {
    /// Kira sözleşmesi (REQ-I9, specs/12). Yalnız hesap ve hatırlatma içindir; kayıt üretmez.
    @Model
    public final class RentContract {
        public var id: UUID = UUID()
        public var name: String = ""
        var roleRaw: String = RentIncrease.Role.tenant.rawValue
        /// Sözleşmenin başladığı gün; yıl dönümleri yenileme günleridir.
        public var start: Date = Date.now
        var rentRaw: String = "0"
        /// Bağlı tekrarlayan kira kuralı (varsa yeni kira ona da yazılır).
        public var recurringRuleID: UUID?
        /// Tabloda henüz olmayan ay için elle girilen TÜİK oranı ("2026-11" ve oran).
        public var manualRateMonth: String?
        var manualRateRaw: String?
        public var createdAt: Date = Date.now

        public init(name: String, role: RentIncrease.Role, start: Date, rent: Decimal) {
            self.name = name
            self.roleRaw = role.rawValue
            self.start = start
            self.rentRaw = rent.canonicalString
        }

        public var role: RentIncrease.Role {
            get { RentIncrease.Role(rawValue: roleRaw) ?? .tenant }
            set { roleRaw = newValue.rawValue }
        }

        public var rent: Decimal {
            get { Decimal(canonical: rentRaw) ?? 0 }
            set { rentRaw = newValue.canonicalString }
        }

        public var manualRate: (month: LedgerMonth, rate: Decimal)? {
            get {
                guard let manualRateMonth, let manualRateRaw, let rate = Decimal(canonical: manualRateRaw) else { return nil }
                let parts = manualRateMonth.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
                return (LedgerMonth(year: parts[0], month: parts[1]), rate)
            }
            set {
                manualRateMonth = newValue.map { String(format: "%04d-%02d", $0.month.year, $0.month.month) }
                manualRateRaw = newValue?.rate.canonicalString
            }
        }
    }

    /// Kredi (REQ-I10, specs/13). Ödeme planı koşullardan hesaplanır, saklanmaz. Ödenen her taksit,
    /// seçilen hesaptan bir gider kaydıdır; kimlikleri sırayla `paymentIDsRaw` içinde tutulur.
    @Model
    public final class Loan {
        public var id: UUID = UUID()
        public var name: String = ""
        var kindRaw: String = LoanKind.personal.rawValue
        var principalRaw: String = "0"
        var monthlyRateRaw: String = "0"
        var taxRateRaw: String = "0"
        public var termMonths: Int = 12
        public var firstDue: Date = Date.now
        /// Bankanın bildirdiği taksit; boşsa formülden.
        var paymentRaw: String = ""
        public var isVariableRate: Bool = false
        /// Taksitin çıktığı hesap (nakit/banka).
        public var accountID: UUID?
        public var categoryID: UUID?
        /// Ödenmiş taksit sayısı (uygulamaya eklenmeden önce ödenenler dahil).
        public var paidCount: Int = 0
        /// Uygulamada işaretlenen ödemeler sırayla, virgülle: gider kaydının kimliği ya da kayıtsız
        /// işaretlenen ödeme için `-`.
        var paymentIDsRaw: String = ""
        public var closedAt: Date?
        /// Erken kapama gider kaydı.
        public var closingTransactionID: UUID?
        public var createdAt: Date = Date.now

        public init(name: String, terms: LoanTerms) {
            self.name = name
            apply(terms)
        }

        public func apply(_ terms: LoanTerms) {
            kindRaw = terms.kind.rawValue
            principalRaw = terms.principal.canonicalString
            monthlyRateRaw = terms.monthlyRate.canonicalString
            taxRateRaw = terms.taxRate.canonicalString
            termMonths = terms.termMonths
            firstDue = terms.firstDue
            paymentRaw = terms.payment?.canonicalString ?? ""
            isVariableRate = terms.isVariableRate
        }

        public var kind: LoanKind { LoanKind(rawValue: kindRaw) ?? .personal }
        public var terms: LoanTerms {
            LoanTerms(kind: kind, principal: Decimal(canonical: principalRaw) ?? 0,
                      monthlyRate: Decimal(canonical: monthlyRateRaw) ?? 0, taxRate: Decimal(canonical: taxRateRaw) ?? 0,
                      termMonths: termMonths, firstDue: firstDue, payment: Decimal(canonical: paymentRaw),
                      isVariableRate: isVariableRate)
        }

        /// Uygulamada işaretlenen ödemeler; `nil` = gider kaydı olmadan işaretlendi.
        public var payments: [UUID?] {
            get { paymentIDsRaw.split(separator: ",").map { UUID(uuidString: String($0)) } }
            set { paymentIDsRaw = newValue.map { $0?.uuidString ?? "-" }.joined(separator: ",") }
        }

        public var isClosed: Bool { closedAt != nil || paidCount >= termMonths }
    }
}
