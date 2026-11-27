import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Fiyat alarmı kur (REQ-M4, specs/08 §5). Eşik bugünkü fiyatın biraz üstü/altıyla dolu gelir.
struct PriceAlertEditor: View {
    let asset: AssetCode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(PriceBoard.self) private var board
    @AppStorage(SettingsKey.priceKind) private var defaultPriceKind: PriceKind = .bid
    @State private var direction: PriceAlertRule.Direction = .above
    @State private var priceKind: PriceKind = .bid
    @State private var thresholdText = ""
    @FocusState private var focused: Bool

    private var quote: Quote? { board.quote(asset) }
    private var threshold: Decimal? { AmountParser(locale: locale).parse(thresholdText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Koşul", selection: $direction) {
                        Text("Üstüne çıkarsa").tag(PriceAlertRule.Direction.above)
                        Text("Altına düşerse").tag(PriceAlertRule.Direction.below)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: direction) { _, _ in prefill() }
                    HStack {
                        TextField("Eşik", text: $thresholdText)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .focused($focused)
                            .accessibilityIdentifier("alert.threshold")
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: "₺").foregroundStyle(.secondary)
                    }
                    Picker("Fiyat", selection: $priceKind) {
                        ForEach(PriceKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text(verbatim: asset.displayName())
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let quote {
                            Text("Şu an \(asset.formatPrice(quote.price(priceKind), locale: locale)) ₺ · \(RelativeTimeText.text(for: quote.asOf))")
                        }
                        Text("Fiyat eşiği geçtiğinde bir kez haber veririm. Uygulama kapalıyken kontrol, telefonun arka planda yenilemeye izin verdiği sıklıkta yapılır; anlık değildir.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Fiyat alarmı")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kur", action: save)
                        .primaryActionStyle()
                        .disabled(threshold == nil)
                }
            }
            .onAppear {
                priceKind = defaultPriceKind
                prefill()
                focused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    /// Bugünkü fiyatın %2 üstü/altı, varlığın basamağında.
    private func prefill() {
        guard let price = quote?.price(priceKind) else { return }
        var target = price * (direction == .above ? Decimal(string: "1.02")! : Decimal(string: "0.98")!)
        var rounded = Decimal()
        let scale = price >= 1000 ? -1 : 2
        NSDecimalRound(&rounded, &target, scale, direction == .above ? .up : .down)
        var text = rounded.formattedNumber(locale: locale, fractionDigits: 0...2)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty { text = text.replacingOccurrences(of: grouping, with: "") }
        thresholdText = text
    }

    private func save() {
        guard let threshold else { return }
        let rule = PriceAlertRule(asset: asset, direction: direction, threshold: threshold, priceKind: priceKind)
        _ = try? PriceAlertStore(context: context).create(rule, current: quote)
        Reminders.requestAuthorizationIfNeeded()
        Task { await board.refresh(including: [asset]) }
        dismiss()
    }
}

/// Ayarlar › Fiyat alarmları: bekleyenler ve çalanlar; çalan yeniden kurulabilir.
struct PriceAlertsView: View {
    @Query(sort: \PriceAlert.createdAt, order: .reverse) private var alerts: [PriceAlert]
    @Environment(\.modelContext) private var context
    @Environment(PriceBoard.self) private var board

    var body: some View {
        Group {
            if alerts.isEmpty {
                ContentUnavailableView {
                    Label("Fiyat alarmı yok", systemImage: "bell")
                } description: {
                    Text("Bir varlığın ayrıntısından ya da Piyasa sayfasında satırı basılı tutarak alarm kur.")
                }
            } else {
                List {
                    let active = alerts.filter(\.isActive)
                    let fired = alerts.filter { !$0.isActive }
                    if !active.isEmpty {
                        Section("Bekleyen") {
                            ForEach(active) { alert in AlertRow(alert: alert) }
                                .onDelete { offsets in offsets.forEach { try? PriceAlertStore(context: context).delete(active[$0]) } }
                        }
                    }
                    if !fired.isEmpty {
                        Section("Çalan") {
                            ForEach(fired) { alert in
                                AlertRow(alert: alert)
                                    .swipeActions {
                                        Button("Sil", role: .destructive) { try? PriceAlertStore(context: context).delete(alert) }
                                        Button("Yeniden kur") {
                                            try? PriceAlertStore(context: context).rearm(alert, current: alert.rule.flatMap { board.quote($0.asset) })
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fiyat alarmları")
    }
}

private struct AlertRow: View {
    let alert: PriceAlert
    @Environment(\.locale) private var locale

    var body: some View {
        if let rule = alert.rule {
            HStack {
                AssetBadge(asset: rule.asset)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: rule.asset.displayName())
                    Group {
                        if let firedAt = alert.firedAt {
                            Text("Çaldı \(RelativeTimeText.text(for: firedAt))")
                        } else {
                            Text(rule.priceKind.shortLabel)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(rule.direction == .above
                     ? "\(rule.asset.formatPrice(rule.threshold, locale: locale)) üstü"
                     : "\(rule.asset.formatPrice(rule.threshold, locale: locale)) altı")
                    .monospacedDigit()
                    .foregroundStyle(alert.isActive ? Color.primary : Color.secondary)
            }
        }
    }
}
