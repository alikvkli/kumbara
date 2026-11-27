import Foundation
import KumbaraCore
import SwiftData

public enum LedgerStoreError: Error, Equatable {
    case invalid([TransactionDraft.Issue])
    case accountNotFound
    case categoryNotFound
}

/// Defter yazma işlemlerinin tek kapısı: doğrulama Core'da, kalıcılık burada.
@MainActor
public struct LedgerStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Yazma

    /// Yeni kayıt oluşturur veya `editing` kaydını günceller. Kayıt sonrası satıcı hafızası güncellenir.
    @discardableResult
    public func save(_ draft: TransactionDraft, origin: TransactionOrigin = .manual,
                     status: TransactionStatus = .posted, editing: LedgerTransaction? = nil,
                     now: Date = .now) throws -> LedgerTransaction {
        let issues = draft.issues
        guard issues.isEmpty, let amount = draft.amount, let accountRef = draft.account else {
            throw LedgerStoreError.invalid(issues)
        }
        guard let account = try account(id: accountRef.id) else { throw LedgerStoreError.accountNotFound }

        let toAccount: LedgerAccount?
        if draft.kind == .transfer, let ref = draft.toAccount {
            guard let found = try self.account(id: ref.id) else { throw LedgerStoreError.accountNotFound }
            toAccount = found
        } else {
            toAccount = nil
        }

        var category: LedgerCategory?
        if draft.kind != .transfer, let ref = draft.category {
            guard let found = try self.category(id: ref.id) else { throw LedgerStoreError.categoryNotFound }
            category = found
        }

        let money = Money(amount, account.currency)
        let transaction: LedgerTransaction
        if let editing {
            transaction = editing
            transaction.amount = money
            transaction.kind = draft.kind
            transaction.date = draft.date
            transaction.status = status
            transaction.updatedAt = now
        } else {
            transaction = LedgerTransaction(date: draft.date, amount: money, kind: draft.kind,
                                            status: status, origin: origin)
            transaction.createdAt = now
            transaction.updatedAt = now
            context.insert(transaction)
        }
        transaction.account = account
        transaction.toAccount = toAccount
        transaction.category = category
        transaction.merchant = draft.kind == .transfer ? nil : draft.trimmedMerchant
        transaction.merchantKey = transaction.merchant.map(MerchantKey.normalize) ?? ""
        transaction.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        if status == .posted, let merchant = transaction.merchant, let category {
            try remember(merchant: merchant, category: category, at: draft.date)
        }

        try context.save()
        return transaction
    }

    public func delete(_ transaction: LedgerTransaction) throws {
        context.delete(transaction)
        try context.save()
    }

    // MARK: Okuma

    public func account(id: UUID) throws -> LedgerAccount? {
        var descriptor = FetchDescriptor<LedgerAccount>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func category(id: UUID) throws -> LedgerCategory? {
        var descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Varsayılan kategoriyi kalıcı anahtarıyla bulur (OCR önerisi → kategori).
    public func category(seedKey: String) throws -> LedgerCategory? {
        var descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.seedKey == seedKey })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.flatMap { $0.isArchived ? nil : $0 }
    }

    /// Bir tarihin ±`days` gün çevresindeki kayıtlar (mükerrer kontrolü, REQ-C6).
    public func entries(around date: Date, days: Int = 1, calendar: Calendar = .current) throws -> [LedgerEntry] {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -days, to: day)!
        let end = calendar.date(byAdding: .day, value: days + 1, to: day)!
        return try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.date >= start && $0.date < end }))
            .map(\.entry)
    }

    public func activeAccounts() throws -> [LedgerAccount] {
        try context.fetch(FetchDescriptor<LedgerAccount>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        ))
    }

    /// Hızlı eklemede ön seçili hesap: son kaydın hesabı, yoksa sıradaki ilk aktif hesap.
    public func defaultAccount() throws -> LedgerAccount? {
        var recent = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recent.fetchLimit = 1
        if let account = try context.fetch(recent).first?.account, !account.isArchived {
            return account
        }
        return try activeAccounts().first
    }

    /// Son kullanılan kategoriler (yeniden eskiye, tekil), hızlı seçim için.
    public func recentCategories(kind: CategoryKind, limit: Int = 6) throws -> [LedgerCategory] {
        var descriptor = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 200
        var seen = Set<UUID>()
        var result: [LedgerCategory] = []
        for transaction in try context.fetch(descriptor) {
            guard let category = transaction.category, category.kind == kind, !category.isArchived,
                  seen.insert(category.id).inserted else { continue }
            result.append(category)
            if result.count == limit { break }
        }
        return result
    }

    public func entries(in month: LedgerMonth, calendar: Calendar) throws -> [LedgerEntry] {
        let interval = month.interval(in: calendar)
        let start = interval.start, end = interval.end
        let descriptor = FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return try context.fetch(descriptor).map(\.entry)
    }

    public func summary(for month: LedgerMonth, currency: CurrencyCode, calendar: Calendar) throws -> MonthlySummary {
        MonthlySummary(entries: try entries(in: month, calendar: calendar), month: month,
                       currency: currency, calendar: calendar)
    }

    // MARK: Satıcı hafızası (REQ-L6)

    private func ruleBook() throws -> (MerchantRuleBook, [String: MerchantMemory]) {
        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let byKey = Dictionary(memories.map { ($0.key, $0) }, uniquingKeysWith: { $0.lastUsed >= $1.lastUsed ? $0 : $1 })
        return (MerchantRuleBook(byKey.values.compactMap(\.rule)), byKey)
    }

    public func suggestedCategory(forMerchant merchant: String) throws -> LedgerCategory? {
        let (book, _) = try ruleBook()
        guard let id = book.suggestedCategory(for: merchant), let category = try category(id: id),
              !category.isArchived else { return nil }
        return category
    }

    public func merchantCompletions(for prefix: String, limit: Int = 5) throws -> [MerchantMemory] {
        let (book, byKey) = try ruleBook()
        return book.completions(for: prefix, limit: limit).compactMap { byKey[$0.key] }
    }

    private func remember(merchant: String, category: LedgerCategory, at date: Date) throws {
        var (book, byKey) = try ruleBook()
        guard let rule = book.record(merchant: merchant, categoryID: category.id, at: date) else { return }
        if let memory = byKey[rule.key] {
            memory.displayName = rule.displayName
            memory.lastUsed = rule.lastUsed
            memory.useCount = rule.useCount
            if memory.category?.id != rule.categoryID {
                if rule.categoryID == category.id {
                    memory.category = category
                } else {
                    memory.category = try self.category(id: rule.categoryID)
                }
            }
        } else {
            context.insert(MerchantMemory(key: rule.key, displayName: rule.displayName, category: category,
                                          lastUsed: rule.lastUsed, useCount: rule.useCount))
        }
    }
}
