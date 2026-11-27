import Foundation
import KumbaraCore
import SwiftData

/// Birikim hedefleri (T5.6, specs/09 §6).
@MainActor
public struct GoalStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func goals() throws -> [Goal] {
        try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.createdAt)]))
    }

    @discardableResult
    public func save(_ goal: SavingsGoal, editing: Goal? = nil) throws -> Goal {
        let record: Goal
        if let editing {
            editing.apply(goal)
            record = editing
        } else {
            record = Goal(goal)
            context.insert(record)
        }
        try context.save()
        return record
    }

    /// Hedef silinince alımlar kalır, yalnız hedef bağı kopar.
    public func delete(_ goal: Goal) throws {
        let id: UUID? = goal.id
        for trade in try context.fetch(FetchDescriptor<AssetTrade>(predicate: #Predicate { $0.goalID == id })) {
            trade.goalID = nil
        }
        context.delete(goal)
        try context.save()
    }

    public func assign(_ trades: [AssetTrade], to goal: Goal?) throws {
        for trade in trades { trade.goalID = goal?.id }
        try context.save()
    }

    public func trades(for goal: Goal) throws -> [AssetTrade] {
        let id: UUID? = goal.id
        return try context.fetch(FetchDescriptor<AssetTrade>(predicate: #Predicate { $0.goalID == id }, sortBy: [SortDescriptor(\.date)]))
    }

    public func progress(of goal: Goal, prices: [AssetCode: Decimal], now: Date = .now,
                         calendar: Calendar = .current) throws -> GoalProgress? {
        guard let value = goal.goal else { return nil }
        return GoalMath.progress(of: value, trades: try trades(for: goal).compactMap(\.trade), prices: prices,
                                 now: now, calendar: calendar)
    }

    /// Miktar hedefinde: aynı varlıktan hedefe atanmamış alımlar ve net miktarları.
    public func unassigned(for goal: Goal) throws -> (trades: [AssetTrade], quantity: Decimal) {
        guard case let .quantity(asset, _)? = goal.goal?.target else { return ([], 0) }
        let all = try context.fetch(FetchDescriptor<AssetTrade>()).filter { $0.asset == asset }
        let free = all.filter { $0.goalID == nil }
        let assignedIDs = Set(all.filter { $0.goalID != nil }.map(\.id))
        let quantity = GoalMath.unassignedQuantity(of: asset, allTrades: all.compactMap(\.trade), assignedTradeIDs: assignedIDs)
        return (free, quantity)
    }
}
