import Foundation
import KumbaraCore
import SwiftData

/// Kira sözleşmelerinin yedeği (specs/12). Alanlar depodaki kanonik metinlerle birebir.
extension Backup {
    struct RentRecord: Codable {
        var id: UUID; var name: String; var role: String; var start: Date; var rent: String
        var recurringRuleID: UUID?; var manualRateMonth: String?; var manualRate: String?; var createdAt: Date
    }
}

extension ExchangeStore {
    func rentRecords() throws -> [Backup.RentRecord] {
        try context.fetch(FetchDescriptor<RentContract>()).map {
            .init(id: $0.id, name: $0.name, role: $0.roleRaw, start: $0.start, rent: $0.rentRaw,
                  recurringRuleID: $0.recurringRuleID, manualRateMonth: $0.manualRateMonth, manualRate: $0.manualRateRaw,
                  createdAt: $0.createdAt)
        }
    }

    func restoreRents(_ records: [Backup.RentRecord]?) throws {
        let existing = Set(try context.fetch(FetchDescriptor<RentContract>()).map(\.id))
        for record in records ?? [] where !existing.contains(record.id) {
            guard let rent = Decimal(canonical: record.rent) else { continue }
            let contract = RentContract(name: record.name, role: RentIncrease.Role(rawValue: record.role) ?? .tenant,
                                        start: record.start, rent: rent)
            contract.id = record.id
            contract.recurringRuleID = record.recurringRuleID
            contract.manualRateMonth = record.manualRateMonth
            contract.manualRateRaw = record.manualRate
            contract.createdAt = record.createdAt
            context.insert(contract)
        }
    }
}
