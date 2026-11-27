import Foundation
import KumbaraCore
import SwiftData

/// Taksitli alım ve kart ekstresi (REQ-L8, L9; specs/08 §3).
@MainActor
public struct InstallmentStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// `draft.amount` toplam tutardır; `count` taksite bölünür. Tarihi gelmiş taksit kesinleşir,
    /// gelecektekiler planlanmış olarak bekler (bütçe ve bakiyeye tarihi gelince girer).
    @discardableResult
    public func save(_ draft: TransactionDraft, count: Int, now: Date = .now, calendar: Calendar = .current) throws -> [LedgerTransaction] {
        guard count > 1, let total = draft.amount else {
            return [try LedgerStore(context: context).save(draft, now: now)]
        }
        let ledger = LedgerStore(context: context)
        let plan = UUID()
        let parts = Installments.split(total, count: count)
        let dates = Installments.dates(purchase: draft.date, count: count, calendar: calendar)
        var result: [LedgerTransaction] = []
        for (index, (amount, date)) in zip(parts, dates).enumerated() {
            var part = draft
            part.amount = amount
            part.date = date
            let transaction = try ledger.save(part, status: date <= now ? .posted : .planned, now: now)
            transaction.installmentPlanID = plan
            transaction.installmentIndex = index + 1
            transaction.installmentCount = count
            result.append(transaction)
        }
        try context.save()
        return result
    }

    /// Tarihi gelen planlanmış taksitleri kesinleştirir (uygulama öne gelince).
    @discardableResult
    public func postDue(now: Date = .now) throws -> Int {
        let planned = TransactionStatus.planned.rawValue
        let due = try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.statusRaw == planned && $0.date <= now }))
        for transaction in due { transaction.status = .posted }
        if !due.isEmpty { try context.save() }
        return due.count
    }

    /// Planın gelecek taksitleri; kesinleşmişler korunur.
    public func cancelRemaining(of planID: UUID) throws {
        let id: UUID? = planID
        let planned = TransactionStatus.planned.rawValue
        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.installmentPlanID == id && $0.statusRaw == planned })) {
            context.delete(transaction)
        }
        try context.save()
    }

    /// Kart hesabının ekstre özeti; kesim günü tanımlı değilse `nil`.
    public func statement(for account: LedgerAccount, now: Date = .now, calendar: Calendar = .current) throws -> CardStatement? {
        guard account.kind == .card, let day = account.statementDay else { return nil }
        let entries = (account.transactions ?? []).map(\.entry) + (account.incomingTransfers ?? []).map(\.entry)
        return CardStatement(entries: entries, cardID: account.id, currency: account.currency, statementDay: day,
                             dueDay: account.paymentDueDay, now: now, calendar: calendar)
    }

    public func upcomingInstallments(for account: LedgerAccount) -> [LedgerTransaction] {
        (account.transactions ?? []).filter { $0.status == .planned }.sorted { $0.date < $1.date }
    }
}
