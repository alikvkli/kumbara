import Foundation

/// Kredi takibi (REQ-I10, specs/13). Eşit taksitli (anüite) ödeme planı, taksitten faiz oranı,
/// erken kapama tutarı. Hesap yalnız gösterim içindir; banka sözleşmesindeki plan esastır.
///
/// Vergi kuralı: ihtiyaç ve taşıt kredisinde her taksitin faizi üzerinden KKDF (%15) ve BSMV (%15)
/// alınır; konut kredisi ikisinden de muaftır. Taksit, vergi dahil efektif oranla hesaplanır:
/// `r_e = r × (1 + vergi)`.
public enum LoanKind: String, Sendable, Codable, CaseIterable {
    case personal, vehicle, housing

    /// Faiz üzerinden alınan KKDF + BSMV toplamı.
    public var defaultTaxRate: Decimal { self == .housing ? 0 : Decimal(string: "0.30")! }
}

public struct LoanTerms: Hashable, Sendable {
    public var kind: LoanKind
    /// Çekilen tutar.
    public var principal: Decimal
    /// Aylık akdi faiz (vergi hariç), ör. 0,0349.
    public var monthlyRate: Decimal
    /// Faiz üzerinden vergi (KKDF + BSMV), ör. 0,30.
    public var taxRate: Decimal
    public var termMonths: Int
    /// İlk taksitin son ödeme günü; sonrakiler her ay aynı gün (ay kısaysa ayın son günü).
    public var firstDue: Date
    /// Bankanın bildirdiği taksit; verilmezse formülle hesaplanır (kuruşa yuvarlı).
    public var payment: Decimal?
    /// Değişken faizli konut kredisinde erken ödeme tazminatı alınmaz.
    public var isVariableRate: Bool

    public init(kind: LoanKind, principal: Decimal, monthlyRate: Decimal, taxRate: Decimal? = nil, termMonths: Int,
                firstDue: Date, payment: Decimal? = nil, isVariableRate: Bool = false) {
        self.kind = kind
        self.principal = principal
        self.monthlyRate = monthlyRate
        self.taxRate = taxRate ?? kind.defaultTaxRate
        self.termMonths = termMonths
        self.firstDue = firstDue
        self.payment = payment
        self.isVariableRate = isVariableRate
    }

    public var effectiveRate: Decimal { monthlyRate * (1 + taxRate) }
    public var installment: Decimal { payment ?? LoanMath.payment(principal: principal, effectiveRate: effectiveRate, term: termMonths) }
}

public struct LoanInstallment: Hashable, Sendable, Identifiable {
    /// 1'den başlar.
    public var number: Int
    public var due: Date
    public var payment: Decimal
    public var principal: Decimal
    public var interest: Decimal
    /// KKDF + BSMV.
    public var tax: Decimal
    /// Bu taksitten sonra kalan anapara.
    public var balanceAfter: Decimal
    public var id: Int { number }
}

public enum LoanMath {
    /// Anüite taksiti: P × r / (1 − (1 + r)^−n), kuruşa yuvarlı. Faizsizse P / n.
    public static func payment(principal: Decimal, effectiveRate rate: Decimal, term: Int) -> Decimal {
        guard term > 0, principal > 0 else { return 0 }
        return rawPayment(principal: principal, rate: rate, term: term).rounded(scale: 2)
    }

    static func rawPayment(principal: Decimal, rate: Decimal, term: Int) -> Decimal {
        guard rate > 0 else { return principal / Decimal(term) }
        let growth = power(1 + rate, term)
        return principal * rate * growth / (growth - 1)
    }

    static func power(_ base: Decimal, _ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<exponent { result *= base }
        return result
    }

    /// `number`. taksitin vadesi (ilk vade + number−1 ay; kaymaz).
    public static func dueDate(_ terms: LoanTerms, number: Int, calendar: Calendar) -> Date {
        let first = calendar.startOfDay(for: terms.firstDue)
        return calendar.date(byAdding: .month, value: number - 1, to: first) ?? first
    }

    /// Ödeme planı. Faiz ve vergi her satırda kuruşa yuvarlanır; son taksit kalan anaparayı kapatır.
    public static func schedule(_ terms: LoanTerms, calendar: Calendar) -> [LoanInstallment] {
        guard terms.termMonths > 0, terms.principal > 0 else { return [] }
        let payment = terms.installment
        var balance = terms.principal
        var rows: [LoanInstallment] = []
        for number in 1...terms.termMonths {
            let interest = (balance * terms.monthlyRate).rounded(scale: 2)
            let tax = (interest * terms.taxRate).rounded(scale: 2)
            var principal = payment - interest - tax
            if number == terms.termMonths || principal > balance { principal = balance }
            balance -= principal
            rows.append(LoanInstallment(number: number, due: dueDate(terms, number: number, calendar: calendar),
                                        payment: principal + interest + tax, principal: principal, interest: interest,
                                        tax: tax, balanceAfter: balance))
            if balance <= 0 { break }
        }
        return rows
    }

    /// Bilinen taksitten aylık akdi faiz (vergi hariç). Efektif oran ikiye bölme ile bulunur.
    /// Taksit anapara / vadeden küçükse (eksi faiz) `nil`.
    public static func solveRate(principal: Decimal, payment: Decimal, term: Int, taxRate: Decimal) -> Decimal? {
        guard principal > 0, payment > 0, term > 0 else { return nil }
        let flat = principal / Decimal(term)
        if payment < flat - Decimal(string: "0.01")! { return nil }
        if payment <= flat { return 0 }
        var low = Decimal(0)
        var high = Decimal(1)
        guard rawPayment(principal: principal, rate: high, term: term) >= payment else { return nil }
        let tolerance = Decimal(string: "0.0000000001")!
        while high - low > tolerance {
            let mid = (low + high) / 2
            if rawPayment(principal: principal, rate: mid, term: term) < payment { low = mid } else { high = mid }
        }
        return ((low + high) / 2 / (1 + taxRate)).rounded(scale: 6)
    }

    /// Yıllık basit oran (aylık × 12), bankaların "yıllık faiz" gösterimi.
    public static func annualRate(_ monthly: Decimal) -> Decimal { monthly * 12 }

    public struct Totals: Hashable, Sendable {
        public var paid: Decimal
        public var interest: Decimal
        public var tax: Decimal
    }

    public static func totals(_ rows: some Collection<LoanInstallment>) -> Totals {
        rows.reduce(into: Totals(paid: 0, interest: 0, tax: 0)) {
            $0.paid += $1.payment
            $0.interest += $1.interest
            $0.tax += $1.tax
        }
    }

    /// `paidCount` taksit ödendikten sonra kalan anapara.
    public static func remainingPrincipal(_ schedule: [LoanInstallment], paidCount: Int, principal: Decimal) -> Decimal {
        guard paidCount > 0 else { return principal }
        guard paidCount <= schedule.count else { return 0 }
        return schedule[paidCount - 1].balanceAfter
    }

    /// Erken kapama (6502 s. Kanun m.37 ve Konut Finansmanı Sözleşmeleri Yönetmeliği).
    public struct Payoff: Hashable, Sendable {
        public var remainingPrincipal: Decimal
        /// Son vadeden bugüne işlemiş faiz (gün / 30).
        public var accruedInterest: Decimal
        public var accruedTax: Decimal
        /// Erken ödeme tazminatı: yalnız sabit faizli konut kredisinde; kalan vade ≤ 36 ay %1, üstü %2.
        public var fee: Decimal
        public var total: Decimal { remainingPrincipal + accruedInterest + accruedTax + fee }
        /// Plana göre ödenecek kalan taksitlerin toplamı.
        public var scheduledRemaining: Decimal
        /// Kapatınca ödenmeyecek faiz + vergi, tazminat düşülmüş.
        public var saved: Decimal { scheduledRemaining - total }
        public var remainingInstallments: Int
    }

    /// `date` gününde kalan borcu kapatma tutarı. Ödenmemiş taksit yoksa `nil`.
    public static func payoff(_ terms: LoanTerms, paidCount: Int, on date: Date, calendar: Calendar) -> Payoff? {
        let rows = schedule(terms, calendar: calendar)
        guard paidCount < rows.count else { return nil }
        let remaining = rows[max(paidCount, 0)...]
        let balance = remainingPrincipal(rows, paidCount: paidCount, principal: terms.principal)
        let periodStart = paidCount > 0
            ? rows[paidCount - 1].due
            : (calendar.date(byAdding: .month, value: -1, to: rows[0].due) ?? rows[0].due)
        let day = calendar.startOfDay(for: date)
        let days = max(0, min(calendar.dateComponents([.day], from: periodStart, to: day).day ?? 0, 30))
        let accrued = (balance * terms.monthlyRate * Decimal(days) / 30).rounded(scale: 2)
        let accruedTax = (accrued * terms.taxRate).rounded(scale: 2)
        let scheduled = totals(remaining).paid
        var fee = Decimal(0)
        if terms.kind == .housing, !terms.isVariableRate {
            let ratio = remaining.count <= 36 ? Decimal(string: "0.01")! : Decimal(string: "0.02")!
            // Tazminat, yapılacak faiz indiriminden fazla olamaz.
            let discount = max(scheduled - balance - accrued - accruedTax, 0)
            fee = min((balance * ratio).rounded(scale: 2), discount)
        }
        return Payoff(remainingPrincipal: balance, accruedInterest: accrued, accruedTax: accruedTax, fee: fee,
                      scheduledRemaining: scheduled, remainingInstallments: remaining.count)
    }
}
