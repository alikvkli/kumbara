import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Hesaplar (REQ-L1): her hesabın tek para birimi var; bakiye işlemlerden hesaplanır.
struct AccountsView: View {
    @Query(sort: \LedgerAccount.sortIndex) private var accounts: [LedgerAccount]
    @State private var editing: AccountEditor.Target?
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
                ForEach(accounts.filter { !$0.isArchived }) { account in
                    row(account)
                }
            }
            let archived = accounts.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Arşiv") {
                    ForEach(archived) { row($0) }
                }
            }
        }
        .navigationTitle("Hesaplar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Hesap ekle", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { target in
            AccountEditor(target: target, nextSortIndex: (accounts.map(\.sortIndex).max() ?? 0) + 1)
        }
    }

    private func row(_ account: LedgerAccount) -> some View {
        Button {
            editing = .existing(account)
        } label: {
            HStack {
                Label {
                    Text(verbatim: account.name)
                } icon: {
                    Image(systemName: account.kind.systemImage)
                }
                Spacer()
                Text(verbatim: account.balance.formatted(locale: locale))
                    .monospacedDigit()
                    .foregroundStyle(account.balance.isNegative ? .red : .secondary)
            }
        }
        .tint(.primary)
    }
}

struct AccountEditor: View {
    enum Target: Identifiable {
        case new
        case existing(LedgerAccount)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let account): account.id.uuidString
            }
        }
    }

    let target: Target
    let nextSortIndex: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var kind = AccountKind.bank
    @State private var currency = CurrencyCode.TRY
    @State private var openingText = ""
    @State private var isArchived = false
    @State private var statementDay: Int?
    @State private var paymentDueDay: Int?
    @State private var didLoad = false

    private static let currencies: [CurrencyCode] = [.TRY, .USD, .EUR, .GBP, .CHF]

    private var existing: LedgerAccount? {
        if case .existing(let account) = target { return account }
        return nil
    }

    /// Para birimi, işlemi olan hesapta değiştirilemez (tutarlar o birimde kaydedildi).
    private var currencyLocked: Bool {
        guard let existing else { return false }
        return !(existing.transactions ?? []).isEmpty || !(existing.incomingTransfers ?? []).isEmpty
    }

    private var opening: Decimal? {
        openingText.isEmpty ? 0 : AmountParser(locale: locale).parse(openingText)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && opening != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $name, prompt: Text("Örn. Maaş hesabı"))
                    Picker("Tür", selection: $kind) {
                        ForEach(AccountKind.allCases, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    Picker("Para birimi", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { code in
                            Text(verbatim: code.rawValue).tag(code)
                        }
                    }
                    .disabled(currencyLocked)
                } footer: {
                    if currencyLocked {
                        Text("İşlemi olan hesabın para birimi değiştirilemez.")
                    }
                }
                Section {
                    TextField("Açılış bakiyesi", text: $openingText, prompt: Text(verbatim: "0"))
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                } footer: {
                    Text("Uygulamayı kullanmaya başladığın andaki bakiye. Kredi kartı borcu için eksi gir.")
                }
                if kind == .card {
                    Section {
                        Picker("Ekstre kesim günü", selection: $statementDay) {
                            Text("Belirtilmedi").tag(Int?.none)
                            ForEach(1...31, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                        }
                        Picker("Son ödeme günü", selection: $paymentDueDay) {
                            Text("Kesimden 10 gün sonra").tag(Int?.none)
                            ForEach(1...31, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                        }
                        .disabled(statementDay == nil)
                    } header: {
                        Text("Ekstre")
                    } footer: {
                        Text("Kesim gününe göre dönem harcaman, ekstre borcun ve son ödeme tarihin gösterilir; son ödemeden 3 gün önce hatırlatma gelir.")
                    }
                }
                if existing != nil {
                    Section {
                        Toggle("Arşivle", isOn: $isArchived)
                    } footer: {
                        Text("Arşivlenen hesap yeni işlemlerde görünmez; geçmiş kayıtları korunur.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Yeni hesap" : "Hesabı düzenle")
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
                        .disabled(!isValid)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                if let existing {
                    name = existing.name
                    kind = existing.kind
                    currency = existing.currency
                    isArchived = existing.isArchived
                    statementDay = existing.statementDay
                    paymentDueDay = existing.paymentDueDay
                    let amount = existing.openingBalance.amount
                    openingText = amount.isZero ? "" : amount.formattedNumber(locale: locale, fractionDigits: 0...2)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func save() {
        guard let opening else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.name = trimmed
            existing.kind = kind
            if !currencyLocked { existing.currency = currency }
            existing.openingBalance = Money(opening, existing.currency)
            existing.isArchived = isArchived
            existing.statementDay = kind == .card ? statementDay : nil
            existing.paymentDueDay = kind == .card ? paymentDueDay : nil
        } else {
            let account = LedgerAccount(name: trimmed, kind: kind, currency: currency,
                                        openingBalance: opening, sortIndex: nextSortIndex)
            account.statementDay = kind == .card ? statementDay : nil
            account.paymentDueDay = kind == .card ? paymentDueDay : nil
            context.insert(account)
        }
        if kind == .card, statementDay != nil { Reminders.requestAuthorizationIfNeeded() }
        try? context.save()
        dismiss()
    }
}
