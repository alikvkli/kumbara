import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçe › Abonelikler (REQ-I2, specs/10 §2). Liste kendiliğinden bulunur; kullanıcı yalnız düzeltir
/// ("Abonelik değil") ya da tekrarlayan kurala çevirir.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    // Gözlem için: işlem ya da kural değişince liste yeniden hesaplanır.
    @Query private var transactions: [LedgerTransaction]
    @Query private var rules: [RecurringRule]
    @Query private var logs: [NotificationLog]
    @State private var madeRecurring: String?

    private var store: InsightStore { InsightStore(context: context) }

    var body: some View {
        let subscriptions = (try? store.subscriptions(now: .now, calendar: calendar)) ?? []
        let active = subscriptions.filter { !$0.isMissed }
        let missed = subscriptions.filter(\.isMissed)

        Group {
            if subscriptions.isEmpty {
                ContentUnavailableView {
                    Label("Abonelik bulunamadı", systemImage: "repeat")
                } description: {
                    Text("Aynı yere her ay ya da her yıl benzer tutarda yapılan en az üç ödeme burada kendiliğinden listelenir.")
                }
            } else {
                List {
                    Section {
                        SubscriptionTotal(subscriptions: active)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    }
                    if !active.isEmpty {
                        Section {
                            ForEach(active) { row($0) }
                        } header: {
                            Text("Abonelikler")
                        } footer: {
                            Text("Aynı yere düzenli aralıkla, benzer tutarda yapılan en az üç ödemeden bulunur. Taksitler sayılmaz.")
                        }
                    }
                    if !missed.isEmpty {
                        Section {
                            ForEach(missed) { row($0) }
                        } header: {
                            Text("Bu dönem görünmedi")
                        } footer: {
                            Text("Beklenen günden 10 günden fazla geçti ve ödeme yok. İptal ettiysen ya da başka yerden ödüyorsan böyle görünür; toplama katılmaz.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Abonelikler")
        .alert("Tekrarlayan işlem oluşturuldu", isPresented: Binding(get: { madeRecurring != nil }, set: { if !$0 { madeRecurring = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            if let madeRecurring {
                Text("\(madeRecurring) her vadesinde onayına gelecek; Ayarlar › Tekrarlayan işlemler bölümünden değiştirilebilir.")
            }
        }
    }

    private func row(_ subscription: SubscriptionDetector.Subscription) -> some View {
        SubscriptionRow(subscription: subscription)
            .swipeActions {
                Button("Abonelik değil", role: .destructive) { try? store.dismissSubscription(subscription.merchantKey) }
                if !subscription.isTracked {
                    Button("Tekrarlayan yap") { makeRecurring(subscription) }.tint(.accentColor)
                }
            }
            .contextMenu {
                if !subscription.isTracked {
                    Button("Tekrarlayan yap", systemImage: "repeat") { makeRecurring(subscription) }
                }
                Button("Abonelik değil", systemImage: "xmark.circle", role: .destructive) {
                    try? store.dismissSubscription(subscription.merchantKey)
                }
            }
    }

    private func makeRecurring(_ subscription: SubscriptionDetector.Subscription) {
        guard let rule = try? store.makeRecurring(subscription, calendar: calendar) else { return }
        Reminders.schedule([rule])
        Reminders.requestAuthorizationIfNeeded()
        madeRecurring = subscription.name
    }
}

/// "Aylık ₺1.230 · yılda ₺14.760".
private struct SubscriptionTotal: View {
    let subscriptions: [SubscriptionDetector.Subscription]
    @Environment(\.locale) private var locale

    var body: some View {
        let monthly = SubscriptionDetector.monthlyTotal(subscriptions)
        VStack(alignment: .leading, spacing: 4) {
            Text("Aylık abonelik").font(.subheadline).foregroundStyle(.secondary)
            HeroAmount(money: Money(monthly, .TRY))
            Text("Yılda \(Money(monthly * 12, .TRY).formatted(locale: locale, fractionDigits: 0)) · \(subscriptions.count) abonelik")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct SubscriptionRow: View {
    let subscription: SubscriptionDetector.Subscription
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: subscription.name).font(.body.weight(.medium))
                if subscription.isTracked {
                    Text("Tekrarlayan")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: Money(subscription.lastAmount, .TRY).formatted(locale: locale))
                    .monospacedDigit()
                    .foregroundStyle(subscription.isMissed ? .secondary : .primary)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let previous = subscription.previousAmount, let increase = subscription.priceIncrease {
                Label {
                    Text("\(Money(previous, .TRY).formatted(locale: locale)) → \(Money(subscription.lastAmount, .TRY).formatted(locale: locale)) (\(increase.formattedPercent(locale: locale, fractionDigits: 0, sign: .always)))")
                } icon: {
                    Image(systemName: "arrow.up.right")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let cadence = subscription.cadence == .monthly ? String(localized: "Aylık") : String(localized: "Yıllık")
        let count = String(localized: "\(subscription.payments.count) ödeme")
        if subscription.isMissed {
            return "\(cadence) · \(String(localized: "beklenen \(subscription.nextDue.formatted(.dateTime.day().month(.abbreviated)))")) · \(count)"
        }
        return "\(cadence) · \(String(localized: "sıradaki \(subscription.nextDue.formatted(.dateTime.day().month(.abbreviated)))")) · \(count)"
    }
}

/// Bütçe ekranındaki bağlantı: "Abonelikler · aylık ₺1.230".
struct SubscriptionsLinkLabel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var transactions: [LedgerTransaction]

    var body: some View {
        let subscriptions = (try? InsightStore(context: context).subscriptions(now: .now, calendar: calendar)) ?? []
        let increased = subscriptions.contains { $0.previousAmount != nil && !$0.isMissed }
        HStack {
            Label("Abonelikler", systemImage: "repeat")
            Spacer()
            if !subscriptions.isEmpty {
                if increased {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("Fiyatı artan abonelik var"))
                }
                Text("aylık \(Money(SubscriptionDetector.monthlyTotal(subscriptions), .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
