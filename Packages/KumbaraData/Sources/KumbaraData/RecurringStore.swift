import Foundation
import KumbaraCore
import SwiftData

/// Tekrarlayan işlemler (REQ-L7, specs/08 §2): kural yönetimi ve vadesi gelen taslakların üretimi.
@MainActor
public struct RecurringStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func rules() throws -> [RecurringRule] {
        try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Kaydedilmiş bir işlemden kural: işlemin kendisi ilk vadedir, sonraki vadeler taslak olur.
    @discardableResult
    public func makeRule(from transaction: LedgerTransaction, frequency: RecurrenceFrequency,
                         isAmountVariable: Bool = false, end: Date? = nil, maxCount: Int? = nil,
                         calendar: Calendar = .current) throws -> RecurringRule {
        let rule = RecurringRule(kind: transaction.kind, amount: transaction.amount.amount, frequency: frequency,
                                 start: calendar.startOfDay(for: transaction.date))
        rule.account = transaction.account
        rule.category = transaction.category
        rule.merchant = transaction.merchant
        rule.note = transaction.note
        rule.isAmountVariable = isAmountVariable
        rule.end = end
        rule.maxCount = maxCount
        context.insert(rule)
        // İşlemin günü bir vadeyse o vade "üretilmiş" sayılır; değilse ilk vade ondan sonra gelir.
        let day = calendar.startOfDay(for: transaction.date)
        if rule.schedule?.occurrences(calendar: calendar, limit: 1).first == day {
            rule.lastDue = day
            transaction.recurrenceID = rule.id
            transaction.dueDay = day
        } else {
            rule.lastDue = calendar.date(byAdding: .day, value: -1, to: day)
        }
        try context.save()
        return rule
    }

    /// Vadesi gelmiş (bugün dahil) her tekrar için bir taslak. Tekrar çağrılınca yeni taslak oluşmaz.
    @discardableResult
    public func generateDrafts(now: Date = .now, calendar: Calendar = .current) throws -> [LedgerTransaction] {
        var created: [LedgerTransaction] = []
        for rule in try rules() where !rule.isPaused {
            guard let schedule = rule.schedule, let account = rule.account, rule.amount > 0 else { continue }
            let dues = schedule.due(after: rule.lastDue, through: now, calendar: calendar)
            guard !dues.isEmpty else { continue }
            let ruleID: UUID? = rule.id
            let existing = Set(try context.fetch(FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.recurrenceID == ruleID })).compactMap(\.dueDay))
            for due in dues where !existing.contains(due) {
                let date = calendar.date(byAdding: .hour, value: 12, to: due) ?? due
                let transaction = LedgerTransaction(date: date, amount: Money(rule.amount, account.currency), kind: rule.kind,
                                                    status: .draft, origin: .recurring)
                transaction.account = account
                transaction.category = rule.category
                transaction.merchant = rule.merchant
                transaction.merchantKey = rule.merchant.map(MerchantKey.normalize) ?? ""
                transaction.note = rule.note
                transaction.recurrenceID = rule.id
                transaction.dueDay = due
                context.insert(transaction)
                created.append(transaction)
            }
            rule.lastDue = dues.last
        }
        try context.save()
        return created
    }

    public func pendingDrafts() throws -> [LedgerTransaction] {
        let draft = TransactionStatus.draft.rawValue
        return try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == draft }, sortBy: [SortDescriptor(\.date)]))
    }

    /// Taslağı kesinleştirir (satıcı hafızası da öğrenir). Tutar düzenlendiyse `amount` ile.
    public func approve(_ transaction: LedgerTransaction, amount: Decimal? = nil) throws {
        var draft = transaction.draft
        if let amount { draft.amount = amount }
        try LedgerStore(context: context).save(draft, origin: transaction.origin, status: .posted, editing: transaction)
        if let amount, let id = transaction.recurrenceID, let rule = try rules().first(where: { $0.id == id }), !rule.isAmountVariable {
            rule.amount = amount  // Sabit tutarlı kuralda yeni tutar sonraki vadeler için de geçerli.
            try context.save()
        }
    }

    /// Bu vadeyi atla: taslak silinir, kural yeniden üretmez (`lastDue` ilerlemiştir).
    public func skip(_ transaction: LedgerTransaction) throws {
        context.delete(transaction)
        try context.save()
    }

    /// Kural silinir; onay bekleyen taslakları da gider, kesinleşmiş kayıtlar kalır.
    public func delete(_ rule: RecurringRule) throws {
        let ruleID: UUID? = rule.id
        let draft = TransactionStatus.draft.rawValue
        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.recurrenceID == ruleID && $0.statusRaw == draft })) {
            context.delete(transaction)
        }
        context.delete(rule)
        try context.save()
    }
}
