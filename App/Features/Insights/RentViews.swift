import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçe › Kira artışı (REQ-I9, specs/12). Hesap TÜFE tablosundan; kayıt üretmez.
struct RentContractsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Query(sort: \RentContract.createdAt) private var contracts: [RentContract]
    @State private var isAdding = false

    var body: some View {
        Group {
            if contracts.isEmpty {
                ContentUnavailableView {
                    Label("Kira sözleşmesi yok", systemImage: "house")
                } description: {
                    Text("Sözleşme başlangıcını ve kirayı gir; yenilemede yasal artış sınırı TÜFE'ye göre hesaplanır ve bir ay önceden hatırlatılır.")
                } actions: {
                    Button("Sözleşme ekle") { isAdding = true }.primaryActionStyle()
                }
            } else {
                List {
                    Section {
                        ForEach(contracts) { contract in
                            NavigationLink { RentDetailView(contract: contract) } label: {
                                RentRow(contract: contract)
                            }
                        }
                    } footer: {
                        Text("Konut ve işyeri kiralarında artış, önceki kira yılındaki TÜFE 12 aylık ortalamasını geçemez (TBK m.344).")
                    }
                }
            }
        }
        .navigationTitle("Kira artışı")
        .toolbar {
            if !contracts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Sözleşme ekle", systemImage: "plus") { isAdding = true }
                }
            }
        }
        .sheet(isPresented: $isAdding) { RentEditor() }
    }
}

private struct RentRow: View {
    let contract: RentContract
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let quote = RentStore(context: context).quote(for: contract, calendar: calendar)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: contract.name.isEmpty ? String(localized: "Kira") : contract.name)
                Text("Yenileme \(quote.renewal.formatted(.dateTime.day().month(.wide).year()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let maximum = quote.maximumRent {
                Text("en fazla \(Money(maximum, .TRY).formatted(locale: locale))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("oran bekleniyor").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bir sözleşmenin yenileme hesabı.
struct RentDetailView: View {
    let contract: RentContract
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var isEditing = false
    @State private var rateText = ""
    @State private var agreedText = ""
    @State private var savedNotice = false

    private var store: RentStore { RentStore(context: context) }
    private var parser: AmountParser { AmountParser(locale: locale) }

    var body: some View {
        let quote = store.quote(for: contract, calendar: calendar)
        let reference = quote.referenceMonth.title(calendar: calendar)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.role == .tenant ? "Yeni kira en fazla" : "İsteyebileceğin kira en fazla")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let maximum = quote.maximumRent {
                        HeroAmount(money: Money(maximum, .TRY))
                    } else {
                        Text("Oran henüz yok").font(.title2.weight(.semibold))
                    }
                    Text("\(quote.year). kira yılı · \(quote.renewal.formatted(.dateTime.day().month(.wide).year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Şu anki kira") { money(contract.rent) }
                if let rate = quote.rate {
                    LabeledContent("Artış oranı") {
                        Text(verbatim: rate.formattedPercent(locale: locale, fractionDigits: 2)).monospacedDigit()
                    }
                    if let increase = quote.maximumIncrease {
                        LabeledContent("En fazla artış") { money(increase) }
                    }
                }
            } footer: {
                switch quote.source {
                case .table?:
                    Text("Oran: \(reference) TÜFE 12 aylık ortalamalara göre değişim (TÜİK). Yenileme ayından önceki ayın oranı kullanılır.")
                case .manual?:
                    Text("Oran elle girildi: \(reference) için TÜİK'in açıkladığı 12 aylık ortalama.")
                case nil:
                    let published = RentIncrease.publicationDate(of: quote.referenceMonth, calendar: calendar)
                    if published > .now {
                        Text("Bu yenileme \(reference) oranıyla hesaplanır; TÜİK bu veriyi \(published.formatted(.dateTime.day().month(.wide))) günü açıklar.")
                    } else {
                        Text("\(reference) verisi uygulamanın TÜFE tablosunda henüz yok. TÜİK'in açıkladığı 12 aylık ortalama oranı aşağıya girersen hesap yapılır.")
                    }
                }
            }

            if quote.source != .table {
                Section {
                    HStack {
                        TextField("12 aylık ortalama", text: $rateText)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: "%").foregroundStyle(.secondary)
                    }
                    Button("Oranı kaydet") {
                        let rate = parser.parse(rateText).map { $0 / 100 }
                        try? store.setManualRate(rate, month: quote.referenceMonth, for: contract)
                    }
                    .disabled(parser.parse(rateText) == nil)
                } header: {
                    Text("Açıklanan oran")
                } footer: {
                    Text("TÜİK bülteninde \"12 aylık ortalamalara göre değişim\" satırı. Uygulama güncellenip tablo bu ayı içerince elle girilen oranın yerine tablo kullanılır.")
                }
            }

            Section {
                HStack {
                    TextField("Kararlaştırılan kira", text: $agreedText)
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(verbatim: "₺").foregroundStyle(.secondary)
                }
                if let agreed, let maximum = quote.maximumRent, agreed > maximum {
                    Label {
                        Text("Bu tutar yasal sınırı \(Money(agreed - maximum, .TRY).formatted(locale: locale)) aşıyor. Sınırı aşan artış anlaşması geçerli sayılmaz.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }
                Button("Yeni kirayı kaydet") {
                    guard let agreed else { return }
                    try? store.applyNewRent(agreed, to: contract)
                    agreedText = ""
                    savedNotice = true
                    RentReminders.schedule([contract])
                }
                .disabled(agreed == nil)
            } header: {
                Text("Yenileme")
            } footer: {
                if savedNotice {
                    Text("Kaydedildi. Bağlı tekrarlayan işlem varsa sonraki taslaklar bu tutarla gelir; geçmiş kayıtlar değişmez.")
                } else if (try? store.linkedRule(of: contract)) != nil {
                    Text("Bağlı tekrarlayan işlemin tutarı da güncellenir; geçmiş kayıtlar değişmez.")
                } else {
                    Text("Sınır bir üst limittir; daha düşük bir artışta anlaşabilirsin.")
                }
            }

            Section {
                if quote.isPastFiveYears {
                    Text("Sözleşme 5 yılı doldurdu. Bu durumda yeni kira, emsal kiralara ve hakkaniyete göre mahkemece belirlenebilir; bu hesap o durumu kapsamaz.")
                }
                Text("Bu hesap bilgi amaçlıdır, hukuki danışmanlık yerine geçmez. Döviz cinsinden kiralar için ayrı kurallar vardır.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle(contract.name.isEmpty ? String(localized: "Kira") : contract.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Düzenle") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) { RentEditor(editing: contract) }
        .onAppear {
            if let manual = contract.manualRate, manual.month == quote.referenceMonth {
                rateText = (manual.rate * 100).formattedNumber(locale: locale, fractionDigits: 0...2)
            }
        }
    }

    private var agreed: Decimal? { parser.parse(agreedText).flatMap { $0 > 0 ? $0 : nil } }

    private func money(_ value: Decimal) -> some View {
        Text(verbatim: Money(value, .TRY).formatted(locale: locale)).monospacedDigit()
    }
}

/// Yeni ya da düzenlenen sözleşme; altta canlı hesap.
struct RentEditor: View {
    var editing: RentContract? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var role: RentIncrease.Role = .tenant
    @State private var start = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    @State private var rentText = ""
    @State private var ruleID: UUID?
    @State private var rules: [RecurringRule] = []
    @State private var didLoad = false
    @State private var isConfirmingDelete = false

    private var rent: Decimal? { AmountParser(locale: locale).parse(rentText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad (ör. Ev kirası)", text: $name)
                    Picker("Taraf", selection: $role) {
                        Text("Kiracı").tag(RentIncrease.Role.tenant)
                        Text("Ev sahibi").tag(RentIncrease.Role.landlord)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Sözleşme başlangıcı", selection: $start, displayedComponents: .date)
                    HStack {
                        TextField("Şu anki aylık kira", text: $rentText)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(verbatim: "₺").foregroundStyle(.secondary)
                    }
                } footer: {
                    if let rent {
                        let quote = RentIncrease.quote(start: start, currentRent: rent, now: .now, cpi: CPIData.turkey,
                                                       manualRate: editing?.manualRate, calendar: calendar)
                        if let maximum = quote.maximumRent {
                            Text("\(quote.renewal.formatted(.dateTime.day().month(.wide).year())) yenilemesinde en fazla \(Money(maximum, .TRY).formatted(locale: locale)).")
                        } else {
                            Text("\(quote.renewal.formatted(.dateTime.day().month(.wide).year())) yenilemesinin oranı \(quote.referenceMonth.title(calendar: calendar)) verisiyle belli olur.")
                        }
                    } else {
                        Text("Yıl dönümleri yenileme günü sayılır. Konut ve işyeri için kural aynıdır.")
                    }
                }
                if !rules.isEmpty {
                    Section {
                        Picker("Tekrarlayan işlem", selection: $ruleID) {
                            Text("Yok").tag(UUID?.none)
                            ForEach(rules) { rule in
                                Text(verbatim: ruleTitle(rule)).tag(Optional(rule.id))
                            }
                        }
                    } footer: {
                        Text("Bağlarsan yeni kira kaydedilince tekrarlayan işlemin tutarı da güncellenir.")
                    }
                }
                if editing != nil {
                    Section {
                        Button("Sözleşmeyi sil", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Kira sözleşmesi" : "Sözleşmeyi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(rent == nil)
                }
            }
            .confirmationDialog("Sözleşme silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let editing {
                        RentReminders.cancel(editing.id)
                        try? RentStore(context: context).delete(editing)
                    }
                    dismiss()
                }
            } message: {
                Text("Tekrarlayan işlem ve geçmiş kayıtlar silinmez.")
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func ruleTitle(_ rule: RecurringRule) -> String {
        let title = rule.merchant ?? rule.category?.name ?? String(localized: "Tekrarlayan işlem")
        guard let currency = rule.account?.currency else { return title }
        return "\(title) · \(Money(rule.amount, currency).formatted(locale: locale, fractionDigits: 0))"
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let store = RentStore(context: context)
        rules = (try? store.candidateRules()) ?? []
        if let editing {
            name = editing.name
            role = editing.role
            start = editing.start
            rentText = plain(editing.rent)
            ruleID = editing.recurringRuleID
        } else if let rule = rules.first(where: { rule in
            let key: String = rule.category?.seedKey ?? ""
            return key == "housing.rent" || key == "rental"
        }) {
            ruleID = rule.id
            role = rule.kind == .income ? .landlord : .tenant
            rentText = plain(rule.amount)
            start = rule.start
        }
    }

    private func plain(_ value: Decimal) -> String {
        var text = value.formattedNumber(locale: locale, fractionDigits: 0...2)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty { text = text.replacingOccurrences(of: grouping, with: "") }
        return text
    }

    private func save() {
        guard let rent else { return }
        let store = RentStore(context: context)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing {
            editing.name = trimmed
            editing.role = role
            editing.start = calendar.startOfDay(for: start)
            editing.rent = rent
            editing.recurringRuleID = ruleID
            try? store.save()
            RentReminders.schedule([editing])
        } else if let contract = try? store.add(name: trimmed, role: role, start: start, rent: rent,
                                                recurringRuleID: ruleID, calendar: calendar) {
            RentReminders.schedule([contract])
        }
        Reminders.requestAuthorizationIfNeeded()
        dismiss()
    }
}

/// Bütçe ekranındaki bağlantı: "Kira artışı · yenileme 1 Aralık".
struct RentLinkLabel: View {
    @Environment(\.calendar) private var calendar
    @Query(sort: \RentContract.createdAt) private var contracts: [RentContract]

    var body: some View {
        HStack {
            Label("Kira artışı", systemImage: "house")
            Spacer()
            if let next = nextRenewal {
                Text("yenileme \(next.formatted(.dateTime.day().month(.wide)))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nextRenewal: Date? {
        contracts.map { RentIncrease.relevantRenewal(start: $0.start, now: .now, calendar: calendar).date }.min()
    }
}
