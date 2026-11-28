import Foundation
import KumbaraCore
import SwiftData

/// Kira sözleşmeleri ve yenileme hesabı (REQ-I9, specs/12).
@MainActor
public struct RentStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func contracts() throws -> [RentContract] {
        try context.fetch(FetchDescriptor<RentContract>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @discardableResult
    public func add(name: String, role: RentIncrease.Role, start: Date, rent: Decimal,
                    recurringRuleID: UUID? = nil, calendar: Calendar = .current) throws -> RentContract {
        let contract = RentContract(name: name, role: role, start: calendar.startOfDay(for: start), rent: rent)
        contract.recurringRuleID = recurringRuleID
        context.insert(contract)
        try context.save()
        return contract
    }

    public func save() throws { try context.save() }

    public func delete(_ contract: RentContract) throws {
        context.delete(contract)
        try context.save()
    }

    /// Sıradaki (ya da son 45 günde yapılmış) yenilemenin hesabı.
    public func quote(for contract: RentContract, now: Date = .now, cpi: RealReturn.CPITable = CPIData.turkey,
                      calendar: Calendar = .current) -> RentIncrease.Quote {
        RentIncrease.quote(start: contract.start, currentRent: contract.rent, now: now, cpi: cpi,
                           manualRate: contract.manualRate, calendar: calendar)
    }

    /// Tabloda olmayan ay için TÜİK'in açıkladığı oranı kaydeder (`nil` siler).
    public func setManualRate(_ rate: Decimal?, month: LedgerMonth, for contract: RentContract) throws {
        contract.manualRate = rate.map { (month, $0) }
        try context.save()
    }

    /// Kararlaştırılan yeni kirayı yazar. Bağlı tekrarlayan kural varsa sonraki taslaklar yeni tutarla gelir;
    /// geçmiş kayıtlar değişmez. Elle girilen oran işini bitirdiği için silinir.
    public func applyNewRent(_ amount: Decimal, to contract: RentContract) throws {
        contract.rent = amount
        contract.manualRate = nil
        if let rule = try linkedRule(of: contract) { rule.amount = amount }
        try context.save()
    }

    public func linkedRule(of contract: RentContract) throws -> RecurringRule? {
        guard let id = contract.recurringRuleID else { return nil }
        return try context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.id == id })).first
    }

    /// Bağlanabilecek kurallar: kira gideri ya da kira geliri kategorisindeki tekrarlar önce.
    public func candidateRules() throws -> [RecurringRule] {
        let rules = try RecurringStore(context: context).rules()
        func isRent(_ rule: RecurringRule) -> Bool {
            [rule.category?.seedKey, rule.category?.parent?.seedKey].contains { $0 == "housing.rent" || $0 == "rental" }
        }
        return rules.filter(isRent) + rules.filter { !isRent($0) }
    }
}
