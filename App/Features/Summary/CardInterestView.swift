import KumbaraCore
import SwiftUI

/// Kartın faiz ayarları (specs/11 §4, K2): şema değişmesin diye kart kimliğine göre UserDefaults'ta.
struct CardInterestSettings: Codable, Hashable {
    var rule: MinimumPaymentRule = .standard
    /// Kartın kendi aylık akdi faizi (0,0299); `nil` → TCMB tavanı.
    var rate: Decimal?

    static let key = "card.interest"

    static func load(_ cardID: UUID) -> CardInterestSettings {
        all()[cardID.uuidString] ?? CardInterestSettings()
    }

    static func save(_ settings: CardInterestSettings, for cardID: UUID) {
        var values = all()
        values[cardID.uuidString] = settings
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func all() -> [String: CardInterestSettings] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([String: CardInterestSettings].self, from: data) else { return [:] }
        return values
    }
}

/// "Asgari ödersen ne olur?" (REQ-I8, specs/11 §4). Kayıt oluşturmaz; ekstre borcunun gelecek ekstreye
/// maliyetini ve yalnız asgari ödenirse borcun ne zaman kapanacağını gösterir. Tavsiye vermez (C6).
struct CardInterestView: View {
    let cardID: UUID
    /// Son ekstre (dönem borcu).
    let statement: Decimal
    /// Kesimden bu yana yapılan ödemeler.
    let paid: Decimal
    let due: Date
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var settings = CardInterestSettings()
    @State private var paymentText = ""
    @State private var rateText = ""
    @State private var loaded = false

    /// Son ödeme günü geçtiyse sonuç bellidir: yalnız ödenen tutarın sonucu gösterilir.
    private var isPastDue: Bool { calendar.startOfDay(for: due) < calendar.startOfDay(for: .now) }

    private var rates: CardInterestRates { CardInterestRates.current(on: .now, calendar: calendar) }
    private var parser: AmountParser { AmountParser(locale: locale) }

    /// Bu ekstre için toplam ödeme: yapılan + yazılan.
    private var custom: Decimal? {
        parser.parse(paymentText).flatMap { $0 >= 0 ? paid + $0 : nil }
    }

    var body: some View {
        let rule = settings.rule
        let minimum = CardInterest.minimum(balance: statement, rule: rule)
        let minimumOutcome = outcome(paying: max(minimum, paid))
        let tier = rates.tier(for: statement)

        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ekstre borcu").font(.subheadline).foregroundStyle(.secondary)
                    HeroAmount(money: money(statement))
                    Text("Asgari \(format(minimum)) · son ödeme \(due.formatted(.dateTime.day().month(.wide)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if paid > 0 {
                        Text("Bu ekstreye \(format(paid)) ödendi.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            if isPastDue {
                Section {
                    OutcomeRow(title: "Ödediğin", payment: paid, outcome: outcome(paying: paid))
                } header: {
                    Text("Son ödeme günü geçti")
                } footer: {
                    Text("Kalan \(format(statement - paid)) ve faizi gelecek ekstreye eklenir. Faize \(share(rates.kkdf)) KKDF ve \(share(rates.bsmv)) BSMV eklenir.")
                }
            } else {
                Section {
                    OutcomeRow(title: "Tamamını ödersen", payment: statement, outcome: nil)
                    OutcomeRow(title: "Asgariyi ödersen", payment: max(minimum, paid), outcome: minimumOutcome)
                    if paid < minimum {
                        OutcomeRow(title: paid > 0 ? "Başka ödeme yapmazsan" : "Ödeme yapmazsan", payment: paid,
                                   outcome: outcome(paying: paid))
                    }
                } header: {
                    Text("Gelecek ekstreye")
                } footer: {
                    Text("Asgari ödenmezse eksik kalan kısma gecikme faizi işler ve kart kullanıma kapanabilir. Faize \(share(rates.kkdf)) KKDF ve \(share(rates.bsmv)) BSMV eklenir.")
                }

                Section {
                    TextField("Ödeyeceğin tutar", text: $paymentText, prompt: Text(verbatim: format(minimum - min(paid, minimum))))
                        .monospacedDigit()
                        .accessibilityIdentifier("cardInterest.payment")
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    if let custom {
                        let result = outcome(paying: custom)
                        if result.unpaid == 0 {
                            Text("Borcun tamamı kapanır; faiz işlemez.").foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Faiz ve vergi", value: format(result.cost)).monospacedDigit()
                            LabeledContent("Gelecek ekstreye devreden", value: format(result.carried)).monospacedDigit()
                            if result.isBelowMinimum {
                                Text("Bu tutar asgarinin altında; eksik kalan \(format(result.minimum - result.payment)) için gecikme faizi işler.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Başka bir tutar")
                }
            }

            Section {
                payoffRow(title: "Her ay asgari", payoff: CardInterest.payoff(
                    balance: statement - paid, plan: .minimum, rule: rule, rates: rates, rate: settings.rate))
                if let custom, custom > paid, custom - paid < statement - paid {
                    let monthly = custom - paid
                    payoffRow(title: "Her ay \(format(monthly))", payoff: CardInterest.payoff(
                        balance: statement - paid, plan: .fixed(monthly), rule: rule, rates: rates, rate: settings.rate))
                }
            } header: {
                Text("Hep böyle ödersen")
            } footer: {
                Text("Karta yeni harcama eklenmediği, iki ekstre arasının 30 gün olduğu ve oranların değişmediği varsayılır. Kalan borç \(format(CardInterest.closingThreshold)) altına inince o ay tamamı ödenmiş sayılır.")
            }

            Section {
                Picker("Kart limiti", selection: $settings.rule) {
                    Text("\(format(MinimumPaymentRule.limitThreshold)) ve altı · asgari \(share(MinimumPaymentRule.standard.ratio))")
                        .tag(MinimumPaymentRule.standard)
                    Text("\(format(MinimumPaymentRule.limitThreshold)) üstü · asgari \(share(MinimumPaymentRule.high.ratio))")
                        .tag(MinimumPaymentRule.high)
                }
                TextField("Kartın aylık akdi faizi (%)", text: $rateText,
                          prompt: Text(verbatim: percent(tier.contractual)))
                    .monospacedDigit()
                    .accessibilityIdentifier("cardInterest.rate")
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            } header: {
                Text("Oranlar")
            } footer: {
                Text("Boş bırakılırsa TCMB'nin \(rates.effective.title(calendar: calendar)) tavanı kullanılır: bu ekstre için aylık \(rate(tier.contractual)) akdi, \(rate(tier.late)) gecikme faizi. Banka daha düşük oran uyguluyorsa ekstredeki oranı yaz.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Asgari ödersen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard !loaded else { return }
            loaded = true
            settings = CardInterestSettings.load(cardID)
            rateText = settings.rate.map { percent($0) } ?? ""
        }
        .onChange(of: rateText) { _, text in
            let value = parser.parse(text).flatMap { $0 > 0 && $0 < 100 ? $0 / 100 : nil }
            settings.rate = value
        }
        .onChange(of: settings) { _, value in
            CardInterestSettings.save(value, for: cardID)
        }
    }

    private func outcome(paying payment: Decimal) -> CardInterest.Outcome {
        CardInterest.outcome(balance: statement, payment: payment, rule: settings.rule, rates: rates, rate: settings.rate)
    }

    @ViewBuilder
    private func payoffRow(title: LocalizedStringKey, payoff: CardInterest.Payoff) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                if payoff.finishes {
                    Text("\(payoff.months) ayda kapanır")
                    Text("\(format(payoff.totalCost)) faiz ve vergi")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Bu ödemeyle borç kapanmaz").foregroundStyle(.orange)
                }
            }
            .monospacedDigit()
        } label: {
            Text(title)
        }
    }

    private func money(_ value: Decimal) -> Money { Money(value, .TRY) }
    private func format(_ value: Decimal) -> String { money(value).formatted(locale: locale) }
    /// 0,15 → "%15"
    private func share(_ value: Decimal) -> String { value.formattedPercent(locale: locale, fractionDigits: 0) }
    /// 0,0308 → "%3,08"
    private func rate(_ value: Decimal) -> String { value.formattedPercent(locale: locale, fractionDigits: 2) }
    /// 0,0308 → "3,08" (yazma alanı için)
    private func percent(_ value: Decimal) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

/// Kart ayrıntısındaki bağlantı: "Asgari ödersen · +₺641 faiz".
struct CardInterestLinkLabel: View {
    let cardID: UUID
    let statement: CardStatement
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        let settings = CardInterestSettings.load(cardID)
        let balance = statement.lastStatement.amount
        let paid = statement.paidSinceClosing.amount
        let minimum = CardInterest.minimum(balance: balance, rule: settings.rule)
        let outcome = CardInterest.outcome(balance: balance, payment: max(minimum, paid), rule: settings.rule,
                                           rates: CardInterestRates.current(on: .now, calendar: calendar), rate: settings.rate)
        HStack {
            Label("Asgari ödersen", systemImage: "percent")
            Spacer()
            if outcome.cost > 0 {
                Text("+\(Money(outcome.cost, .TRY).formatted(locale: locale, fractionDigits: 0)) faiz")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct OutcomeRow: View {
    let title: LocalizedStringKey
    let payment: Decimal
    let outcome: CardInterest.Outcome?
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                if let outcome, outcome.cost > 0 {
                    Text(verbatim: "+" + Money(outcome.cost, .TRY).formatted(locale: locale))
                        .foregroundStyle(outcome.isBelowMinimum ? Color.orange : Color.primary)
                    Text("faiz ve vergi").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Faiz yok").foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: Money(payment, .TRY).formatted(locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
