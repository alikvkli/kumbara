import Foundation
import KumbaraCore
import SwiftData

/// Alacak / borç defteri (REQ-I4, specs/10 §4). Bölme bütçeyi, borç ve kapanışlar yalnız hesap bakiyesini
/// etkiler (transfer olarak; bütçeye girmez).
@MainActor
public struct DebtStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public enum DebtError: Error, Equatable { case invalidAmount, notExpense, sharesExceedTotal }

    // MARK: Kişiler

    public func people() throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    public func addPerson(name: String, contactID: String? = nil) throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try people().first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }
        let person = Person(name: trimmed, contactID: contactID)
        context.insert(person)
        try context.save()
        return person
    }

    public func archive(_ person: Person) throws {
        person.isArchived = true
        try context.save()
    }

    // MARK: Kayıtlar

    /// Silinmiş işleme bağlı bölme kayıtları sayılmaz (işlem silinince alacak da düşer).
    public func records(for personID: UUID? = nil) throws -> [DebtRecord] {
        let all = try context.fetch(FetchDescriptor<DebtRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let transactionIDs = Set(try context.fetch(FetchDescriptor<LedgerTransaction>()).map(\.id))
        return all.filter { record in
            (personID == nil || record.personID == personID)
                && (record.transactionID == nil || transactionIDs.contains(record.transactionID!))
        }
    }

    public func balances() throws -> [UUID: Decimal] {
        DebtMath.balances(try records().map(\.entry))
    }

    /// Gideri böl: `shares` kişi → pay. Önceki bölme kayıtlarının yerine geçer; boş liste bölmeyi kaldırır.
    public func split(_ transaction: LedgerTransaction, shares: [(person: Person, amount: Decimal)]) throws {
        guard transaction.kind == .expense else { throw DebtError.notExpense }
        let total = shares.reduce(Decimal(0)) { $0 + $1.amount }
        guard shares.allSatisfy({ $0.amount > 0 }) else { throw DebtError.invalidAmount }
        guard total < transaction.amount.amount else { throw DebtError.sharesExceedTotal }
        let id: UUID? = transaction.id
        let split = DebtKind.split.rawValue
        for old in try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.transactionID == id && $0.kindRaw == split })) {
            context.delete(old)
        }
        for share in shares {
            let record = DebtRecord(personID: share.person.id, kind: .split, amount: share.amount, date: transaction.date,
                                    transactionID: transaction.id)
            record.note = transaction.merchant ?? transaction.category?.name ?? ""
            context.insert(record)
        }
        transaction.sharedAmount = total
        transaction.updatedAt = .now
        try context.save()
    }

    public func splitShares(of transaction: LedgerTransaction) throws -> [DebtRecord] {
        let id: UUID? = transaction.id
        let split = DebtKind.split.rawValue
        return try context.fetch(FetchDescriptor<DebtRecord>(predicate: #Predicate { $0.transactionID == id && $0.kindRaw == split }))
    }

    /// Elden borç: `lent` hesaptan çıkar, `borrowed` hesaba girer (transfer; bütçeye girmez).
    @discardableResult
    public func record(_ kind: DebtKind, person: Person, amount: Decimal, account: LedgerAccount, date: Date = .now,
                       note: String = "") throws -> DebtRecord {
        guard amount > 0 else { throw DebtError.invalidAmount }
        let signed: Decimal
        let outgoing: Bool
        switch kind {
        case .lent: signed = amount; outgoing = true
        case .borrowed: signed = -amount; outgoing = false
        case .settlement:
            let balance = try balances()[person.id] ?? 0
            signed = DebtMath.settlement(amount: amount, balance: balance)
            outgoing = signed > 0   // ben ödüyorum
        case .split: throw DebtError.notExpense
        }
        let transaction = LedgerTransaction(date: date, amount: Money(amount, account.currency), kind: .transfer)
        if outgoing { transaction.account = account } else { transaction.toAccount = account }
        transaction.merchant = person.name
        transaction.merchantKey = ""
        transaction.note = note.isEmpty ? Self.defaultNote(kind, outgoing: outgoing) : note
        context.insert(transaction)
        let record = DebtRecord(personID: person.id, kind: kind, amount: signed, date: date, transactionID: transaction.id)
        record.note = transaction.note
        context.insert(record)
        try context.save()
        return record
    }

    static func defaultNote(_ kind: DebtKind, outgoing: Bool) -> String {
        switch kind {
        case .lent: String(localized: "Borç verildi")
        case .borrowed: String(localized: "Borç alındı")
        case .settlement: outgoing ? String(localized: "Borç ödendi") : String(localized: "Alacak tahsil edildi")
        case .split: ""
        }
    }

    public func delete(_ record: DebtRecord) throws {
        // Kişiyle yapılan transfer de silinir; bölünen giderin kendisi kalır, payı geri alınır.
        if let id = record.transactionID,
           let transaction = try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.id == id })).first {
            if record.kind == .split {
                transaction.sharedAmount = max(transaction.sharedAmount - record.amount, 0)
            } else {
                context.delete(transaction)
            }
        }
        context.delete(record)
        try context.save()
    }
}
