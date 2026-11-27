import KumbaraCore
import KumbaraData
import SwiftUI

/// Raporu görsel olarak paylaş (specs/10 §1, K2). Varsayılan olarak tutarlar gizli, yalnız yüzdeler.
struct ReportShareSheet: View {
    let report: MonthlyReport
    let categories: [UUID: LedgerCategory]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsAmounts = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    card
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    Toggle("Tutarları göster", isOn: $showsAmounts)
                } footer: {
                    Text("Kapalıyken görselde yalnız yüzdeler görünür; kaç lira harcadığın ya da biriktirdiğin yazmaz.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Raporu paylaş")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let image = rendered {
                        ShareLink(item: image, preview: SharePreview(Text(verbatim: report.month.title(calendar: calendar)), image: image)) {
                            Text("Paylaş")
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 640)
        #endif
    }

    private var card: ReportShareCard {
        ReportShareCard(report: report, categories: categories, showsAmounts: showsAmounts)
    }

    /// 1080 × 1350 (4:5): 360 × 450 nokta, 3 kat ölçek.
    @MainActor
    private var rendered: Image? {
        let renderer = ImageRenderer(content: card
            .frame(width: 360, height: 450)
            .environment(\.calendar, calendar)
            .environment(\.locale, locale)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        return Image(decorative: image, scale: 1)
    }
}

/// Paylaşılan görsel. Uygulamanın kendi yüzeylerine benzer, sade; renk yalnız vurgu.
struct ReportShareCard: View {
    let report: MonthlyReport
    let categories: [UUID: LedgerCategory]
    let showsAmounts: Bool
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verbatim: report.month.title(calendar: calendar))
                    .font(.headline)
                Spacer()
                Label("Kumbara", systemImage: "circle.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(ReportText.headline(report, categories: categories, showsAmounts: showsAmounts,
                                     calendar: calendar, locale: locale))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                if let change = report.change {
                    row("Önceki aya göre gider", change.formattedPercent(locale: locale, fractionDigits: 0, sign: .always))
                }
                if let budget = report.budget {
                    row("Bütçe kullanımı", budget.usage.formattedPercent(locale: locale, fractionDigits: 0))
                }
                if report.income > 0 {
                    let saved = report.net / report.income
                    row("Gelirden kalan", saved.formattedPercent(locale: locale, fractionDigits: 0))
                }
                if let savings = report.savings, let priceReturn = savings.priceReturn {
                    row("Birikimin değeri", priceReturn.formattedPercent(locale: locale, fractionDigits: 1, sign: .always))
                    if let inflation = savings.inflation {
                        row("Aylık enflasyon", inflation.formattedPercent(locale: locale, fractionDigits: 1))
                    }
                }
                if showsAmounts {
                    row("Gelir", Money(report.income, .TRY).formatted(locale: locale, fractionDigits: 0))
                    row("Gider", Money(report.expense, .TRY).formatted(locale: locale, fractionDigits: 0))
                }
            }
            .font(.subheadline)
            .monospacedDigit()

            Spacer(minLength: 0)
            ForEach(report.categoryChanges.prefix(3), id: \.categoryID) { change in
                HStack {
                    Text(verbatim: change.categoryID.flatMap { categories[$0]?.name } ?? String(localized: "Kategorisiz"))
                    Spacer()
                    if let ratio = change.ratio {
                        Text(verbatim: ratio.formattedPercent(locale: locale, fractionDigits: 0, sign: .always))
                            .monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 28))
        .background(.background, in: .rect(cornerRadius: 28))
        .aspectRatio(4 / 5, contentMode: .fit)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).fontWeight(.semibold)
        }
    }
}
