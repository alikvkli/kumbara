import Foundation
import KumbaraCore
import SwiftData

/// Altın birikim planları (REQ-I7, specs/10 §7).
@MainActor
public struct PlanStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func plans() throws -> [SavingsPlan] {
        try context.fetch(FetchDescriptor<SavingsPlan>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @discardableResult
    public func save(_ rule: SavingsPlanRule, editing: SavingsPlan? = nil) throws -> SavingsPlan {
        let plan: SavingsPlan
        if let editing {
            editing.apply(rule)
            plan = editing
        } else {
            plan = SavingsPlan(rule)
            context.insert(plan)
        }
        try context.save()
        return plan
    }

    public func delete(_ plan: SavingsPlan) throws {
        context.delete(plan)
        try context.save()
    }

    public func setActive(_ plan: SavingsPlan, _ active: Bool) throws {
        plan.isActive = active
        try context.save()
    }

    /// Maaş kategorisindeki (ve alt kategorilerindeki) kesinleşmiş gelirlerin günleri.
    public func salaryDates() throws -> [Date] {
        let posted = TransactionStatus.posted.rawValue
        let income = TransactionKind.income.rawValue
        return try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { $0.statusRaw == posted && $0.kindRaw == income }))
            .filter { $0.category?.seedKey == "salary" || $0.category?.parent?.seedKey == "salary" }
            .map(\.date)
    }

    public func progress(of plan: SavingsPlan, now: Date = .now, calendar: Calendar = .current) throws -> SavingsPlanProgress? {
        guard let rule = plan.rule else { return nil }
        let trades = try PortfolioStore(context: context, calendar: calendar).trades(for: rule.asset)
        let salaries = rule.trigger == .salary ? try salaryDates() : []
        return SavingsPlanMath.progress(of: rule, trades: trades, salaryDates: salaries, now: now, calendar: calendar)
    }

    /// Maaş gelince sorulacak etkin planlar.
    public func salaryPlans() throws -> [SavingsPlan] {
        try plans().filter { $0.isActive && $0.rule?.trigger == .salary }
    }
}
