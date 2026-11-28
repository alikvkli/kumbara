import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçe › Ödeme takvimi (REQ-I5, specs/10 §5). Kayıt oluşturmaz; dokunulan kalem kaynağına gider.
struct PaymentCalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var transactions: [LedgerTransaction]
    @Query private var rules: [RecurringRule]
    @State private var month = LedgerMonth(containing: .now, calendar: .current)
    @State private var selectedDay: Date?

    private var store: InsightStore { InsightStore(context: context) }

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let items = (try? store.upcomingPayments(from: today, days: 92, calendar: calendar)) ?? []
        let week = PaymentCalendar.window(items, from: today, days: 7, calendar: calendar)
        let thirty = PaymentCalendar.window(items, from: today, days: 30, calendar: calendar)
        let income = PaymentCalendar.nextIncome(items, from: today, calendar: calendar)
        let balance = try? store.liquidBalance()
        let pending = ((try? RecurringStore(context: context).pendingDrafts()) ?? []).filter { $0.recurrenceID != nil }

        List {
            Section {
                CalendarHeader(week: week, income: income)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            } footer: {
                if let balance {
                    let after = PaymentCalendar.balance(starting: balance, items: thirty.items)
                    if after.lowest < 0, let date = after.lowestDate {
                        Text("Nakit ve banka hesapların \(date.formatted(.dateTime.day().month(.wide))) günü \(money(-after.lowest)) eksiye düşebilir.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("30 gün içindeki gelir ve ödemelerden sonra nakit ve banka hesaplarında \(money(after.end)) kalır.")
                    }
                }
            }

            Section {
                MonthGrid(month: $month, items: items, selectedDay: $selectedDay)
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { draft in
                        LabeledContent {
                            Text(verbatim: draft.amount.formatted(locale: locale)).monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: draft.merchant ?? draft.category?.name ?? String(localized: "Tekrarlayan işlem"))
                                Text(draft.date.formatted(.dateTime.day().month(.wide))).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Onay bekliyor")
                } footer: {
                    Text("Vadesi gelmiş tekrarlar; İşlemler ekranından onaylanınca kesinleşir.")
                }
            }

            let listed = selectedDay.map { day in items.filter { $0.date == day } } ?? thirty.items
            Section {
                if listed.isEmpty {
                    Text(selectedDay == nil ? LocalizedStringKey("Önümüzdeki 30 günde bilinen ödeme yok.") : LocalizedStringKey("Bu gün için ödeme yok."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(listed) { item in
                        UpcomingRow(item: item)
                    }
                }
            } header: {
                if let selectedDay {
                    Text(selectedDay.formatted(.dateTime.day().month(.wide).weekday(.wide)))
                } else {
                    Text("Önümüzdeki 30 gün")
                }
            } footer: {
                Text("Tekrarlayan işlemler, kart son ödemeleri, kredi taksitleri ve aboneliklerden. Kartla ödenen abonelikler kart ödemesinin içindedir; \"tahmini\" yazanlar geçmiş ödemelerden çıkarıldı.")
            }
        }
        .navigationTitle("Ödeme takvimi")
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale, fractionDigits: 0) }
}

/// "Önümüzdeki 7 günde ₺21.400 ödeme var · maaşa 5 gün".
private struct CalendarHeader: View {
    let week: PaymentCalendar.Window
    let income: (payment: UpcomingPayment, days: Int)?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Önümüzdeki 7 gün").font(.subheadline).foregroundStyle(.secondary)
            HeroAmount(money: Money(week.outgoing, .TRY))
            HStack(spacing: 6) {
                Text("\(week.items.filter { !$0.isIncome }.count) ödeme")
                if let income {
                    Text(verbatim: "·")
                    if income.days == 0 {
                        Text("\(income.payment.title) bugün")
                    } else {
                        Text("\(income.payment.title): \(income.days) gün sonra")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ay ızgarası: ödemeli günlerde nokta, gelirli günlerde yeşil nokta; dokununca o günün kalemleri.
private struct MonthGrid: View {
    @Binding var month: LedgerMonth
    let items: [UpcomingPayment]
    @Binding var selectedDay: Date?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let days = self.days
        let byDay = Dictionary(grouping: items, by: \.date)
        let today = calendar.startOfDay(for: .now)
        VStack(spacing: 10) {
            HStack {
                Button("Önceki ay", systemImage: "chevron.left") { move(-1) }
                    .labelStyle(.iconOnly)
                    .disabled(month <= LedgerMonth(containing: .now, calendar: calendar))
                Spacer()
                Text(verbatim: month.title(calendar: calendar)).font(.headline)
                Spacer()
                Button("Sonraki ay", systemImage: "chevron.right") { move(1) }
                    .labelStyle(.iconOnly)
                    .disabled(month >= LedgerMonth(containing: .now, calendar: calendar).next.next)
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let dayItems = byDay[day] ?? []
                        DayCell(day: day, items: dayItems, isToday: day == today, isPast: day < today,
                                isSelected: selectedDay == day)
                            .onTapGesture { selectedDay = selectedDay == day ? nil : day }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func move(_ step: Int) {
        month = step > 0 ? month.next : month.previous
        selectedDay = nil
    }

    /// Haftanın ilk günü takvime göre (tr: Pazartesi).
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Ayın günleri, başında haftanın ilk gününe kadar boşluk.
    private var days: [Date?] {
        let interval = month.interval(in: calendar)
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }
}

private struct DayCell: View {
    let day: Date
    let items: [UpcomingPayment]
    let isToday: Bool
    let isPast: Bool
    let isSelected: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        let outgoing = items.contains { !$0.isIncome }
        let incoming = items.contains(where: \.isIncome)
        VStack(spacing: 3) {
            Text(verbatim: "\(calendar.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isPast ? .tertiary : .primary)
                .monospacedDigit()
            HStack(spacing: 2) {
                if outgoing { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                if incoming { Circle().fill(Color.green).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
            } else if isToday {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.formatted(.dateTime.day().month(.wide))))
        .accessibilityValue(items.isEmpty ? Text("Ödeme yok") : Text("\(items.count) kalem"))
        .accessibilityAddTraits(.isButton)
    }
}

struct UpcomingRow: View {
    let item: UpcomingPayment
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                HStack(spacing: 4) {
                    Text(item.date.formatted(.dateTime.day().month(.wide).weekday(.abbreviated)))
                    if item.isEstimate { Text("· tahmini") }
                    if item.isPartial { Text("· ekstre şu ana kadar") }
                    if case .card = item.source, !item.isPartial { Text("· son ödeme") }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: Money(item.amount, .TRY).formatted(locale: locale, sign: item.isIncome ? .always : .automatic))
                .monospacedDigit()
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bütçe ekranındaki bağlantı: "Ödeme takvimi · 7 günde ₺21.400".
struct PaymentCalendarLinkLabel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var transactions: [LedgerTransaction]

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let items = (try? InsightStore(context: context).upcomingPayments(from: today, days: 7, calendar: calendar)) ?? []
        let week = PaymentCalendar.window(items, from: today, days: 7, calendar: calendar)
        HStack {
            Label("Ödeme takvimi", systemImage: "calendar")
            Spacer()
            if week.outgoing > 0 {
                Text("7 günde \(Money(week.outgoing, .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
