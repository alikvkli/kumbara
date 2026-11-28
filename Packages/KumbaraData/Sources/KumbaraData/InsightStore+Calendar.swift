import Foundation
import KumbaraCore
import SwiftData

/// Ödeme takvimi kaynakları (specs/10 §5, kredi taksitleri specs/13). Kartla ödenen tekrarlar ve abonelikler ayrı kalem değildir;
/// kart son ödemesinin içindedir (çift sayım olmasın).
extension InsightStore {
    public func upcomingPayments(from: Date = .now, days: Int = 62, now: Date = .now,
                                 calendar: Calendar = .current) throws -> [UpcomingPayment] {
        let start = calendar.startOfDay(for: from)
        let through = calendar.date(byAdding: .day, value: days, to: start) ?? start
        var items: [UpcomingPayment] = []

        for rule in try RecurringStore(context: context).rules() where !rule.isPaused {
            guard let schedule = rule.schedule, let account = rule.account, account.currency == .TRY,
                  rule.kind != .transfer else { continue }
            if rule.kind == .expense, account.kind == .card { continue }
            let title = rule.merchant ?? rule.category?.name ?? (rule.kind == .income ? "Gelir" : "Tekrarlayan işlem")
            items += PaymentCalendar.recurring(id: rule.id, title: title, amount: rule.amount, isIncome: rule.kind == .income,
                                               schedule: schedule, lastDue: rule.lastDue, from: start, through: through,
                                               calendar: calendar)
        }

        let accounts = try context.fetch(FetchDescriptor<LedgerAccount>()).filter { !$0.isArchived }
        let installments = InstallmentStore(context: context)
        for card in accounts where card.kind == .card && card.currency == .TRY {
            guard let statement = try installments.statement(for: card, now: now, calendar: calendar) else { continue }
            items += PaymentCalendar.card(id: card.id, name: card.name, statement: statement, from: start, through: through,
                                          calendar: calendar)
        }

        items += try LoanStore(context: context).upcoming(from: start, through: through, calendar: calendar)

        let onCard = try merchantKeysPaidByCard()
        let subscriptions = try subscriptions(now: now, calendar: calendar).filter { !onCard.contains($0.merchantKey) }
        items += PaymentCalendar.subscriptions(subscriptions, from: start, through: through, calendar: calendar)
        return PaymentCalendar.sorted(items)
    }

    /// Nakit ve banka hesaplarının (TRY) toplam bakiyesi; kart ve birikim hesabı hariç.
    public func liquidBalance() throws -> Decimal? {
        let accounts = try context.fetch(FetchDescriptor<LedgerAccount>())
            .filter { !$0.isArchived && $0.currency == .TRY && ($0.kind == .cash || $0.kind == .bank) }
        guard !accounts.isEmpty else { return nil }
        return accounts.reduce(Decimal(0)) { $0 + $1.balance.amount }
    }

    /// Son ödemesi kartla yapılan satıcılar.
    func merchantKeysPaidByCard() throws -> Set<String> {
        let posted = TransactionStatus.posted.rawValue
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == posted && $0.merchantKey != "" },
            sortBy: [SortDescriptor(\.date)]))
        var latest: [String: Bool] = [:]
        for transaction in transactions { latest[transaction.merchantKey] = transaction.account?.kind == .card }
        return Set(latest.filter(\.value).keys)
    }
}
