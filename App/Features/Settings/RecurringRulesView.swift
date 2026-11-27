import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Tekrarlayan işlem kuralları (REQ-L7): sıradaki vade, duraklat, sil. Kural yeni işlem
/// formundaki "Tekrarla" ile oluşur.
struct RecurringRulesView: View {
    @Query(sort: \RecurringRule.createdAt) private var rules: [RecurringRule]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        Group {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("Tekrarlayan işlem yok", systemImage: "repeat")
                } description: {
                    Text("Kira, maaş, abonelik gibi düzenli kayıtlar için yeni işlem eklerken \"Tekrarla\"yı seç. Vadesi gelince onayına bir taslak gelir.")
                }
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRow(rule: rule)
                            .swipeActions {
                                Button("Sil", systemImage: "trash", role: .destructive) {
                                    Reminders.cancel(rule)
                                    try? RecurringStore(context: context).delete(rule)
                                }
                                Button(rule.isPaused ? "Sürdür" : "Duraklat", systemImage: rule.isPaused ? "play" : "pause") {
                                    rule.isPaused.toggle()
                                    try? context.save()
                                    Reminders.schedule([rule])
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
        .navigationTitle("Tekrarlayan işlemler")
    }
}

private struct RuleRow: View {
    let rule: RecurringRule
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack {
            CategoryBadge(systemImage: rule.category?.resolvedSymbol ?? "repeat", color: rule.category?.color.color ?? .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.merchant ?? rule.category?.name ?? "—")
                Group {
                    if rule.isPaused {
                        Text("Duraklatıldı")
                    } else if let next = rule.schedule?.nextDue(after: .now, calendar: calendar) {
                        Text("\(frequencyText) · sıradaki \(next.formatted(.dateTime.day().month(.abbreviated)))")
                    } else {
                        Text("Bitti")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: Money(rule.amount, rule.account?.currency ?? .TRY).formatted(locale: locale))
                .monospacedDigit()
                .foregroundStyle(rule.kind == .income ? Color.green : Color.primary)
        }
        .opacity(rule.isPaused ? 0.6 : 1)
    }

    private var frequencyText: Text {
        switch rule.frequency {
        case .monthly(_, let interval) where interval > 1: Text("\(interval) ayda bir")
        case .monthly: Text("Her ay")
        case .weekly: Text("Her hafta")
        case .yearly: Text("Her yıl")
        case nil: Text(verbatim: "—")
        }
    }
}
