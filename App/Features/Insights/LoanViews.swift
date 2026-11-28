import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Özet › Krediler (REQ-I10, specs/13). Ödeme planı sözleşme koşullarından hesaplanır; banka planı esastır.
struct LoansView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Query(sort: \Loan.createdAt) private var loans: [Loan]
    @State private var isAdding = false

    var body: some View {
        let store = LoanStore(context: context)
        let open = loans.filter { !$0.isClosed }
        let closed = loans.filter(\.isClosed)
        Group {
            if loans.isEmpty {
                ContentUnavailableView {
                    Label("Kredi yok", systemImage: "building.columns")
                } description: {
                    Text("İhtiyaç, taşıt ya da konut kredini ekle; kalan borcu, taksitleri ve erken kapama tutarını gör. Taksitler ödeme takvimine düşer.")
                } actions: {
                    Button("Kredi ekle") { isAdding = true }.primaryActionStyle()
                }
            } else {
                List {
                    if !open.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Kalan anapara").font(.subheadline).foregroundStyle(.secondary)
                                HeroAmount(money: Money((try? store.totalRemaining(calendar: calendar)) ?? 0, .TRY))
                                let monthly = open.compactMap { store.nextInstallment(of: $0, calendar: calendar)?.payment }
                                    .reduce(Decimal(0), +)
                                Text("Aylık taksitler \(Money(monthly, .TRY).formatted(locale: locale))")
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                        }
                        Section {
                            ForEach(open) { loan in
                                NavigationLink { LoanDetailView(loan: loan) } label: { LoanRow(loan: loan) }
                            }
                            Button("Kredi ekle", systemImage: "plus.circle") { isAdding = true }
                        }
                    } else {
                        Section {
                            Button("Kredi ekle", systemImage: "plus.circle") { isAdding = true }
                        }
                    }
                    if !closed.isEmpty {
                        Section("Kapanan") {
                            ForEach(closed) { loan in
                                NavigationLink { LoanDetailView(loan: loan) } label: { LoanRow(loan: loan) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Krediler")
        .sheet(isPresented: $isAdding) { LoanEditor() }
    }
}

private struct LoanRow: View {
    let loan: Loan
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let store = LoanStore(context: context)
        let next = store.nextInstallment(of: loan, calendar: calendar)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: loan.name)
                if loan.closedAt != nil {
                    Text("Erken kapatıldı").font(.footnote).foregroundStyle(.secondary)
                } else if loan.isClosed {
                    Text("Bitti").font(.footnote).foregroundStyle(.secondary)
                } else if let next {
                    let overdue = next.due < calendar.startOfDay(for: .now)
                    Text("\(loan.paidCount) / \(loan.termMonths) taksit · sıradaki \(next.due.formatted(.dateTime.day().month(.wide)))")
                        .font(.footnote)
                        .foregroundStyle(overdue ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            if let next, !loan.isClosed {
                Text(verbatim: Money(next.payment, .TRY).formatted(locale: locale)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Krediler · kalan ₺52.000" (Özet bağlantısı).
struct LoansLinkLabel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query private var loans: [Loan]

    var body: some View {
        let remaining = (try? LoanStore(context: context).totalRemaining(calendar: calendar)) ?? 0
        HStack {
            Label("Krediler", systemImage: "building.columns")
            Spacer()
            if remaining > 0 {
                Text("kalan \(Money(remaining, .TRY).formatted(locale: locale, fractionDigits: 0))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

struct LoanDetailView: View {
    let loan: Loan
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]
    @Query private var transactions: [LedgerTransaction]
    @State private var isPaying = false
    @State private var isClosing = false
    @State private var isEditing = false
    @State private var isDeleting = false
    @State private var failed = false

    private var store: LoanStore { LoanStore(context: context) }
    private var account: LedgerAccount? {
        let usable = accounts.filter { $0.currency == .TRY && $0.kind != .card }
        return usable.first { $0.id == loan.accountID } ?? usable.first
    }

    var body: some View {
        let schedule = store.schedule(of: loan, calendar: calendar)
        let terms = loan.terms
        let remaining = LoanMath.remainingPrincipal(schedule, paidCount: loan.paidCount, principal: terms.principal)
        let next = store.nextInstallment(of: loan, calendar: calendar)
        let payoff = store.payoff(of: loan, calendar: calendar)
        let totals = LoanMath.totals(schedule)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loan.isClosed ? "Kredi kapandı" : "Kalan anapara").font(.subheadline).foregroundStyle(.secondary)
                    HeroAmount(money: Money(loan.isClosed ? 0 : remaining, .TRY))
                    ProgressView(value: Double(min(loan.paidCount, loan.termMonths)), total: Double(max(loan.termMonths, 1)))
                    Text("\(loan.paidCount) / \(loan.termMonths) taksit ödendi")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            if let next {
                Section {
                    LabeledContent {
                        Text(verbatim: money(next.payment)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(next.number). taksit")
                            if next.due < calendar.startOfDay(for: .now) {
                                Text("Vadesi geçti · \(next.due.formatted(.dateTime.day().month(.wide)))")
                                    .font(.footnote).foregroundStyle(.orange)
                            } else {
                                Text("Son ödeme \(next.due.formatted(.dateTime.day().month(.wide).weekday(.wide)))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Ödendi", systemImage: "checkmark.circle") { isPaying = true }
                    if loan.paidCount > 0 {
                        Button("Son ödemeyi geri al", systemImage: "arrow.uturn.backward") { perform { try store.undoLastPayment(loan) } }
                    }
                } header: {
                    Text("Sıradaki taksit")
                } footer: {
                    Text("Faiz \(money(next.interest)) · vergi \(money(next.tax)) · anapara \(money(next.principal)). \"Ödendi\" taksiti seçtiğin hesaptan gider olarak yazar.")
                }
            }

            if let payoff {
                Section {
                    LabeledContent("Kalan anapara") { Text(verbatim: money(payoff.remainingPrincipal)).monospacedDigit() }
                    LabeledContent("İşlemiş faiz") { Text(verbatim: money(payoff.accruedInterest)).monospacedDigit() }
                    if payoff.accruedTax > 0 {
                        LabeledContent("Vergi (KKDF + BSMV)") { Text(verbatim: money(payoff.accruedTax)).monospacedDigit() }
                    }
                    if payoff.fee > 0 {
                        LabeledContent("Erken ödeme tazminatı") { Text(verbatim: money(payoff.fee)).monospacedDigit() }
                    }
                    LabeledContent {
                        Text(verbatim: money(payoff.total)).monospacedDigit().fontWeight(.semibold)
                    } label: {
                        Text("Bugün kapatırsan").fontWeight(.semibold)
                    }
                    if payoff.saved > 0 {
                        Text("Kalan \(payoff.remainingInstallments) taksitte \(money(payoff.scheduledRemaining)) ödeyecektin; bugün kapatırsan \(money(payoff.saved)) daha az ödersin.")
                            .font(.subheadline)
                    }
                    Button("Erken kapattım", systemImage: "flag.checkered") { isClosing = true }
                } header: {
                    Text("Erken kapama")
                } footer: {
                    payoffFootnote(terms)
                }
            } else if loan.closedAt != nil {
                Section {
                    Button("Kapanışı geri al", systemImage: "arrow.uturn.backward") { perform { try store.reopen(loan) } }
                } footer: {
                    Text("Kapama tutarı defterden silinir, kredi yeniden açılır.")
                }
            }

            Section("Koşullar") {
                LabeledContent("Tür") { Text(LoanText.kind(terms.kind)) }
                LabeledContent("Çekilen tutar") { Text(verbatim: money(terms.principal)).monospacedDigit() }
                LabeledContent("Aylık faiz") {
                    Text(verbatim: terms.monthlyRate.formattedPercent(locale: locale, fractionDigits: 2)).monospacedDigit()
                }
                if terms.taxRate > 0 {
                    LabeledContent("Vergi (faizin)") {
                        Text(verbatim: terms.taxRate.formattedPercent(locale: locale, fractionDigits: 0)).monospacedDigit()
                    }
                }
                LabeledContent("Toplam geri ödeme") { Text(verbatim: money(totals.paid)).monospacedDigit() }
                LabeledContent("Toplam faiz ve vergi") { Text(verbatim: money(totals.interest + totals.tax)).monospacedDigit() }
            }

            Section("Ödeme planı") {
                ForEach(schedule) { row in
                    InstallmentRow(row: row, isPaid: row.number <= loan.paidCount)
                }
            }
        }
        .navigationTitle(loan.name)
        .toolbar {
            ToolbarItem {
                Menu("Diğer", systemImage: "ellipsis.circle") {
                    Button("Düzenle", systemImage: "pencil") { isEditing = true }
                    Button("Sil", systemImage: "trash", role: .destructive) { isDeleting = true }
                }
            }
        }
        .confirmationDialog("Taksit ödendi", isPresented: $isPaying, titleVisibility: .visible) {
            if let account {
                Button("\(account.name) hesabından") {
                    perform { _ = try store.markPaid(loan, account: account, calendar: calendar) }
                }
            }
            Button("Deftere yazmadan işaretle") {
                perform { _ = try store.markPaid(loan, account: nil, calendar: calendar) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Hesaptan ödendiyse taksit gider olarak yazılır ve bütçene girer.")
        }
        .confirmationDialog("Kredi kapatıldı", isPresented: $isClosing, titleVisibility: .visible) {
            if let payoff {
                if let account {
                    Button("\(account.name) hesabından \(money(payoff.total))") {
                        perform { _ = try store.close(loan, amount: payoff.total, account: account) }
                    }
                }
                Button("Deftere yazmadan kapat") {
                    perform { _ = try store.close(loan, amount: payoff.total, account: nil) }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bankanın bildirdiği tutar farklıysa önce koşulları düzenle.")
        }
        .confirmationDialog("Kredi silinsin mi?", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                let id = loan.id
                do {
                    try store.delete(loan)
                    Reminders.cancelLoan(id)
                    dismiss()
                } catch {
                    failed = true
                }
            }
        } message: {
            Text("Deftere yazılmış taksit ödemeleri kalır.")
        }
        .sheet(isPresented: $isEditing) { LoanEditor(editing: loan) }
        .alert("Kaydedilemedi", isPresented: $failed) { Button("Tamam") {} }
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale) }

    private func payoffFootnote(_ terms: LoanTerms) -> Text {
        switch terms.kind {
        case .housing where terms.isVariableRate:
            Text("Değişken faizli konut kredisinde erken ödeme tazminatı alınmaz.")
        case .housing:
            Text("Sabit faizli konut kredisinde tazminat, kalan anaparanın oranı olarak alınır: kalan vade 36 ay ve altındaysa \(percent(0.01)), üstündeyse \(percent(0.02)). Faiz indirimini geçemez.")
        case .personal, .vehicle:
            Text("Tüketici kredisinde erken ödeme tazminatı alınmaz; işlemiş faiz son vadeden bugüne gün hesabıyla eklenir. Kesin tutarı bankandan iste.")
        }
    }

    private func percent(_ value: Decimal) -> String { value.formattedPercent(locale: locale, fractionDigits: 0) }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            Reminders.scheduleLoans((try? store.loans()) ?? [], context: context)
        } catch {
            failed = true
        }
    }
}

private struct InstallmentRow: View {
    let row: LoanInstallment
    let isPaid: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Image(systemName: isPaid ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isPaid ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.number). taksit · \(row.due.formatted(.dateTime.day().month(.abbreviated).year()))")
                Text("Kalan \(Money(row.balanceAfter, .TRY).formatted(locale: locale))")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Text(verbatim: Money(row.payment, .TRY).formatted(locale: locale))
                .monospacedDigit()
                .foregroundStyle(isPaid ? Color.secondary : Color.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isPaid ? Text("Ödendi") : Text(""))
    }
}

enum LoanText {
    static func kind(_ kind: LoanKind) -> LocalizedStringKey {
        switch kind {
        case .personal: "İhtiyaç kredisi"
        case .vehicle: "Taşıt kredisi"
        case .housing: "Konut kredisi"
        }
    }
}

/// Yeni kredi ya da düzenleme. Bankanın verdiği taksit biliniyorsa faiz oranı ondan bulunur.
struct LoanEditor: View {
    var editing: Loan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    private enum Known: Hashable { case installment, rate }

    @State private var name = ""
    @State private var kind: LoanKind = .personal
    @State private var principalText = ""
    @State private var termText = ""
    @State private var known: Known = .installment
    @State private var installmentText = ""
    @State private var rateText = ""
    @State private var taxText = "30"
    @State private var isVariableRate = false
    @State private var firstDue = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var paidCount = 0
    @State private var paidTouched = false
    @State private var isSuggesting = false
    @State private var accountID: UUID?
    @State private var category: LedgerCategory?
    @State private var didLoad = false
    @State private var failed = false

    private var parser: AmountParser { AmountParser(locale: locale) }
    private var usable: [LedgerAccount] { accounts.filter { $0.currency == .TRY && $0.kind != .card } }
    private var principal: Decimal? { parser.parse(principalText).flatMap { $0 > 0 ? $0 : nil } }
    private var term: Int? { Int(termText.trimmingCharacters(in: .whitespaces)).flatMap { (1...480).contains($0) ? $0 : nil } }
    private var taxRate: Decimal { kind == .housing ? 0 : (parser.parse(taxText) ?? 0) / 100 }

    /// Girilenlerden koşullar; eksikse `nil`.
    private var terms: LoanTerms? {
        guard let principal, let term else { return nil }
        switch known {
        case .rate:
            guard let rate = parser.parse(rateText), rate >= 0 else { return nil }
            return LoanTerms(kind: kind, principal: principal, monthlyRate: rate / 100, taxRate: taxRate, termMonths: term,
                             firstDue: firstDue, isVariableRate: kind == .housing && isVariableRate)
        case .installment:
            guard let payment = parser.parse(installmentText), payment > 0,
                  let rate = LoanMath.solveRate(principal: principal, payment: payment, term: term, taxRate: taxRate) else { return nil }
            return LoanTerms(kind: kind, principal: principal, monthlyRate: rate, taxRate: taxRate, termMonths: term,
                             firstDue: firstDue, payment: payment, isVariableRate: kind == .housing && isVariableRate)
        }
    }

    /// İlk vade geçmişteyse bugüne kadar gelen vadeler ödenmiş varsayılır.
    private var suggestedPaid: Int {
        guard let term else { return 0 }
        let today = calendar.startOfDay(for: .now)
        let probe = LoanTerms(kind: kind, principal: 1, monthlyRate: 0, termMonths: term, firstDue: firstDue)
        return (1...term).filter { LoanMath.dueDate(probe, number: $0, calendar: calendar) <= today }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad (ör. Taşıt kredisi)", text: $name)
                    Picker("Tür", selection: $kind) {
                        ForEach(LoanKind.allCases, id: \.self) { Text(LoanText.kind($0)).tag($0) }
                    }
                }

                Section {
                    amountField("Çekilen tutar", text: $principalText)
                    TextField("Vade (ay)", text: $termText)
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Picker("Bildiğin", selection: $known) {
                        Text("Taksit").tag(Known.installment)
                        Text("Faiz oranı").tag(Known.rate)
                    }
                    .pickerStyle(.segmented)
                    if known == .installment {
                        amountField("Aylık taksit", text: $installmentText)
                    } else {
                        amountField("Aylık faiz oranı (ör. 3,49)", text: $rateText)
                    }
                    if kind == .housing {
                        Toggle("Değişken faizli", isOn: $isVariableRate)
                    } else {
                        LabeledContent("KKDF + BSMV oranı") {
                            HStack(spacing: 2) {
                                Text(verbatim: "%").foregroundStyle(.secondary)
                                TextField(text: $taxText) { Text(verbatim: "30") }
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(maxWidth: 80)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }
                        }
                    }
                } footer: {
                    if kind == .housing {
                        Text("Konut kredisi KKDF ve BSMV'den muaftır.")
                    } else {
                        let rate = Decimal(string: "0.15")!.formattedPercent(locale: locale, fractionDigits: 0)
                        Text("İhtiyaç ve taşıt kredisinde faize KKDF (\(rate)) ve BSMV (\(rate)) eklenir; ikisi de taksitin içindedir.")
                    }
                }

                if let terms {
                    Section("Hesap") {
                        let totals = LoanMath.totals(LoanMath.schedule(terms, calendar: calendar))
                        if known == .installment {
                            LabeledContent("Aylık faiz") {
                                Text(verbatim: terms.monthlyRate.formattedPercent(locale: locale, fractionDigits: 2))
                            }
                            LabeledContent("Yıllık faiz") {
                                Text(verbatim: LoanMath.annualRate(terms.monthlyRate).formattedPercent(locale: locale, fractionDigits: 2))
                            }
                        } else {
                            LabeledContent("Aylık taksit") { Text(verbatim: money(terms.installment)) }
                        }
                        LabeledContent("Toplam geri ödeme") { Text(verbatim: money(totals.paid)) }
                        LabeledContent("Toplam faiz ve vergi") { Text(verbatim: money(totals.interest + totals.tax)) }
                    }
                    .monospacedDigit()
                } else if principal != nil, term != nil, known == .installment, !installmentText.isEmpty {
                    Section {
                        Text("Taksit, çekilen tutarın vadeye bölümünden küçük olamaz.").foregroundStyle(.orange)
                    }
                }

                Section {
                    DatePicker("İlk taksit", selection: $firstDue, displayedComponents: .date)
                    Stepper(value: $paidCount, in: 0...(term ?? 0)) {
                        LabeledContent("Ödenmiş taksit") { Text(verbatim: "\(paidCount)").monospacedDigit() }
                    }
                    .onChange(of: paidCount) { _, _ in
                        if isSuggesting { isSuggesting = false } else { paidTouched = true }
                    }
                } footer: {
                    Text("Sonraki taksitler her ay aynı gün. Önceden ödediğin taksitler deftere yazılmaz.")
                }

                Section {
                    Picker("Ödeme hesabı", selection: $accountID) {
                        ForEach(usable) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    NavigationLink {
                        CategoryPicker(kind: .expense, selection: $category)
                    } label: {
                        LabeledContent("Kategori") { Text(verbatim: category?.path ?? String(localized: "Seç")) }
                    }
                } footer: {
                    Text("\"Ödendi\" dediğinde taksit bu hesaptan, bu kategoriyle gider olarak yazılır.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Kredi ekle" : "Krediyi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(terms == nil)
                }
            }
            .alert("Kaydedilemedi", isPresented: $failed) { Button("Tamam") {} }
            .onAppear(perform: load)
            .onChange(of: firstDue) { _, _ in suggestPaid() }
            .onChange(of: termText) { _, _ in
                suggestPaid()
                if let term { paidCount = min(paidCount, term) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func money(_ value: Decimal) -> String { Money(value, .TRY).formatted(locale: locale) }

    private func plain(_ value: Decimal, digits: ClosedRange<Int>) -> String {
        value.formattedNumber(locale: locale, fractionDigits: digits)
            .replacingOccurrences(of: locale.groupingSeparator ?? "", with: "")
    }

    private func suggestPaid() {
        guard editing == nil, !paidTouched else { return }
        let suggested = suggestedPaid
        guard suggested != paidCount else { return }
        // Öneri kullanıcı dokunuşu sayılmasın.
        isSuggesting = true
        paidCount = suggested
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let ledger = LedgerStore(context: context)
        guard let editing else {
            accountID = usable.first { $0.kind == .bank }?.id ?? usable.first?.id
            category = try? ledger.category(seedKey: "other.expense")
            return
        }
        let terms = editing.terms
        name = editing.name
        kind = terms.kind
        principalText = plain(terms.principal, digits: 0...2)
        termText = "\(terms.termMonths)"
        if let payment = terms.payment {
            known = .installment
            installmentText = plain(payment, digits: 0...2)
        } else {
            known = .rate
            rateText = plain(terms.monthlyRate * 100, digits: 0...4)
        }
        taxText = plain(terms.taxRate * 100, digits: 0...2)
        isVariableRate = terms.isVariableRate
        firstDue = terms.firstDue
        paidCount = editing.paidCount
        paidTouched = true
        accountID = editing.accountID ?? usable.first?.id
        category = editing.categoryID.flatMap { try? ledger.category(id: $0) }
    }

    private func save() {
        guard let terms else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? String(localized: kindName(terms.kind)) : trimmed
        do {
            let store = LoanStore(context: context)
            try store.save(name: title, terms: terms, paidCount: paidCount, accountID: accountID, categoryID: category?.id,
                           editing: editing)
            Reminders.requestAuthorizationIfNeeded()
            Reminders.scheduleLoans((try? store.loans()) ?? [], context: context)
            dismiss()
        } catch {
            failed = true
        }
    }

    private func kindName(_ kind: LoanKind) -> String.LocalizationValue {
        switch kind {
        case .personal: "İhtiyaç kredisi"
        case .vehicle: "Taşıt kredisi"
        case .housing: "Konut kredisi"
        }
    }
}
