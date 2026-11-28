import Foundation
import KumbaraCore
import SwiftData

/// Dışa / içe aktarma ve yedek (specs/09 §3, T5.3).
@MainActor
public struct ExchangeStore {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: CSV dışa aktarma

    /// Tüm işlemler (taslak ve planlılar dahil, durum sütunuyla), tarihe göre.
    public func transactionsCSV(locale: Locale, timeZone: TimeZone = .current) throws -> String {
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)]))
        let rows = transactions.map { transaction in
            let category = transaction.category
            return ExportTransaction(
                date: transaction.date, kind: transaction.kind, status: transaction.status, amount: transaction.amount,
                account: transaction.account?.name ?? "", toAccount: transaction.toAccount?.name,
                category: category?.parent?.name ?? category?.name,
                subcategory: category?.parent == nil ? nil : category?.name,
                merchant: transaction.merchant, note: transaction.note)
        }
        return TransactionCSV.encode(rows, locale: locale, timeZone: timeZone)
    }

    // MARK: CSV içe aktarma

    public struct ImportSummary: Hashable, Sendable {
        public var created: Int
        public var duplicates: Int
    }

    /// Satırlar hesaba **taslak** olarak girer (C5); daha önce alınmış satır (parmak izi aynı) atlanır.
    /// Kategori, satıcı hafızasından önerilir (REQ-L5).
    @discardableResult
    public func importRows(_ rows: [ImportedRow], into account: LedgerAccount, now: Date = .now,
                           calendar: Calendar = .current) throws -> ImportSummary {
        var seen = Set((account.transactions ?? []).map { transaction in
            ImportFingerprint.make(date: transaction.date, amount: transaction.amount.amount, kind: transaction.kind,
                                   description: transaction.merchant ?? transaction.note, calendar: calendar)
        })
        let ledger = LedgerStore(context: context)
        var created = 0, duplicates = 0
        for row in rows {
            let key = row.fingerprint(calendar: calendar)
            guard seen.insert(key).inserted else { duplicates += 1; continue }
            let transaction = LedgerTransaction(date: row.date, amount: Money(row.amount, account.currency), kind: row.kind,
                                                status: .draft, origin: .import)
            transaction.createdAt = now
            transaction.updatedAt = now
            context.insert(transaction)
            transaction.account = account
            let merchant = row.description.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.merchant = merchant.isEmpty ? nil : merchant
            transaction.merchantKey = transaction.merchant.map(MerchantKey.normalize) ?? ""
            if let merchant = transaction.merchant, let category = try ledger.suggestedCategory(forMerchant: merchant),
               category.kind == CategoryKind(row.kind) {
                transaction.category = category
            }
            created += 1
        }
        try context.save()
        return ImportSummary(created: created, duplicates: duplicates)
    }

    // MARK: JSON yedek

    public func backupJSON(now: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var backup = try makeBackup(now: now)
        backup.rents = try rentRecords()
        return try encoder.encode(backup)
    }

    public enum RestoreMode: Sendable { case replace, merge }

    public enum RestoreError: Error, Equatable {
        case unreadable
        case newerVersion(Int)
    }

    /// Yedeği yükler. `.replace`: önce her şey silinir. `.merge`: aynı kimlikli kayıt atlanır; varsayılan
    /// kategoriler (`seedKey`) mevcut olanla eşleşir, çift kategori oluşmaz.
    public func restore(_ data: Data, mode: RestoreMode) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data) else { throw RestoreError.unreadable }
        guard backup.version <= Backup.currentVersion else { throw RestoreError.newerVersion(backup.version) }

        if mode == .replace { try deleteAll() }

        // Kimlik eşlemesi: yedekteki kimlik → depodaki nesne.
        var accounts = Dictionary(try context.fetch(FetchDescriptor<LedgerAccount>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingCategories = try context.fetch(FetchDescriptor<LedgerCategory>())
        var categories = Dictionary(existingCategories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bySeed = Dictionary(existingCategories.compactMap { c in c.seedKey.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })

        for record in backup.accounts where accounts[record.id] == nil {
            let account = LedgerAccount(name: record.name, kind: .cash, currency: .TRY)
            account.id = record.id
            account.kindRaw = record.kind
            account.currencyRaw = record.currency
            account.openingBalanceRaw = record.openingBalance
            account.statementDay = record.statementDay
            account.paymentDueDay = record.paymentDueDay
            account.creditLimitRaw = record.creditLimit
            account.isArchived = record.isArchived
            account.sortIndex = record.sortIndex
            account.createdAt = record.createdAt
            context.insert(account)
            accounts[record.id] = account
        }
        // Önce üst kategoriler, sonra alt kategoriler (ebeveyn hazır olsun).
        let orderedCategories = backup.categories.filter { $0.parentID == nil } + backup.categories.filter { $0.parentID != nil }
        for record in orderedCategories where categories[record.id] == nil {
            if let seed = record.seedKey, let existing = bySeed[seed] {
                categories[record.id] = existing
                continue
            }
            let category = LedgerCategory(name: record.name, kind: .expense, symbol: record.symbol, color: .gray)
            category.id = record.id
            category.seedKey = record.seedKey
            category.kindRaw = record.kind
            category.colorRaw = record.color
            category.sortIndex = record.sortIndex
            category.isArchived = record.isArchived
            context.insert(category)
            category.parent = record.parentID.flatMap { categories[$0] }
            categories[record.id] = category
        }

        let existingTransactions = Set(try context.fetch(FetchDescriptor<LedgerTransaction>()).map(\.id))
        for record in backup.transactions where !existingTransactions.contains(record.id) {
            guard let amount = Decimal(canonical: record.amount), amount > 0 else { continue }
            let transaction = LedgerTransaction(date: record.date, amount: Money(amount, .TRY), kind: .expense)
            transaction.id = record.id
            transaction.currencyRaw = record.currency
            transaction.kindRaw = record.kind
            transaction.statusRaw = record.status
            transaction.originRaw = record.origin
            transaction.merchant = record.merchant
            transaction.merchantKey = record.merchant.map(MerchantKey.normalize) ?? ""
            transaction.note = record.note
            transaction.createdAt = record.createdAt
            transaction.updatedAt = record.updatedAt
            transaction.recurrenceID = record.recurrenceID
            transaction.dueDay = record.dueDay
            transaction.installmentPlanID = record.installmentPlanID
            transaction.installmentIndex = record.installmentIndex
            transaction.installmentCount = record.installmentCount
            transaction.sharedRaw = record.shared
            context.insert(transaction)
            transaction.account = record.accountID.flatMap { accounts[$0] }
            transaction.toAccount = record.toAccountID.flatMap { accounts[$0] }
            transaction.category = record.categoryID.flatMap { categories[$0] }
        }

        let existingMemories = Set(try context.fetch(FetchDescriptor<MerchantMemory>()).map(\.key))
        for record in backup.merchantMemories where !existingMemories.contains(record.key) {
            guard let category = categories[record.categoryID] else { continue }
            context.insert(MerchantMemory(key: record.key, displayName: record.displayName, category: category,
                                          lastUsed: record.lastUsed, useCount: record.useCount))
        }

        let existingCustom = Set(try context.fetch(FetchDescriptor<CustomAsset>()).map(\.id))
        for record in backup.customAssets where !existingCustom.contains(record.id) {
            let asset = CustomAsset(name: record.name)
            asset.id = record.id
            asset.manualPriceRaw = record.manualPrice
            asset.manualPriceDate = record.manualPriceDate
            asset.createdAt = record.createdAt
            context.insert(asset)
        }

        let existingTrades = Set(try context.fetch(FetchDescriptor<AssetTrade>()).map(\.id))
        for record in backup.trades where !existingTrades.contains(record.id) {
            guard let asset = AssetCode(id: record.assetID),
                  let quantity = Decimal(canonical: record.quantity), let price = Decimal(canonical: record.unitPrice)
            else { continue }
            let trade = AssetTrade(trade: Trade(id: record.id, asset: asset, side: .buy, quantity: quantity,
                                                unitPrice: price, fee: 0, date: record.date), note: record.note)
            trade.sideRaw = record.side
            trade.feeRaw = record.fee
            trade.usdTRYRaw = record.usdTRY
            trade.createdAt = record.createdAt
            trade.goalID = record.goalID
            context.insert(trade)
        }

        let existingSnapshots = Set(try context.fetch(FetchDescriptor<PriceSnapshot>()).map { "\($0.assetID)|\($0.day.timeIntervalSince1970)" })
        for record in backup.snapshots where !existingSnapshots.contains("\(record.assetID)|\(record.day.timeIntervalSince1970)") {
            guard let asset = AssetCode(id: record.assetID), let mid = Decimal(canonical: record.mid),
                  let quote = Quote(asset: asset, bid: mid, ask: mid, asOf: record.asOf, source: .manual) else { continue }
            let snapshot = PriceSnapshot(quote: quote, day: record.day)
            snapshot.midRaw = record.mid
            snapshot.bidRaw = record.bid
            snapshot.askRaw = record.ask
            snapshot.sourceRaw = record.source
            snapshot.isDerived = record.isDerived
            context.insert(snapshot)
        }

        let existingBudgets = Set(try context.fetch(FetchDescriptor<Budget>()).map(\.id))
        for record in backup.budgets where !existingBudgets.contains(record.id) {
            let budget = Budget(category: record.categoryID.flatMap { categories[$0] }, history: BudgetLimitHistory())
            budget.id = record.id
            budget.isOverall = record.isOverall
            budget.historyRaw = record.history
            budget.createdAt = record.createdAt
            context.insert(budget)
            if !record.isOverall, budget.category == nil { context.delete(budget) }
        }

        let existingRules = Set(try context.fetch(FetchDescriptor<RecurringRule>()).map(\.id))
        for record in backup.recurringRules where !existingRules.contains(record.id) {
            let rule = RecurringRule(kind: .expense, amount: 1, frequency: .monthly(day: 1), start: record.start)
            rule.id = record.id
            rule.kindRaw = record.kind
            rule.amountRaw = record.amount
            rule.isAmountVariable = record.isAmountVariable
            rule.merchant = record.merchant
            rule.note = record.note
            rule.frequencyRaw = record.frequency
            rule.end = record.end
            rule.maxCount = record.maxCount
            rule.lastDue = record.lastDue
            rule.isPaused = record.isPaused
            rule.createdAt = record.createdAt
            context.insert(rule)
            rule.account = record.accountID.flatMap { accounts[$0] }
            rule.category = record.categoryID.flatMap { categories[$0] }
        }

        let existingGoals = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))
        for record in backup.goals ?? [] where !existingGoals.contains(record.id) {
            let goal = Goal(SavingsGoal(id: record.id, name: record.name, target: .amount(0), deadline: record.deadline))
            goal.kindRaw = record.kind
            goal.assetID = record.assetID
            goal.targetRaw = record.target
            goal.isArchived = record.isArchived
            goal.createdAt = record.createdAt
            context.insert(goal)
        }

        let existingPlans = Set(try context.fetch(FetchDescriptor<SavingsPlan>()).map(\.id))
        for record in backup.plans ?? [] where !existingPlans.contains(record.id) {
            guard let asset = AssetCode(id: record.assetID), let target = SavingsPlanRule.target(canonical: record.target),
                  let trigger = SavingsPlanRule.trigger(canonical: record.trigger) else { continue }
            let plan = SavingsPlan(SavingsPlanRule(id: record.id, asset: asset, target: target, trigger: trigger,
                                                   start: record.start, goalID: record.goalID))
            plan.isActive = record.isActive
            plan.createdAt = record.createdAt
            context.insert(plan)
        }

        let existingPeople = Set(try context.fetch(FetchDescriptor<Person>()).map(\.id))
        for record in backup.people ?? [] where !existingPeople.contains(record.id) {
            let person = Person(name: record.name, contactID: record.contactID)
            person.id = record.id
            person.remindAt = record.remindAt
            person.isArchived = record.isArchived
            person.createdAt = record.createdAt
            context.insert(person)
        }
        let existingDebts = Set(try context.fetch(FetchDescriptor<DebtRecord>()).map(\.id))
        for record in backup.debts ?? [] where !existingDebts.contains(record.id) {
            guard let kind = DebtKind(rawValue: record.kind), let amount = Decimal(canonical: record.amount) else { continue }
            let debt = DebtRecord(personID: record.personID, kind: kind, amount: amount, date: record.date,
                                  transactionID: record.transactionID)
            debt.id = record.id
            debt.note = record.note
            debt.createdAt = record.createdAt
            context.insert(debt)
        }

        try restoreLoans(backup.loans ?? [])

        let existingAlerts = Set(try context.fetch(FetchDescriptor<PriceAlert>()).map(\.id))
        for record in backup.priceAlerts where !existingAlerts.contains(record.id) {
            guard let asset = AssetCode(id: record.assetID), let threshold = Decimal(canonical: record.threshold) else { continue }
            let alert = PriceAlert(rule: PriceAlertRule(asset: asset, direction: .above, threshold: threshold, priceKind: .bid))
            alert.id = record.id
            alert.directionRaw = record.direction
            alert.priceKindRaw = record.priceKind
            alert.lastSatisfied = record.lastSatisfied
            alert.isActive = record.isActive
            alert.firedAt = record.firedAt
            alert.firedPrice = record.firedPrice
            alert.createdAt = record.createdAt
            context.insert(alert)
        }
        try restoreRents(backup.rents)

        try context.save()
    }

    private func deleteAll() throws {
        try context.delete(model: LedgerTransaction.self)
        try context.delete(model: MerchantMemory.self)
        try context.delete(model: Budget.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: NotificationLog.self)
        try context.delete(model: LedgerCategory.self)
        try context.delete(model: LedgerAccount.self)
        try context.delete(model: AssetTrade.self)
        try context.delete(model: CustomAsset.self)
        try context.delete(model: PriceSnapshot.self)
        try context.delete(model: PriceAlert.self)
        try context.delete(model: Goal.self)
        try context.delete(model: SavingsPlan.self)
        try context.delete(model: Person.self)
        try context.delete(model: DebtRecord.self)
        try context.delete(model: RentContract.self)
        try context.delete(model: Loan.self)
        try context.save()
    }

    private func makeBackup(now: Date) throws -> Backup {
        var backup = try makeBaseBackup(now: now)
        backup.loans = try loanRecords()
        return backup
    }

    private func makeBaseBackup(now: Date) throws -> Backup {
        Backup(
            version: Backup.currentVersion,
            exportedAt: now,
            accounts: try context.fetch(FetchDescriptor<LedgerAccount>()).map {
                .init(id: $0.id, name: $0.name, kind: $0.kindRaw, currency: $0.currencyRaw, openingBalance: $0.openingBalanceRaw,
                      statementDay: $0.statementDay, paymentDueDay: $0.paymentDueDay, isArchived: $0.isArchived,
                      sortIndex: $0.sortIndex, createdAt: $0.createdAt, creditLimit: $0.creditLimitRaw)
            },
            categories: try context.fetch(FetchDescriptor<LedgerCategory>()).map {
                .init(id: $0.id, seedKey: $0.seedKey, name: $0.name, kind: $0.kindRaw, symbol: $0.symbol, color: $0.colorRaw,
                      sortIndex: $0.sortIndex, isArchived: $0.isArchived, parentID: $0.parent?.id)
            },
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()).map {
                .init(id: $0.id, date: $0.date, amount: $0.amountRaw, currency: $0.currencyRaw, kind: $0.kindRaw,
                      status: $0.statusRaw, origin: $0.originRaw, merchant: $0.merchant, note: $0.note,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt, accountID: $0.account?.id,
                      toAccountID: $0.toAccount?.id, categoryID: $0.category?.id, recurrenceID: $0.recurrenceID,
                      dueDay: $0.dueDay, installmentPlanID: $0.installmentPlanID, installmentIndex: $0.installmentIndex,
                      installmentCount: $0.installmentCount, shared: $0.sharedRaw)
            },
            merchantMemories: try context.fetch(FetchDescriptor<MerchantMemory>()).compactMap { memory in
                memory.category.map { .init(key: memory.key, displayName: memory.displayName, lastUsed: memory.lastUsed,
                                            useCount: memory.useCount, categoryID: $0.id) }
            },
            trades: try context.fetch(FetchDescriptor<AssetTrade>()).map {
                .init(id: $0.id, assetID: $0.assetID, side: $0.sideRaw, quantity: $0.quantityRaw, unitPrice: $0.unitPriceRaw,
                      fee: $0.feeRaw, date: $0.date, usdTRY: $0.usdTRYRaw, note: $0.note, createdAt: $0.createdAt,
                      goalID: $0.goalID)
            },
            customAssets: try context.fetch(FetchDescriptor<CustomAsset>()).map {
                .init(id: $0.id, name: $0.name, manualPrice: $0.manualPriceRaw, manualPriceDate: $0.manualPriceDate,
                      createdAt: $0.createdAt)
            },
            snapshots: try context.fetch(FetchDescriptor<PriceSnapshot>()).map {
                .init(assetID: $0.assetID, day: $0.day, bid: $0.bidRaw, ask: $0.askRaw, mid: $0.midRaw, source: $0.sourceRaw,
                      asOf: $0.asOf, isDerived: $0.isDerived)
            },
            budgets: try context.fetch(FetchDescriptor<Budget>()).map {
                .init(id: $0.id, categoryID: $0.category?.id, isOverall: $0.isOverall, history: $0.historyRaw, createdAt: $0.createdAt)
            },
            recurringRules: try context.fetch(FetchDescriptor<RecurringRule>()).map {
                .init(id: $0.id, kind: $0.kindRaw, amount: $0.amountRaw, isAmountVariable: $0.isAmountVariable,
                      accountID: $0.account?.id, categoryID: $0.category?.id, merchant: $0.merchant, note: $0.note,
                      frequency: $0.frequencyRaw, start: $0.start, end: $0.end, maxCount: $0.maxCount, lastDue: $0.lastDue,
                      isPaused: $0.isPaused, createdAt: $0.createdAt)
            },
            priceAlerts: try context.fetch(FetchDescriptor<PriceAlert>()).map {
                .init(id: $0.id, assetID: $0.assetID, direction: $0.directionRaw, threshold: $0.thresholdRaw,
                      priceKind: $0.priceKindRaw, lastSatisfied: $0.lastSatisfied, isActive: $0.isActive, firedAt: $0.firedAt,
                      firedPrice: $0.firedPrice, createdAt: $0.createdAt)
            },
            goals: try context.fetch(FetchDescriptor<Goal>()).map {
                .init(id: $0.id, name: $0.name, kind: $0.kindRaw, assetID: $0.assetID, target: $0.targetRaw,
                      deadline: $0.deadline, isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            plans: try context.fetch(FetchDescriptor<SavingsPlan>()).map {
                .init(id: $0.id, assetID: $0.assetID, target: $0.targetRaw, trigger: $0.triggerRaw, start: $0.start,
                      goalID: $0.goalID, isActive: $0.isActive, createdAt: $0.createdAt)
            },
            people: try context.fetch(FetchDescriptor<Person>()).map {
                .init(id: $0.id, name: $0.name, contactID: $0.contactID, remindAt: $0.remindAt, isArchived: $0.isArchived,
                      createdAt: $0.createdAt)
            },
            debts: try context.fetch(FetchDescriptor<DebtRecord>()).map {
                .init(id: $0.id, personID: $0.personID, kind: $0.kindRaw, amount: $0.amountRaw, date: $0.date,
                      transactionID: $0.transactionID, note: $0.note, createdAt: $0.createdAt)
            })
    }
}

/// JSON yedeğin biçimi. Alanlar depodaki kanonik metinlerle birebir (Decimal → String, enum → rawValue);
/// böylece yedek kuruşu kuruşuna geri döner. Yeni alan eklemek geriye uyumludur (opsiyonel); alan
/// kaldırmak ya da anlam değiştirmek `currentVersion`'ı artırır.
struct Backup: Codable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var accounts: [Account]
    var categories: [Category]
    var transactions: [Transaction]
    var merchantMemories: [Memory]
    var trades: [TradeRecord]
    var customAssets: [Custom]
    var snapshots: [Snapshot]
    var budgets: [BudgetRecord]
    var recurringRules: [Rule]
    var priceAlerts: [Alert]
    /// Sonradan eklendi; eski yedeklerde yok.
    var goals: [GoalRecord]?
    /// Sonradan eklendi (specs/10 §7); eski yedeklerde yok.
    var plans: [PlanRecord]?
    /// Alacak/borç (specs/10 §4); eski yedeklerde yok.
    var people: [PersonRecord]?
    var debts: [DebtRecordBackup]?
    /// Kira sözleşmeleri (specs/12); eski yedeklerde yok.
    var rents: [RentRecord]?
    /// Krediler (specs/13); eski yedeklerde yok.
    var loans: [LoanRecord]?

    struct Account: Codable {
        var id: UUID; var name: String; var kind: String; var currency: String; var openingBalance: String
        var statementDay: Int?; var paymentDueDay: Int?; var isArchived: Bool; var sortIndex: Int; var createdAt: Date
        /// Kart limiti (specs/11 §6); eski yedeklerde yok.
        var creditLimit: String?
    }
    struct Category: Codable {
        var id: UUID; var seedKey: String?; var name: String; var kind: String; var symbol: String; var color: String
        var sortIndex: Int; var isArchived: Bool; var parentID: UUID?
    }
    struct Transaction: Codable {
        var id: UUID; var date: Date; var amount: String; var currency: String; var kind: String; var status: String
        var origin: String; var merchant: String?; var note: String; var createdAt: Date; var updatedAt: Date
        var accountID: UUID?; var toAccountID: UUID?; var categoryID: UUID?; var recurrenceID: UUID?; var dueDay: Date?
        var installmentPlanID: UUID?; var installmentIndex: Int?; var installmentCount: Int?
        var shared: String?
    }
    struct Memory: Codable {
        var key: String; var displayName: String; var lastUsed: Date; var useCount: Int; var categoryID: UUID
    }
    struct TradeRecord: Codable {
        var id: UUID; var assetID: String; var side: String; var quantity: String; var unitPrice: String; var fee: String
        var date: Date; var usdTRY: String?; var note: String; var createdAt: Date; var goalID: UUID?
    }
    struct Custom: Codable {
        var id: UUID; var name: String; var manualPrice: String?; var manualPriceDate: Date?; var createdAt: Date
    }
    struct Snapshot: Codable {
        var assetID: String; var day: Date; var bid: String?; var ask: String?; var mid: String; var source: String
        var asOf: Date; var isDerived: Bool
    }
    struct BudgetRecord: Codable {
        var id: UUID; var categoryID: UUID?; var isOverall: Bool; var history: String; var createdAt: Date
    }
    struct Rule: Codable {
        var id: UUID; var kind: String; var amount: String; var isAmountVariable: Bool; var accountID: UUID?
        var categoryID: UUID?; var merchant: String?; var note: String; var frequency: String; var start: Date
        var end: Date?; var maxCount: Int?; var lastDue: Date?; var isPaused: Bool; var createdAt: Date
    }
    struct GoalRecord: Codable {
        var id: UUID; var name: String; var kind: String; var assetID: String?; var target: String; var deadline: Date?
        var isArchived: Bool; var createdAt: Date
    }
    struct PersonRecord: Codable {
        var id: UUID; var name: String; var contactID: String?; var remindAt: Date?; var isArchived: Bool; var createdAt: Date
    }
    struct DebtRecordBackup: Codable {
        var id: UUID; var personID: UUID; var kind: String; var amount: String; var date: Date; var transactionID: UUID?
        var note: String; var createdAt: Date
    }
    struct LoanRecord: Codable {
        var id: UUID; var name: String; var kind: String; var principal: String; var monthlyRate: String
        var taxRate: String; var termMonths: Int; var firstDue: Date; var payment: String; var isVariableRate: Bool
        var accountID: UUID?; var categoryID: UUID?; var paidCount: Int; var payments: String; var closedAt: Date?
        var closingTransactionID: UUID?; var createdAt: Date
    }
    struct PlanRecord: Codable {
        var id: UUID; var assetID: String; var target: String; var trigger: String; var start: Date; var goalID: UUID?
        var isActive: Bool; var createdAt: Date
    }
    struct Alert: Codable {
        var id: UUID; var assetID: String; var direction: String; var threshold: String; var priceKind: String
        var lastSatisfied: Bool?; var isActive: Bool; var firedAt: Date?; var firedPrice: String?; var createdAt: Date
    }
}

// MARK: Krediler (specs/13)

extension ExchangeStore {
    func loanRecords() throws -> [Backup.LoanRecord] {
        try context.fetch(FetchDescriptor<Loan>()).map {
            .init(id: $0.id, name: $0.name, kind: $0.kindRaw, principal: $0.principalRaw, monthlyRate: $0.monthlyRateRaw,
                  taxRate: $0.taxRateRaw, termMonths: $0.termMonths, firstDue: $0.firstDue, payment: $0.paymentRaw,
                  isVariableRate: $0.isVariableRate, accountID: $0.accountID, categoryID: $0.categoryID,
                  paidCount: $0.paidCount, payments: $0.paymentIDsRaw, closedAt: $0.closedAt,
                  closingTransactionID: $0.closingTransactionID, createdAt: $0.createdAt)
        }
    }

    func restoreLoans(_ records: [Backup.LoanRecord]) throws {
        let existing = Set(try context.fetch(FetchDescriptor<Loan>()).map(\.id))
        for record in records where !existing.contains(record.id) {
            guard let principal = Decimal(canonical: record.principal), let rate = Decimal(canonical: record.monthlyRate)
            else { continue }
            let terms = LoanTerms(kind: LoanKind(rawValue: record.kind) ?? .personal, principal: principal, monthlyRate: rate,
                                  taxRate: Decimal(canonical: record.taxRate), termMonths: record.termMonths,
                                  firstDue: record.firstDue, payment: Decimal(canonical: record.payment),
                                  isVariableRate: record.isVariableRate)
            let loan = Loan(name: record.name, terms: terms)
            loan.id = record.id
            loan.accountID = record.accountID
            loan.categoryID = record.categoryID
            loan.paidCount = record.paidCount
            loan.paymentIDsRaw = record.payments
            loan.closedAt = record.closedAt
            loan.closingTransactionID = record.closingTransactionID
            loan.createdAt = record.createdAt
            context.insert(loan)
        }
    }
}
