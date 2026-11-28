import Foundation
import KumbaraCore
import SwiftData

public typealias Loan = SchemaV1.Loan

/// Krediler (REQ-I10, specs/13). Ödenen taksit seçilen hesaptan gider olarak yazılır (bütçeye girer,
/// tekrarlayan taslaklar gibi kullanıcı "Ödendi" deyince). Satıcı anahtarı boş bırakılır: abonelik ya da
/// hızlı ekleme önerisine karışmaz.
@MainActor
public struct LoanStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public enum LoanError: Error, Equatable { case invalid, nothingToPay, nothingToUndo }

    public func loans(includeClosed: Bool = true) throws -> [Loan] {
        let all = try context.fetch(FetchDescriptor<Loan>(sortBy: [SortDescriptor(\.createdAt)]))
        return includeClosed ? all : all.filter { !$0.isClosed }
    }

    public func loan(id: UUID) throws -> Loan? {
        try context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    public func save(name: String, terms: LoanTerms, paidCount: Int, accountID: UUID?, categoryID: UUID?,
                     editing: Loan? = nil) throws -> Loan {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, terms.principal > 0, terms.termMonths > 0, terms.monthlyRate >= 0,
              (0...terms.termMonths).contains(paidCount) else { throw LoanError.invalid }
        let loan: Loan
        if let editing {
            editing.apply(terms)
            loan = editing
        } else {
            loan = Loan(name: trimmed, terms: terms)
            context.insert(loan)
        }
        loan.name = trimmed
        // Uygulamada kaydedilen ödemeler sayıdan düşülemez.
        loan.paidCount = max(paidCount, loan.payments.count)
        loan.accountID = accountID
        loan.categoryID = categoryID
        try context.save()
        return loan
    }

    /// Kredi silinir; daha önce yazılan gider kayıtları defterde kalır (gerçekten ödendiler).
    public func delete(_ loan: Loan) throws {
        context.delete(loan)
        try context.save()
    }

    public func schedule(of loan: Loan, calendar: Calendar = .current) -> [LoanInstallment] {
        LoanMath.schedule(loan.terms, calendar: calendar)
    }

    /// Sıradaki taksit.
    public func nextInstallment(of loan: Loan, calendar: Calendar = .current) -> LoanInstallment? {
        guard !loan.isClosed else { return nil }
        let rows = schedule(of: loan, calendar: calendar)
        return loan.paidCount < rows.count ? rows[loan.paidCount] : nil
    }

    /// Sıradaki taksiti öde. `account` verilirse o hesaptan gider yazılır; verilmezse yalnız işaretlenir.
    @discardableResult
    public func markPaid(_ loan: Loan, account: LedgerAccount?, date: Date = .now,
                         calendar: Calendar = .current) throws -> LedgerTransaction? {
        guard let row = nextInstallment(of: loan, calendar: calendar) else { throw LoanError.nothingToPay }
        var transaction: LedgerTransaction?
        if let account {
            let note = String(localized: "Taksit \(row.number) / \(loan.termMonths)")
            transaction = try expense(loan, amount: row.payment, account: account, date: date, note: note)
        }
        loan.payments.append(transaction?.id)
        loan.paidCount += 1
        try context.save()
        return transaction
    }

    /// Son işaretlenen taksiti geri al; uygulamada yazılmış gideri de siler.
    public func undoLastPayment(_ loan: Loan) throws {
        guard loan.paidCount > 0, loan.closedAt == nil else { throw LoanError.nothingToUndo }
        // Uygulamada işaretlenen son ödemenin gider kaydı (hâlâ duruyorsa) silinir; uygulamaya eklenmeden
        // önce ödenmiş sayılan taksitlerin kaydı yoktur.
        var payments = loan.payments
        if let last = payments.popLast() {
            if let id = last,
               let transaction = try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.id == id })).first {
                context.delete(transaction)
            }
            loan.payments = payments
        }
        loan.paidCount -= 1
        try context.save()
    }

    public func payoff(of loan: Loan, on date: Date = .now, calendar: Calendar = .current) -> LoanMath.Payoff? {
        guard loan.closedAt == nil else { return nil }
        return LoanMath.payoff(loan.terms, paidCount: loan.paidCount, on: date, calendar: calendar)
    }

    /// Erken kapama: kapama tutarı hesaptan gider olarak yazılır, kredi kapanır.
    @discardableResult
    public func close(_ loan: Loan, amount: Decimal, account: LedgerAccount?, date: Date = .now) throws -> LedgerTransaction? {
        guard loan.closedAt == nil, amount > 0 else { throw LoanError.nothingToPay }
        var transaction: LedgerTransaction?
        if let account {
            transaction = try expense(loan, amount: amount, account: account, date: date,
                                      note: String(localized: "Erken kapama"))
        }
        loan.closingTransactionID = transaction?.id
        loan.closedAt = date
        try context.save()
        return transaction
    }

    /// Erken kapamayı geri al: kapama gideri silinir, kredi yeniden açılır.
    public func reopen(_ loan: Loan) throws {
        guard loan.closedAt != nil else { return }
        if let id = loan.closingTransactionID,
           let transaction = try context.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.id == id })).first {
            context.delete(transaction)
        }
        loan.closingTransactionID = nil
        loan.closedAt = nil
        try context.save()
    }

    /// Kapanmamış kredilerin kalan anaparası.
    public func totalRemaining(calendar: Calendar = .current) throws -> Decimal {
        try loans(includeClosed: false).reduce(Decimal(0)) { total, loan in
            total + LoanMath.remainingPrincipal(schedule(of: loan, calendar: calendar), paidCount: loan.paidCount,
                                                principal: loan.terms.principal)
        }
    }

    /// Takvim kalemleri (kapanmamış krediler).
    public func upcoming(from: Date, through: Date, calendar: Calendar = .current) throws -> [UpcomingPayment] {
        try loans(includeClosed: false).flatMap { loan in
            PaymentCalendar.loan(id: loan.id, title: loan.name, terms: loan.terms, paidCount: loan.paidCount,
                                 from: from, through: through, calendar: calendar)
        }
    }

    private func expense(_ loan: Loan, amount: Decimal, account: LedgerAccount, date: Date, note: String) throws -> LedgerTransaction {
        let transaction = LedgerTransaction(date: date, amount: Money(amount, account.currency), kind: .expense)
        transaction.account = account
        if let id = loan.categoryID {
            transaction.category = try LedgerStore(context: context).category(id: id)
        }
        transaction.merchant = loan.name
        transaction.merchantKey = ""
        transaction.note = note
        context.insert(transaction)
        return transaction
    }
}
