import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI
#if os(iOS)
import ContactsUI
#endif

/// Özet › Alacak ve borçlar (REQ-I4, specs/10 §4). Yalnız senin defterin; kimseye bir şey gönderilmez.
struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<Person> { !$0.isArchived }, sort: \Person.name) private var people: [Person]
    @Query private var records: [DebtRecord]
    @Query private var transactions: [LedgerTransaction]
    @State private var isAdding = false

    var body: some View {
        let balances = (try? DebtStore(context: context).balances()) ?? [:]
        let totals = DebtMath.totals(balances)
        Group {
            if people.isEmpty {
                ContentUnavailableView {
                    Label("Kimse yok", systemImage: "person.2")
                } description: {
                    Text("Arkadaşınla bölüştüğün bir harcamayı ya da elden verdiğin borcu buradan takip et. Bilgiler yalnız bu cihazda kalır.")
                } actions: {
                    Button("Kişi ekle") { isAdding = true }.primaryActionStyle()
                }
            } else {
                List {
                    Section {
                        HStack(alignment: .top) {
                            figure("Alacağın", totals.receivable, tint: .green)
                            figure("Borcun", totals.payable, tint: totals.payable > 0 ? .orange : .primary)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    }
                    Section {
                        ForEach(people) { person in
                            NavigationLink {
                                PersonDetailView(person: person)
                            } label: {
                                PersonRow(person: person, balance: balances[person.id] ?? 0)
                            }
                        }
                        Button("Kişi ekle", systemImage: "plus.circle") { isAdding = true }
                    } footer: {
                        Text("Bölünen harcamada bütçene yalnız kendi payın girer. Elden borç ve geri ödemeler hesap bakiyeni değiştirir, bütçeni değiştirmez.")
                    }
                }
            }
        }
        .navigationTitle("Alacak ve borçlar")
        .sheet(isPresented: $isAdding) { PersonEditor() }
    }

    private func figure(_ title: LocalizedStringKey, _ value: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: Money(value, .TRY).formatted(locale: locale, fractionDigits: 0))
                .font(.title2.weight(.semibold))
                .foregroundStyle(value > 0 ? tint : .primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Ayşe · sana ₺450 borçlu".
struct BalanceText: View {
    let balance: Decimal
    @Environment(\.locale) private var locale

    var body: some View {
        let amount = Money(abs(balance), .TRY).formatted(locale: locale)
        if balance > 0 {
            Text("Alacağın \(amount)").foregroundStyle(.green)
        } else if balance < 0 {
            Text("Borcun \(amount)").foregroundStyle(.orange)
        } else {
            Text("Hesap kapalı").foregroundStyle(.secondary)
        }
    }
}

private struct PersonRow: View {
    let person: Person
    let balance: Decimal

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.name)
                if let remindAt = person.remindAt, balance != 0 {
                    Text("Hatırlatma \(remindAt.formatted(.dateTime.day().month(.wide)))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            BalanceText(balance: balance).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct PersonDetailView: View {
    let person: Person
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [DebtRecord]
    @Query private var transactions: [LedgerTransaction]
    @State private var action: DebtKind?
    @State private var hasReminder = false
    @State private var reminder = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        let store = DebtStore(context: context)
        let history = (try? store.records(for: person.id)) ?? []
        let balance = history.reduce(Decimal(0)) { $0 + $1.amount }
        List {
            Section {
                // Ad zaten başlıkta; burada yalnız bakiye.
                BalanceText(balance: balance)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.vertical, 4)
                if balance != 0 {
                    Button(balance > 0 ? "Ödedi" : "Ödedim", systemImage: "checkmark.circle") { action = .settlement }
                }
                if balance > 0 {
                    ShareLink(item: DebtMath.reminderMessage(name: person.name,
                                                             amount: Money(balance, .TRY).formatted(locale: locale))) {
                        Label("Hatırlat", systemImage: "bubble.left")
                    }
                }
            } footer: {
                if balance > 0 {
                    Text("\"Hatırlat\" hazır bir mesajla paylaş sayfasını açar; mesajı sen gönderirsin.")
                }
            }

            Section {
                Button("Borç verdim", systemImage: "arrow.up.right") { action = .lent }
                Button("Borç aldım", systemImage: "arrow.down.left") { action = .borrowed }
            } footer: {
                Text("Bir harcamayı bölmek için işlemi aç ve \"Böl\"e dokun.")
            }

            if balance != 0 {
                Section {
                    Toggle("Hatırlatma", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("Gün", selection: $reminder, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text("O gün sabah 10:00'da sana hatırlatılır.")
                }
                .onChange(of: hasReminder) { _, _ in saveReminder() }
                .onChange(of: reminder) { _, _ in saveReminder() }
            }

            if !history.isEmpty {
                Section("Geçmiş") {
                    ForEach(history) { record in
                        DebtRecordRow(record: record)
                            .swipeActions {
                                Button("Sil", role: .destructive) { try? store.delete(record) }
                            }
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .toolbar {
            ToolbarItem {
                if balance == 0 {
                    Button("Listeden kaldır") {
                        try? store.archive(person)
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $action) { kind in
            DebtEntrySheet(person: person, kind: kind, balance: balance)
        }
        .onAppear {
            hasReminder = person.remindAt != nil
            if let remindAt = person.remindAt { reminder = remindAt }
        }
    }

    private func saveReminder() {
        person.remindAt = hasReminder ? reminder : nil
        try? context.save()
        Reminders.schedulePerson(person, balance: (try? DebtStore(context: context).balances()[person.id]) ?? 0)
        if hasReminder { Reminders.requestAuthorizationIfNeeded() }
    }
}

extension DebtKind: @retroactive Identifiable {
    public var id: String { rawValue }
}

private struct DebtRecordRow: View {
    let record: DebtRecord
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            Text(verbatim: Money(record.amount, .TRY).formatted(locale: locale, sign: .always))
                .foregroundStyle(record.amount > 0 ? Color.green : Color.orange)
                .monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: [record.note, record.date.formatted(.dateTime.day().month(.wide))]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch record.kind {
        case .split: "Bölünen harcama"
        case .lent: "Borç verdin"
        case .borrowed: "Borç aldın"
        case .settlement: record.amount < 0 ? "Sana ödedi" : "Sen ödedin"
        }
    }
}

/// Borç ver / al / öde: tutar ve hesap.
private struct DebtEntrySheet: View {
    let person: Person
    let kind: DebtKind
    let balance: Decimal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var date = Date.now
    @State private var failed = false

    private var amount: Decimal? { AmountParser(locale: locale).parse(amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var usable: [LedgerAccount] { accounts.filter { $0.currency == .TRY && $0.kind != .card } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tutar", text: $amountText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker(kind == .lent || (kind == .settlement && balance < 0) ? "Hangi hesaptan" : "Hangi hesaba",
                           selection: $accountID) {
                        ForEach(usable) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("Tarih", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Hesap bakiyen değişir; bütçene girmez.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(amount == nil || accountID == nil)
                }
            }
            .alert("Kaydedilemedi", isPresented: $failed) { Button("Tamam") {} }
            .onAppear {
                accountID = accountID ?? usable.first?.id
                if kind == .settlement, amountText.isEmpty {
                    amountText = abs(balance).formattedNumber(locale: locale, fractionDigits: 0...2)
                        .replacingOccurrences(of: locale.groupingSeparator ?? "", with: "")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .lent: "Borç verdim"
        case .borrowed: "Borç aldım"
        case .settlement: balance > 0 ? "Ödedi" : "Ödedim"
        case .split: "Böl"
        }
    }

    private func save() {
        guard let amount, let account = usable.first(where: { $0.id == accountID }) else { return }
        do {
            try DebtStore(context: context).record(kind, person: person, amount: amount, account: account, date: date)
            dismiss()
        } catch {
            failed = true
        }
    }
}

/// Yeni kişi: ad ya da (iOS) rehberden seçim. Rehbere kalıcı erişim istenmez (K4).
struct PersonEditor: View {
    var onSave: ((Person) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var contactID: String?
    @State private var isPickingContact = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $name)
                        .accessibilityIdentifier("person.name")
                    #if os(iOS)
                    Button("Rehberden seç", systemImage: "person.crop.circle.badge.plus") { isPickingContact = true }
                    #endif
                } footer: {
                    Text("Kişi yalnız bu cihazdaki defterinde durur.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Kişi ekle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPickingContact) {
                ContactPicker { picked in
                    name = picked.name
                    contactID = picked.id
                }
                .ignoresSafeArea()
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        if let person = try? DebtStore(context: context).addPerson(name: name, contactID: contactID) {
                            onSave?(person)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }
}

#if os(iOS)
/// Sistem kişi seçicisi: seçilen kişinin yalnız adı ve kimliği gelir; izin istemez.
private struct ContactPicker: UIViewControllerRepresentable {
    struct Picked: Sendable { let id: String; let name: String }
    let onPick: @MainActor @Sendable (Picked) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: @MainActor @Sendable (Picked) -> Void
        init(onPick: @escaping @MainActor @Sendable (Picked) -> Void) { self.onPick = onPick }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let picked = Picked(id: contact.identifier, name: name.isEmpty ? contact.organizationName : name)
            let onPick = self.onPick
            MainActor.assumeIsolated { onPick(picked) }
        }
    }
}
#endif

/// Bir gideri arkadaşlarla böl (specs/10 §4): eşit, tutar ya da yüzde.
struct SplitSheet: View {
    let transaction: LedgerTransaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<Person> { !$0.isArchived }, sort: \Person.name) private var people: [Person]

    private enum Mode: Hashable { case equal, amount, percent }
    @State private var mode: Mode = .equal
    @State private var selected: Set<UUID> = []
    @State private var values: [UUID: String] = [:]
    @State private var isAddingPerson = false
    @State private var failed = false
    @State private var didLoad = false

    private var total: Decimal { transaction.amount.amount }
    private var parser: AmountParser { AmountParser(locale: locale) }

    private var shares: [(person: Person, amount: Decimal)] {
        let chosen = people.filter { selected.contains($0.id) }
        switch mode {
        case .equal:
            let each = DebtMath.equalShares(total: total, others: chosen.count).each
            return chosen.map { ($0, each) }
        case .amount:
            return chosen.compactMap { person in parser.parse(values[person.id] ?? "").map { (person, $0) } }
        case .percent:
            return chosen.compactMap { person in
                parser.parse(values[person.id] ?? "").map { (person, DebtMath.share(of: total, percent: $0)) }
            }
        }
    }

    private var mine: Decimal { total - shares.reduce(0) { $0 + $1.amount } }
    private var isValid: Bool { shares.allSatisfy { $0.amount > 0 } && mine > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Toplam", value: transaction.amount.formatted(locale: locale))
                    Picker("Bölme", selection: $mode) {
                        Text("Eşit").tag(Mode.equal)
                        Text("Tutar").tag(Mode.amount)
                        Text("Yüzde").tag(Mode.percent)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(people) { person in
                        HStack {
                            Button {
                                if selected.contains(person.id) { selected.remove(person.id) } else { selected.insert(person.id) }
                            } label: {
                                Label {
                                    Text(verbatim: person.name).foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            if selected.contains(person.id) {
                                if mode == .equal {
                                    Text(verbatim: Money(DebtMath.equalShares(total: total, others: selected.count).each, .TRY)
                                        .formatted(locale: locale))
                                        .foregroundStyle(.secondary).monospacedDigit()
                                } else {
                                    TextField(mode == .amount ? "₺" : "%", text: Binding(
                                        get: { values[person.id] ?? "" }, set: { values[person.id] = $0 }))
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .frame(maxWidth: 110)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                }
                            }
                        }
                    }
                    Button("Kişi ekle", systemImage: "plus.circle") { isAddingPerson = true }
                } header: {
                    Text("Kimlerle")
                }
                Section {
                    LabeledContent("Senin payın") {
                        Text(verbatim: Money(mine, .TRY).formatted(locale: locale))
                            .foregroundStyle(mine > 0 ? Color.primary : Color.red)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Hesabından tamamı çıkar; bütçene yalnız senin payın girer. Diğer paylar alacak olarak yazılır.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Böl")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(!isValid && !selected.isEmpty)
                }
            }
            .alert("Bölünemedi", isPresented: $failed) { Button("Tamam") {} } message: {
                Text("Paylar toplam tutardan az olmalı.")
            }
            .sheet(isPresented: $isAddingPerson) {
                PersonEditor { person in selected.insert(person.id) }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let existing = (try? DebtStore(context: context).splitShares(of: transaction)) ?? []
        guard !existing.isEmpty else { return }
        selected = Set(existing.map(\.personID))
        let amounts = Set(existing.map(\.amount))
        if amounts.count > 1 || amounts.first != DebtMath.equalShares(total: total, others: existing.count).each {
            mode = .amount
            for record in existing {
                values[record.personID] = record.amount.formattedNumber(locale: locale, fractionDigits: 0...2)
                    .replacingOccurrences(of: locale.groupingSeparator ?? "", with: "")
            }
        }
    }

    private func save() {
        do {
            try DebtStore(context: context).split(transaction, shares: selected.isEmpty ? [] : shares)
            dismiss()
        } catch {
            failed = true
        }
    }
}

/// Özet'teki bağlantı: "Alacak ve borçlar · alacağın ₺1.450".
struct DebtsLinkLabel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query private var records: [DebtRecord]

    var body: some View {
        let totals = DebtMath.totals((try? DebtStore(context: context).balances()) ?? [:])
        HStack {
            Label("Alacak ve borçlar", systemImage: "person.2")
            Spacer()
            if totals.receivable > 0 {
                Text("alacak \(Money(totals.receivable, .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .foregroundStyle(.secondary).monospacedDigit()
            } else if totals.payable > 0 {
                Text("borç \(Money(totals.payable, .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
