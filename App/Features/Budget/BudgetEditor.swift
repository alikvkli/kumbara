import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçe ekle / düzenle (specs/08 §1.1). Limit değişikliği gösterilen aydan itibaren geçerlidir.
struct BudgetEditor: View {
    enum Target: Identifiable {
        case new
        case overall
        case category(LedgerCategory)

        var id: String {
            switch self {
            case .new: "new"
            case .overall: "overall"
            case .category(let category): category.id.uuidString
            }
        }
    }

    let target: Target
    let month: LedgerMonth

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var category: LedgerCategory?
    @State private var isOverall = false
    @State private var amountText = ""
    @State private var suggestion: Decimal?
    @FocusState private var amountFocused: Bool

    private var store: BudgetStore { BudgetStore(context: context) }
    private var limit: Decimal? { AmountParser(locale: locale).parse(amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var existing: Budget? {
        let all = (try? store.budgets()) ?? []
        return isOverall ? all.first(where: \.isOverall) : all.first { $0.category?.id == category?.id && category != nil }
    }
    private var canSave: Bool { limit != nil && (isOverall || category != nil) }
    private var monthTitle: String { month.interval(in: calendar).start.formatted(.dateTime.month(.wide).year()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if case .new = target {
                        Toggle("Genel bütçe (tüm giderler)", isOn: $isOverall)
                        if !isOverall {
                            NavigationLink {
                                CategoryPicker(kind: .expense, selection: $category)
                            } label: {
                                LabeledContent("Kategori") { Text(verbatim: category?.path ?? "Seç") }
                            }
                        }
                    } else {
                        LabeledContent("Bütçe") {
                            if isOverall { Text("Genel (tüm giderler)") } else { Text(verbatim: category?.path ?? "—") }
                        }
                    }
                } footer: {
                    if !isOverall, category?.parent == nil, category != nil {
                        Text("Alt kategorilerin harcaması da bu bütçeye sayılır.")
                    }
                }

                Section {
                    HStack {
                        TextField("Aylık limit", text: $amountText)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .focused($amountFocused)
                            .accessibilityIdentifier("budget.limit")
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: "₺").foregroundStyle(.secondary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let suggestion {
                            Button("Son 3 ay ortalaması \(Money(suggestion, .TRY).formatted(locale: locale, fractionDigits: 0)) · kullan") {
                                amountText = editable(suggestion)
                            }
                            .font(.footnote)
                        }
                        Text("\(monthTitle) ayından itibaren geçerli; geçmiş aylar kendi limitini korur.")
                    }
                }

                if let existing {
                    Section {
                        Button("Bütçeyi sil", role: .destructive) {
                            try? store.delete(existing)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(existing == nil ? "Yeni bütçe" : "Bütçe"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .primaryActionStyle()
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: category) { _, _ in refreshSuggestion(); fillFromExisting() }
            .onChange(of: isOverall) { _, _ in refreshSuggestion(); fillFromExisting() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func load() {
        switch target {
        case .new: break
        case .overall: isOverall = true
        case .category(let value): category = value
        }
        fillFromExisting()
        refreshSuggestion()
        amountFocused = true
    }

    private func fillFromExisting() {
        guard let limit = existing?.history.limit(for: month) else { return }
        amountText = editable(limit)
    }

    /// Alanda gruplama ayırıcısı olmadan ("3900" / "3900,5"); `AmountParser` geri okuyabilsin.
    private func editable(_ value: Decimal) -> String {
        var text = value.formattedNumber(locale: locale, fractionDigits: 0...2)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty { text = text.replacingOccurrences(of: grouping, with: "") }
        return text
    }

    private func refreshSuggestion() {
        suggestion = (isOverall || category != nil)
            ? (try? store.suggestedLimit(for: isOverall ? nil : category, before: month, calendar: calendar)) ?? nil
            : nil
    }

    private func save() {
        guard let limit else { return }
        try? store.setLimit(limit, for: isOverall ? nil : category, from: month)
        BudgetMonitor.shared.requestAuthorizationIfNeeded()
        dismiss()
    }
}
