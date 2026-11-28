import Foundation
import Testing
@testable import KumbaraCore

@Suite("Kart faizi (specs/11)")
struct CardInterestTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func d(_ value: String) -> Decimal { Decimal(string: value)! }
    private var december: CardInterestRates {
        CardInterestRates.current(on: calendar.date(from: DateComponents(year: 2026, month: 12, day: 5))!, calendar: calendar)
    }

    @Test("Tablo tarihe göre seçilir; dilim dönem borcuna göre (AC-I8-1)")
    func tables() {
        let november = CardInterestRates.current(on: calendar.date(from: DateComponents(year: 2026, month: 11, day: 28))!,
                                                 calendar: calendar)
        #expect(november.tier(for: 20_000).contractual == d("0.0325"))
        #expect(december.tier(for: 20_000).contractual == d("0.0308"))
        #expect(december.tier(for: 30_000).contractual == d("0.0308"))
        #expect(december.tier(for: d("30000.01")).contractual == d("0.0358"))
        #expect(december.tier(for: 500_000).contractual == d("0.0408"))
        #expect(MinimumPaymentRule(limit: 100_000) == .standard)
        #expect(MinimumPaymentRule(limit: 100_001) == .high)
    }

    @Test("₺20.000 ekstre, asgari ₺4.000 ödenirse ₺640,64 faiz ve vergi (AC-I8-2)")
    func minimumPaid() {
        let result = CardInterest.outcome(balance: 20_000, payment: 4_000, rule: .standard, rates: december)
        #expect(result.minimum == 4_000)
        #expect(result.unpaid == 16_000)
        #expect(result.contractualInterest == d("492.8"))
        #expect(result.lateInterest == 0)
        #expect(result.kkdf == d("73.92") && result.bsmv == d("73.92"))
        #expect(result.cost == d("640.64"))
        #expect(result.carried == d("16640.64"))
        #expect(!result.isBelowMinimum)
    }

    @Test("Hiç ödenmezse asgariye gecikme, kalana akdi faiz (AC-I8-3)")
    func nothingPaid() {
        let result = CardInterest.outcome(balance: 20_000, payment: 0, rule: .standard, rates: december)
        #expect(result.lateInterest == d("135.2"))
        #expect(result.contractualInterest == d("492.8"))
        #expect(result.cost == d("816.4"))
        #expect(result.isBelowMinimum)
    }

    @Test("Tamamı ödenirse faiz yok; fazla ödeme borçla sınırlı")
    func fullPaid() {
        let result = CardInterest.outcome(balance: 20_000, payment: 25_000, rule: .standard, rates: december)
        #expect(result.payment == 20_000)
        #expect(result.cost == 0 && result.carried == 0)
    }

    @Test("Kartın kendi oranı tavanın yerine geçer")
    func override() {
        let result = CardInterest.outcome(balance: 20_000, payment: 0, rule: .standard, rates: december, rate: d("0.02"))
        #expect(result.contractualInterest == 320)
        // Gecikme: 0,02 + 0,003 = %2,3
        #expect(result.lateInterest == 92)
    }

    @Test("Yalnız asgari: ₺1.000, %40 asgari, %10 faiz → 7 ay, ₺218,72 maliyet (AC-I8-4)")
    func payoffVector() {
        // Elle: 1000 → 678 → 459,68 → 311,67 → 211,32 → 143,27 → 97,14 (≤ ₺100: tamamı) → 0.
        let result = CardInterest.payoff(balance: 1_000, plan: .minimum, rule: .high, rates: december, rate: d("0.10"))
        #expect(result.finishes)
        #expect(result.months == 7)
        #expect(result.firstPayment == 400)
        #expect(result.totalPaid == d("1218.72"))
        #expect(result.totalCost == d("218.72"))
    }

    @Test("Yalnız asgari ödenirse kapanma süresi ve toplam maliyet; sabit ödeme daha kısa")
    func payoffComparison() {
        let minimum = CardInterest.payoff(balance: 20_000, plan: .minimum, rule: .standard, rates: december)
        let fixed = CardInterest.payoff(balance: 20_000, plan: .fixed(5_000), rule: .standard, rates: december)
        #expect(minimum.finishes && fixed.finishes)
        #expect(minimum.firstPayment == 4_000)
        #expect(fixed.firstPayment == 5_000)
        #expect(fixed.months < minimum.months)
        #expect(fixed.totalCost < minimum.totalCost)
        #expect(minimum.totalPaid == 20_000 + minimum.totalCost)
        // İlk ay elle: 20.000 → 16.640,64; ikinci ay asgari 3.328,13.
        let second = CardInterest.outcome(balance: d("16640.64"), payment: d("3328.13"), rule: .standard, rates: december)
        #expect(second.minimum == d("3328.13"))
    }

    @Test("Faizi karşılamayan ödeme kapanmaz")
    func neverFinishes() {
        // %20 asgari, %35 faiz (vergiyle %45,5): borç her ay 0,8 × 1,455 katına çıkar.
        let stuck = CardInterest.payoff(balance: 10_000, plan: .minimum, rule: .standard, rates: december,
                                        rate: d("0.35"), maxMonths: 24)
        #expect(!stuck.finishes)
        #expect(stuck.months == 24)
    }
}
