import Foundation
import KumbaraCore
import SwiftData

/// Abonelikler ve aylık rapor için veri toplama (specs/10 §1, §2). Hesaplar KumbaraCore'dadır.
@MainActor
public struct InsightStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Abonelikler

    /// Kesinleşmiş, TRY cinsinden, satıcısı olan giderler; taksitler hariç.
    public func subscriptionPayments() throws -> [SubscriptionDetector.Payment] {
        let posted = TransactionStatus.posted.rawValue
        let expense = TransactionKind.expense.rawValue
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == posted && $0.kindRaw == expense && $0.merchantKey != "" }))
        return transactions.compactMap { transaction in
            guard transaction.installmentPlanID == nil, transaction.amount.currency == .TRY,
                  let name = transaction.merchant else { return nil }
            return SubscriptionDetector.Payment(date: transaction.date, amount: transaction.amount.amount,
                                                merchantKey: transaction.merchantKey, merchantName: name,
                                                isRecurring: transaction.recurrenceID != nil)
        }
    }

    /// Tekrarlayan kuralı olan satıcılar.
    public func trackedMerchantKeys() throws -> Set<String> {
        Set(try RecurringStore(context: context).rules().compactMap { $0.merchant.map(MerchantKey.normalize) }.filter { !$0.isEmpty })
    }

    public func subscriptions(now: Date = .now, calendar: Calendar = .current) throws -> [SubscriptionDetector.Subscription] {
        SubscriptionDetector.detect(try subscriptionPayments(), now: now, calendar: calendar,
                                    trackedKeys: try trackedMerchantKeys(), dismissedKeys: try dismissedSubscriptionKeys())
    }

    /// "Abonelik değil": satıcı bir daha önerilmez. Bir kez yazılan anahtar defterine kaydedilir.
    public func dismissSubscription(_ merchantKey: String) throws {
        try BudgetStore(context: context).markNotified(Self.dismissPrefix + merchantKey)
    }

    public func dismissedSubscriptionKeys() throws -> Set<String> {
        let prefix = Self.dismissPrefix
        let logs = try context.fetch(FetchDescriptor<NotificationLog>(predicate: #Predicate { $0.key.starts(with: prefix) }))
        return Set(logs.map { String($0.key.dropFirst(prefix.count)) })
    }

    static let dismissPrefix = "dismiss:subscription:"

    /// "Tekrarlayan yap": satıcının son ödemesinden kural (onay bekleyen taslaklar üretir, specs/08 §2).
    @discardableResult
    public func makeRecurring(_ subscription: SubscriptionDetector.Subscription,
                              calendar: Calendar = .current) throws -> RecurringRule? {
        let key = subscription.merchantKey
        let posted = TransactionStatus.posted.rawValue
        var descriptor = FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.merchantKey == key && $0.statusRaw == posted },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = try context.fetch(descriptor).first else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: last.date)
        let frequency: RecurrenceFrequency = subscription.cadence == .monthly
            ? .monthly(day: parts.day ?? 1)
            : .yearly(month: parts.month ?? 1, day: parts.day ?? 1)
        return try RecurringStore(context: context).makeRule(from: last, frequency: frequency, calendar: calendar)
    }

    /// Fiyat artışı bildirimi için anahtar: satıcı + zamlı ödemenin günü (aynı artış bir kez bildirilir).
    public static func increaseKey(_ subscription: SubscriptionDetector.Subscription, calendar: Calendar) -> String {
        let day = subscription.payments.last.map { calendar.dateComponents([.year, .month, .day], from: $0.date) }
        return "subscription:\(subscription.merchantKey):\(day?.year ?? 0)-\(day?.month ?? 0)-\(day?.day ?? 0)"
    }

    // MARK: Aylık rapor

    /// Kapanan ayın raporu. Gider dağılımı üst kategorilere toplanır (Özet ile aynı).
    public func report(for month: LedgerMonth, now: Date = .now, calendar: Calendar = .current) throws -> MonthlyReport {
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let entries = transactions.map { transaction in
            var entry = transaction.entry
            entry.categoryID = transaction.category?.parent?.id ?? transaction.category?.id
            return entry
        }
        let lines = try BudgetStore(context: context).statuses(for: month, today: now, calendar: calendar).map {
            MonthlyReport.BudgetLine(categoryID: $0.categoryID, limit: $0.limit.amount, spent: $0.spent.amount)
        }
        let portfolio = PortfolioStore(context: context, calendar: calendar)
        let trades = try portfolio.allTrades().compactMap(\.trade)
        let savings = trades.isEmpty ? nil : MonthlyReport.Savings.compute(
            trades: trades, prices: try portfolio.priceHistory(priceKind: .bid), month: month, now: now,
            calendar: calendar, cpi: CPIData.turkey)
        return MonthlyReport(entries: entries, month: month, calendar: calendar, budgets: lines, savings: savings)
    }

    /// Raporu olan geçmiş aylar (en az bir gider), yeniden eskiye; içinde bulunulan ay hariç.
    public func reportMonths(now: Date = .now, calendar: Calendar = .current) throws -> [LedgerMonth] {
        let posted = TransactionStatus.posted.rawValue
        let expense = TransactionKind.expense.rawValue
        let dates = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == posted && $0.kindRaw == expense })).map(\.date)
        let current = LedgerMonth(containing: now, calendar: calendar)
        return Set(dates.map { LedgerMonth(containing: $0, calendar: calendar) })
            .filter { $0 < current }
            .sorted(by: >)
    }

    public func categories(_ ids: some Sequence<UUID?>) throws -> [UUID: LedgerCategory] {
        let wanted = Set(ids.compactMap { $0 })
        guard !wanted.isEmpty else { return [:] }
        return Dictionary(try context.fetch(FetchDescriptor<LedgerCategory>()).filter { wanted.contains($0.id) }.map { ($0.id, $0) },
                          uniquingKeysWith: { first, _ in first })
    }
}

// MARK: Hızlı ekleme önerisi (specs/10 §6)

extension InsightStore {
    static let dismissSuggestionPrefix = "dismiss:suggestion:"

    public func quickAddSuggestions(now: Date = .now, calendar: Calendar = .current) throws -> [QuickAddSuggester.Suggestion] {
        guard let since = calendar.date(byAdding: .day, value: -95, to: now) else { return [] }
        let posted = TransactionStatus.posted.rawValue
        let expense = TransactionKind.expense.rawValue
        let entries = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == posted && $0.kindRaw == expense && $0.date >= since && $0.merchantKey != "" }))
            .filter { $0.installmentPlanID == nil }
            .map(\.entry)
        let prefix = Self.dismissSuggestionPrefix
        let dismissed = Set(try context.fetch(FetchDescriptor<NotificationLog>(predicate: #Predicate { $0.key.starts(with: prefix) }))
            .map { String($0.key.dropFirst(prefix.count)) })
        return QuickAddSuggester.suggestions(entries: entries, now: now, calendar: calendar, dismissedKeys: dismissed)
    }

    /// "Bunu önerme".
    public func dismissSuggestion(_ merchantKey: String) throws {
        try BudgetStore(context: context).markNotified(Self.dismissSuggestionPrefix + merchantKey)
    }
}
