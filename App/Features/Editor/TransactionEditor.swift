import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// İşlem ekleme/düzenleme formu (REQ-L2, L4, L6).
///
/// Hızlı ekleme: 1. dokunuş "+" → bu sayfa tutar alanı odaklı açılır; 2. dokunuş "Kaydet".
/// Hesap son kullanılan hesaptan, kategori satıcı hafızasından önerilir; ikisi de değiştirilebilir.
struct TransactionEditor: View {
    enum Mode {
        case create(TransactionKind)
        case edit(LedgerTransaction)
    }

    let mode: Mode
    /// Yeni kayıtta önceden doldurulan alanlar ("Alabilir miyim?", hızlı ekleme önerisi; specs/10 §3, §6).
    /// Kaydetmek yine kullanıcıdadır (C5).
    var prefill: Prefill? = nil

    struct Prefill {
        var amount: Decimal?
        var accountID: UUID?
        var categoryID: UUID?
        var merchant: String?
        var installments: Int?
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(AppRouter.self) private var router
    @AppStorage(SavingsSplitSheet.promptKey) private var offersSavingsSplit = true

    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var account: LedgerAccount?
    @State private var toAccount: LedgerAccount?
    @State private var category: LedgerCategory?
    @State private var categoryIsSuggested = false
    @State private var merchant = ""
    @State private var note = ""
    @State private var recentCategories: [LedgerCategory] = []
    @State private var completions: [MerchantMemory] = []
    @State private var didLoad = false
    @State private var saveFailed = false
    @State private var confirmsDeletion = false
    @State private var repetition: Repetition = .none
    @State private var installments = 1
    @State private var isSplitting = false
    @State private var suggestions: [QuickAddSuggester.Suggestion] = []
    @AppStorage(SettingsKey.quickSuggestions) private var showsSuggestions = true

    /// Kartla yapılan yeni giderde taksit seçilebilir (REQ-L9).
    private var offersInstallments: Bool { editing == nil && kind == .expense && account?.kind == .card }

    /// Yeni işlemi tekrarlayan yapma (REQ-L7, specs/08 §2).
    enum Repetition: Hashable, CaseIterable {
        case none, monthly, weekly, yearly
        var label: LocalizedStringKey {
            switch self {
            case .none: "Tekrarlama"
            case .monthly: "Her ay"
            case .weekly: "Her hafta"
            case .yearly: "Her yıl"
            }
        }
    }
    @FocusState private var focus: Field?

    private enum Field: Hashable { case amount, merchant, note }

    private var store: LedgerStore { LedgerStore(context: context) }

    private var editing: LedgerTransaction? {
        if case .edit(let transaction) = mode { return transaction }
        return nil
    }

    private var draft: TransactionDraft {
        TransactionDraft(
            kind: kind,
            amount: AmountParser(locale: locale).parse(amountText),
            date: date,
            account: account?.ref,
            toAccount: kind == .transfer ? toAccount?.ref : nil,
            category: kind == .transfer ? nil : category?.ref,
            merchant: merchant,
            note: note
        )
    }

    /// Kullanıcının düzeltebileceği sorunlar; tutar boşken uyarı göstermeyiz.
    private var visibleIssues: [TransactionDraft.Issue] {
        draft.issues.filter { $0 != .missingAmount && !($0 == .nonPositiveAmount && amountText.isEmpty) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil, kind == .expense, amountText.isEmpty, !suggestions.isEmpty {
                    suggestionsSection
                }
                amountSection
                if kind == .transfer {
                    transferSection
                } else {
                    // Satıcı tutarın hemen altında: yarım sayfada klavye açıkken görünür kalır
                    // ve kategori satıcıdan önerildiği için önce gelmesi doğal sıradır.
                    merchantSection
                    categorySection
                }
                detailsSection
                if !visibleIssues.isEmpty {
                    Section {
                        ForEach(visibleIssues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                // Arkadaşlarla böl (specs/10 §4): yalnız kaydedilmiş giderde.
                if let editing, editing.kind == .expense, kind == .expense {
                    Section {
                        Button(editing.sharedAmount > 0 ? "Bölmeyi düzenle" : "Böl", systemImage: "person.2") { isSplitting = true }
                    } footer: {
                        if editing.sharedAmount > 0 {
                            Text("Senin payın \(editing.entry.ownAmount.formatted(locale: locale)); kalanı alacak olarak yazıldı.")
                        }
                    }
                }
                if editing != nil {
                    Section {
                        Button("İşlemi sil", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? kind.newTitle : "İşlemi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .primaryActionStyle()
                        .disabled(!draft.isValid)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .sheet(isPresented: $isSplitting) {
                if let editing { SplitSheet(transaction: editing) }
            }
            .confirmationDialog("Bu işlem silinsin mi?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Sil", role: .destructive, action: delete)
            }
            .alert("İşlem kaydedilemedi", isPresented: $saveFailed) {
                Button("Tamam", role: .cancel) {}
            }
            .onChange(of: kind) { _, newKind in
                if let category, CategoryKind(newKind) != category.kind {
                    self.category = nil
                    categoryIsSuggested = false
                }
                if newKind == .transfer, toAccount == nil || toAccount == account {
                    toAccount = accounts.first { $0 != account && $0.currency == account?.currency }
                }
                loadRecentCategories()
            }
            .onChange(of: merchant) { _, newValue in
                merchantChanged(newValue)
            }
            .sensoryFeedback(.selection, trigger: kind)
            .task {
                guard !didLoad else { return }
                didLoad = true
                load()
                if editing == nil { focus = .amount }
            }
        }
    }

    // MARK: Bölümler

    /// Alışkanlığa uyan satıcılar (specs/10 §6): dokununca form dolar, kaydetmek yine kullanıcıda.
    private var suggestionsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            apply(Prefill(amount: suggestion.amount, accountID: suggestion.accountID,
                                          categoryID: suggestion.categoryID, merchant: suggestion.merchant))
                            focus = nil
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: suggestion.merchant)
                                Text(verbatim: Money(suggestion.amount, .TRY).formatted(locale: locale))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Bunu önerme", systemImage: "hand.raised") {
                                try? InsightStore(context: context).dismissSuggestion(suggestion.merchantKey)
                                suggestions.removeAll { $0.id == suggestion.id }
                            }
                        }
                        .accessibilityLabel(Text("\(suggestion.merchant), \(Money(suggestion.amount, .TRY).formatted(locale: locale))"))
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        } header: {
            Text("Bu saatlerde sık")
        }
    }

    private var amountSection: some View {
        Section {
            Picker("Tür", selection: $kind) {
                ForEach(TransactionKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .firstTextBaseline) {
                TextField("Tutar", text: $amountText, prompt: Text(verbatim: "0"))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .focused($focus, equals: .amount)
                    .accessibilityIdentifier("editor.amount")
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(verbatim: (account?.currency ?? .TRY).rawValue)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var categorySection: some View {
        Section {
            CategoryChips(categories: chipCategories, selection: category) { picked in
                category = picked == category ? nil : picked
                categoryIsSuggested = false
            }
            NavigationLink {
                CategoryPicker(kind: CategoryKind(kind) ?? .expense, selection: Binding(
                    get: { category },
                    set: { category = $0; categoryIsSuggested = false }
                ))
            } label: {
                LabeledContent("Tüm kategoriler") {
                    if let category { Text(verbatim: category.path) }
                }
            }
        } header: {
            Text("Kategori")
        } footer: {
            if categoryIsSuggested, let name = draft.trimmedMerchant {
                Text("\(name) için son kullandığın kategori.")
            }
        }
    }

    private var merchantSection: some View {
        Section {
            TextField("Satıcı", text: $merchant, prompt: Text("Örn. Migros"))
                .focused($focus, equals: .merchant)
                #if os(iOS)
                .textContentType(.organizationName)
                .submitLabel(.next)
                #endif
            if focus == .merchant {
                ForEach(completions, id: \.key) { memory in
                    Button {
                        merchant = memory.displayName
                        if let suggested = memory.category, CategoryKind(kind) == suggested.kind {
                            category = suggested
                            categoryIsSuggested = true
                        }
                        focus = nil
                    } label: {
                        LabeledContent {
                            if let path = memory.category?.path { Text(verbatim: path) }
                        } label: {
                            Text(verbatim: memory.displayName)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private var transferSection: some View {
        Section {
            accountPicker("Nereden", selection: $account)
            accountPicker("Nereye", selection: $toAccount)
        }
    }

    private var detailsSection: some View {
        Section {
            if kind != .transfer {
                accountPicker("Hesap", selection: $account)
            }
            DatePicker("Tarih", selection: $date)
            if offersInstallments {
                Picker("Taksit", selection: $installments) {
                    ForEach(Installments.choices, id: \.self) { count in
                        if count == 1 { Text("Peşin").tag(count) } else { Text("\(count) taksit").tag(count) }
                    }
                }
            }
            if editing == nil && kind != .transfer && installments == 1 {
                Picker("Tekrarla", selection: $repetition) {
                    ForEach(Repetition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            TextField("Not", text: $note, axis: .vertical)
                .focused($focus, equals: .note)
                .lineLimit(1...4)
        } footer: {
            if offersInstallments, installments > 1, let total = draft.amount {
                let parts = Installments.split(total, count: installments)
                let currency = account?.currency ?? .TRY
                Text("\(installments) × \(Money(parts.last ?? 0, currency).formatted(locale: locale)) · ilk taksit bu tarihte, kalanlar her ay aynı gün. Bütçeye her ay yalnız o ayın taksiti sayılır.")
            } else if repetition != .none {
                Text("Sonraki tarihlerde onayına bir taslak gelir; onaylamadan kesinleşmez.")
            } else if editing?.status == .draft {
                Text("Bu kayıt onay bekliyor; kaydedince kesinleşir.")
            }
        }
    }

    private func accountPicker(_ title: LocalizedStringKey, selection: Binding<LedgerAccount?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(accounts) { account in
                Label {
                    Text(verbatim: account.name)
                } icon: {
                    Image(systemName: account.kind.systemImage)
                }
                .tag(Optional(account))
            }
        }
    }

    /// Son kullanılanlar önce, ardından üst kategoriler; seçili alt kategori her zaman görünür.
    private var chipCategories: [LedgerCategory] {
        guard let categoryKind = CategoryKind(kind) else { return [] }
        var result: [LedgerCategory] = []
        if let category, category.kind == categoryKind { result.append(category) }
        for candidate in recentCategories where !result.contains(candidate) { result.append(candidate) }
        let tops = (try? context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        for top in tops where top.parent == nil && !top.isArchived && top.kind == categoryKind && !result.contains(top) {
            result.append(top)
        }
        return result
    }

    // MARK: Eylemler

    private func load() {
        if let editing {
            kind = editing.kind
            var text = editing.amount.amount.formattedNumber(
                locale: locale, fractionDigits: 0...editing.amount.currency.minorUnits)
            if let grouping = locale.groupingSeparator, !grouping.isEmpty {
                text = text.replacingOccurrences(of: grouping, with: "")
            }
            amountText = text
            date = editing.date
            account = editing.account
            toAccount = editing.toAccount
            category = editing.category
            merchant = editing.merchant ?? ""
            note = editing.note
        } else {
            account = (try? store.defaultAccount()) ?? accounts.first
            if case .create(let initialKind) = mode { kind = initialKind }
            if let prefill {
                apply(prefill)
            } else if showsSuggestions {
                suggestions = (try? InsightStore(context: context).quickAddSuggestions()) ?? []
            }
        }
        loadRecentCategories()
    }

    private func apply(_ prefill: Prefill) {
        if let amount = prefill.amount {
            var text = amount.formattedNumber(locale: locale, fractionDigits: 0...2)
            if let grouping = locale.groupingSeparator, !grouping.isEmpty {
                text = text.replacingOccurrences(of: grouping, with: "")
            }
            amountText = text
        }
        if let id = prefill.accountID, let match = accounts.first(where: { $0.id == id }) { account = match }
        if let id = prefill.categoryID {
            let descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })
            category = (try? context.fetch(descriptor))?.first
        }
        if let merchant = prefill.merchant { self.merchant = merchant }
        if let count = prefill.installments, count > 1 { installments = count }
    }

    private func loadRecentCategories() {
        guard let categoryKind = CategoryKind(kind) else { recentCategories = []; return }
        recentCategories = (try? store.recentCategories(kind: categoryKind)) ?? []
    }

    private func merchantChanged(_ value: String) {
        completions = (try? store.merchantCompletions(for: value, limit: 3))?
            .filter { MerchantKey.normalize($0.displayName) != MerchantKey.normalize(value) } ?? []
        guard category == nil || categoryIsSuggested else { return }
        if let suggested = try? store.suggestedCategory(forMerchant: value), CategoryKind(kind) == suggested.kind {
            category = suggested
            categoryIsSuggested = true
        } else if categoryIsSuggested {
            category = nil
            categoryIsSuggested = false
        }
    }

    private func save() {
        do {
            if offersInstallments, installments > 1 {
                try InstallmentStore(context: context).save(draft, count: installments)
                dismiss()
                return
            }
            let saved = try store.save(draft, editing: editing)
            if let frequency = frequency(for: saved.date) {
                try RecurringStore(context: context).makeRule(from: saved, frequency: frequency)
                Reminders.requestAuthorizationIfNeeded()
            }
            // Yeni TL geliri: sayfa kapanınca bir kısmını birikime ayırmayı öner (REQ-P10).
            if editing == nil, offersSavingsSplit, saved.kind == .income, saved.amount.currency == .TRY {
                router.pendingSavingsSplit = saved.amount.amount
            }
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    private func frequency(for date: Date) -> RecurrenceFrequency? {
        let calendar = Calendar.current
        switch repetition {
        case .none: return nil
        case .monthly: return .monthly(day: calendar.component(.day, from: date))
        case .weekly: return .weekly(weekday: calendar.component(.weekday, from: date))
        case .yearly: return .yearly(month: calendar.component(.month, from: date), day: calendar.component(.day, from: date))
        }
    }

    private func delete() {
        guard let editing else { return }
        try? store.delete(editing)
        dismiss()
    }
}

/// Yatay kategori seçimi. İçerik katmanındadır: cam değil, sistem bordered buton (specs/06 §1).
private struct CategoryChips: View {
    let categories: [LedgerCategory]
    let selection: LedgerCategory?
    let select: (LedgerCategory) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isSelected = category == selection
                    Button {
                        select(category)
                    } label: {
                        Label {
                            Text(verbatim: category.name)
                        } icon: {
                            Image(systemName: category.resolvedSymbol)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// Tüm kategoriler, iki seviyeli liste.
struct CategoryPicker: View {
    let kind: CategoryKind
    @Binding var selection: LedgerCategory?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerCategory.sortIndex) private var all: [LedgerCategory]

    private var tops: [LedgerCategory] {
        all.filter { $0.parent == nil && !$0.isArchived && $0.kind == kind }
    }

    var body: some View {
        List {
            ForEach(tops) { top in
                Section {
                    row(top)
                    ForEach(top.sortedChildren) { child in
                        row(child).padding(.leading, 28)
                    }
                }
            }
        }
        .navigationTitle("Kategori")
    }

    private func row(_ category: LedgerCategory) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack {
                CategoryBadge(systemImage: category.resolvedSymbol, color: category.color.color)
                Text(verbatim: category.name)
                Spacer()
                if category == selection {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
    }
}
