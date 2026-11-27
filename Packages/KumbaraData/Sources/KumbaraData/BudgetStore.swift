import Foundation
import KumbaraCore
import SwiftData

/// Bütçe okuma/yazma ve bildirim defteri (specs/08 §1). Hesap `BudgetMath`'tedir.
@MainActor
public struct BudgetStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func budgets() throws -> [Budget] {
        try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { $0.isOverall || $0.category != nil }
    }

    public func categoryIndex() throws -> CategoryIndex {
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        var parent: [UUID: UUID] = [:]
        var expense: Set<UUID> = []
        for category in categories {
            if let up = category.parent { parent[category.id] = up.id }
            if category.kind == .expense { expense.insert(category.id) }
        }
        return CategoryIndex(parent: parent, expense: expense)
    }

    /// Ayın bütçe durumları; `rate` döviz giderlerini TRY'ye çevirir.
    public func statuses(for month: LedgerMonth, today: Date = .now, calendar: Calendar,
                         rate: (CurrencyCode, Date) -> Decimal? = { _, _ in nil }) throws -> [BudgetStatus] {
        BudgetMath.statuses(try budgets().map(\.spec), entries: try LedgerStore(context: context).entries(in: month, calendar: calendar),
                            categories: try categoryIndex(), month: month, today: today, calendar: calendar, rate: rate)
    }

    /// `category == nil` genel bütçe. Varsa limiti `month`tan itibaren değiştirir, yoksa oluşturur.
    @discardableResult
    public func setLimit(_ limit: Decimal, for category: LedgerCategory?, from month: LedgerMonth) throws -> Budget {
        let existing = try budgets().first { category == nil ? $0.isOverall : $0.category?.id == category?.id }
        let budget = existing ?? Budget(category: category, history: BudgetLimitHistory())
        if existing == nil { context.insert(budget) }
        var history = budget.history
        history.set(limit, from: month)
        budget.history = history
        try context.save()
        return budget
    }

    public func delete(_ budget: Budget) throws {
        context.delete(budget)
        try context.save()
    }

    /// `month`tan önceki 3 ayın harcaması (en eskiden yeniye). `category == nil`: tüm giderler.
    public func recentSpending(for category: LedgerCategory?, before month: LedgerMonth, calendar: Calendar) throws -> [Decimal] {
        let index = try categoryIndex()
        let ledger = LedgerStore(context: context)
        let months = [month.previous.previous.previous, month.previous.previous, month.previous]
        var history = BudgetLimitHistory()
        history.set(1, from: months[0])
        let spec = BudgetSpec(categoryID: category?.id, history: history)
        return try months.map { item in
            BudgetMath.statuses([spec], entries: try ledger.entries(in: item, calendar: calendar), categories: index,
                                month: item, today: .distantFuture, calendar: calendar).first?.spent.amount ?? 0
        }
    }

    public func suggestedLimit(for category: LedgerCategory?, before month: LedgerMonth, calendar: Calendar) throws -> Decimal? {
        BudgetMath.suggestedLimit(monthlySpending: try recentSpending(for: category, before: month, calendar: calendar))
    }

    /// Önerilen limitler: bütçesi olmayan üst gider kategorileri, son 3 ayda en çok harcanandan aza.
    public func suggestions(before month: LedgerMonth, calendar: Calendar, limit: Int = 5) throws -> [(category: LedgerCategory, limit: Decimal)] {
        let budgeted = Set(try budgets().compactMap { $0.category?.id })
        let tops = try context.fetch(FetchDescriptor<LedgerCategory>())
            .filter { $0.kind == .expense && $0.parent == nil && !$0.isArchived && !budgeted.contains($0.id) }
        let ranked: [(LedgerCategory, Decimal, Decimal)] = try tops.compactMap { category in
            let spending = try recentSpending(for: category, before: month, calendar: calendar)
            guard let suggested = BudgetMath.suggestedLimit(monthlySpending: spending) else { return nil }
            return (category, suggested, spending.reduce(0, +))
        }
        return ranked
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0.sortIndex < $1.0.sortIndex }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    // MARK: Bildirim defteri

    public func wasNotified(_ key: String) throws -> Bool {
        try context.fetchCount(FetchDescriptor<NotificationLog>(predicate: #Predicate { $0.key == key })) > 0
    }

    public func markNotified(_ key: String) throws {
        guard try !wasNotified(key) else { return }
        context.insert(NotificationLog(key: key))
        try context.save()
    }

    public static func notificationKey(budget: UUID, month: LedgerMonth, threshold: Int) -> String {
        "budget:\(budget.uuidString):\(month.year)-\(month.month):\(threshold)"
    }
}
