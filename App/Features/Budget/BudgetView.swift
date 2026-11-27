import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Bütçeler (REQ-B1, B2; specs/08 §1.4).
///
/// Ekran üç soruya cevap verir: **bugün ne kadar harcayabilirim**, **plana göre neredeyim**,
/// **bu gidişle ay sonu ne olur**. Kahraman rakam günlük haktır; her çubukta "bugün burada
/// olmalıydın" işareti vardır. Renk yalnız anlam taşır: normal vurgu, %80+ turuncu, aşım kırmızı (C6).
struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Environment(PriceBoard.self) private var board
    @Environment(AppRouter.self) private var router
    // Gözlem için: işlem ya da bütçe değişince ekran yeniden hesaplanır.
    @Query private var transactions: [LedgerTransaction]
    @Query private var budgetModels: [Budget]
    @State private var selectedMonth: LedgerMonth?
    @State private var editing: BudgetEditor.Target?
    @State private var detail: UUID?
    @State private var isCheckingPurchase = false

    private var month: LedgerMonth { selectedMonth ?? LedgerMonth(containing: .now, calendar: calendar) }
    private var store: BudgetStore { BudgetStore(context: context) }

    var body: some View {
        let statuses = (try? store.statuses(for: month, calendar: calendar, rate: rate)) ?? []
        let overall = statuses.first { $0.categoryID == nil }
        let categories = statuses.filter { $0.categoryID != nil }.sorted(by: BudgetStatus.urgency)
        let suggestions = categories.isEmpty ? ((try? store.suggestions(before: month, calendar: calendar)) ?? []) : []

        Group {
            if budgetModels.isEmpty && suggestions.isEmpty {
                ContentUnavailableView {
                    Label("Bütçe yok", systemImage: "chart.pie")
                } description: {
                    Text("Aylık bir limit belirle; her gün ne kadar harcayabileceğini ve ayı nasıl kapatacağını gör.")
                } actions: {
                    Button("Bütçe ekle") { editing = .new }
                        .primaryActionStyle()
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            MonthMenu(month: month, selection: $selectedMonth)
                            if let overall {
                                OverallHeader(status: overall)
                                    .contentShape(Rectangle())
                                    .onTapGesture { detail = overall.id }
                                    .accessibilityAddTraits(.isButton)
                            } else {
                                OverallPrompt { editing = .overall }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    }

                    if !categories.isEmpty {
                        Section {
                            ForEach(categories) { status in
                                let model = budgetModels.first { $0.id == status.id }
                                Button { detail = status.id } label: {
                                    CategoryBudgetRow(status: status, category: model?.category)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Sil", role: .destructive) { if let model { try? store.delete(model) } }
                                    if let category = model?.category {
                                        Button("Düzenle") { editing = .category(category) }.tint(.accentColor)
                                    }
                                }
                            }
                            // Araç çubuğunda zaten "yeni işlem" (+) var; ikinci bir + karışır (specs/06 §9).
                            Button("Bütçe ekle", systemImage: "plus.circle") { editing = .new }
                        } header: {
                            Text("Kategoriler")
                        } footer: {
                            if statuses.contains(where: \.hasUnconvertedEntries) {
                                Text("Kuru bulunamayan döviz harcamaları bütçeye sayılmadı.")
                            }
                        }
                    }

                    // Ödeme takvimi ve abonelikler (specs/10 §2, §5).
                    Section {
                        NavigationLink { PaymentCalendarView() } label: {
                            PaymentCalendarLinkLabel()
                        }
                        NavigationLink { SubscriptionsView() } label: {
                            SubscriptionsLinkLabel()
                        }
                        Button { isCheckingPurchase = true } label: {
                            Label("Alabilir miyim?", systemImage: "questionmark.circle")
                        }
                    }

                    if !suggestions.isEmpty {
                        Section {
                            ForEach(suggestions, id: \.category.id) { item in
                                SuggestionRow(category: item.category, limit: item.limit) {
                                    _ = try? store.setLimit(item.limit, for: item.category, from: month)
                                    BudgetMonitor.shared.requestAuthorizationIfNeeded()
                                }
                            }
                            if suggestions.count > 1 {
                                Button("Hepsini ekle") {
                                    for item in suggestions { _ = try? store.setLimit(item.limit, for: item.category, from: month) }
                                    BudgetMonitor.shared.requestAuthorizationIfNeeded()
                                }
                            }
                        } header: {
                            Text("Önerilen bütçeler")
                        } footer: {
                            Text("Son 3 ayda bu kategorilere ortalama harcadığın tutar, yukarı yuvarlanmış.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bütçe")
        .navigationDestination(isPresented: Binding(get: { router.isPresentingCalendar },
                                                    set: { router.isPresentingCalendar = $0 })) {
            PaymentCalendarView()
        }
        .navigationDestination(item: $detail) { id in
            BudgetDetailView(budgetID: id, month: month)
        }
        .sheet(isPresented: $isCheckingPurchase) { PurchaseCheckView() }
        .sheet(item: $editing) { target in
            BudgetEditor(target: target, month: month)
        }
    }

    /// Döviz giderleri güncel kurla TRY'ye çevrilir (specs/08 §1.2).
    private func rate(_ currency: CurrencyCode, _ date: Date) -> Decimal? {
        board.quote(.fx(currency))?.mid
    }
}

// MARK: - Ortak parçalar

extension BudgetStatus {
    /// İçinde bulunulan ayda renk tempoya göredir: ayın sonunda %89 dolu bir bütçe plana uygundur,
    /// turuncu yalnız gerçekten dikkat gerekiyorsa (plandan belirgin önde ya da ay sonu aşacak).
    /// Biten ayda doluluk seviyesine göre.
    var tint: Color {
        if level == .over { return .red }
        if isCurrentMonth { return isProjectedOver || isAheadOfPace ? .orange : .accentColor }
        return level == .warning ? .orange : .accentColor
    }

    var progress: Double { (min(max(ratio, 0), 1) as NSDecimalNumber).doubleValue }
    var elapsedFraction: Double { (elapsed as NSDecimalNumber).doubleValue }
    var isCurrentMonth: Bool { elapsed > 0 && elapsed < 1 }

    /// Acil olan önce: aşılanlar, sonra ay sonunda aşacaklar, sonra doluluk.
    static func urgency(_ a: BudgetStatus, _ b: BudgetStatus) -> Bool {
        func rank(_ s: BudgetStatus) -> Int { s.level == .over ? 0 : s.isProjectedOver ? 1 : 2 }
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        return a.ratio != b.ratio ? a.ratio > b.ratio : a.id.uuidString < b.id.uuidString
    }
}

/// Harcama çubuğu + "bugün burada olmalıydın" işareti.
struct PaceBar: View {
    let status: BudgetStatus
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: height)
                if status.progress > 0 {
                    Capsule().fill(status.tint)
                        .frame(width: max(height, width * status.progress), height: height)
                }
                if status.isCurrentMonth {
                    Capsule()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: height + 8)
                        .offset(x: width * status.elapsedFraction - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 8)
        .accessibilityElement()
        .accessibilityLabel(Text("Bütçenin yüzde \(Int(status.progress * 100)) kadarı kullanıldı"))
    }
}

/// "Plana göre ₺1.200 fazla" / "az" / "Plana uygun".
struct PaceText: View {
    let status: BudgetStatus
    @Environment(\.locale) private var locale

    var body: some View {
        let delta = status.paceDelta.amount
        let tolerance = status.limit.amount / 100
        let amount = Money(abs(delta), status.limit.currency).formatted(locale: locale, fractionDigits: 0)
        if delta > tolerance {
            Text("Plana göre \(amount) fazla").foregroundStyle(.orange)
        } else if delta < -tolerance {
            Text("Plana göre \(amount) az").foregroundStyle(.secondary)
        } else {
            Text("Plana uygun").foregroundStyle(.secondary)
        }
    }
}

/// Genel bütçe başlığı: kahraman rakam bugünkü harcama hakkı.
private struct OverallHeader: View {
    let status: BudgetStatus
    @Environment(\.locale) private var locale

    private func money(_ value: Money) -> String { value.formatted(locale: locale, fractionDigits: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.level == .over {
                Text("Bütçe aşıldı").font(.subheadline).foregroundStyle(.secondary)
                Text(verbatim: money(status.spent - status.limit))
                    .font(.largeTitle.weight(.semibold)).foregroundStyle(.red)
            } else if status.isCurrentMonth {
                Text("Bugün harcayabileceğin").font(.subheadline).foregroundStyle(.secondary)
                Text(verbatim: money(status.perDay)).font(.largeTitle.weight(.semibold))
            } else {
                Text("Ay kapandı").font(.subheadline).foregroundStyle(.secondary)
                Text("\(money(status.remaining)) altında").font(.largeTitle.weight(.semibold))
            }

            PaceBar(status: status, height: 10)

            HStack(alignment: .firstTextBaseline) {
                if status.isCurrentMonth && status.level != .over {
                    Text("\(money(status.remaining)) kaldı · \(status.remainingDays) gün")
                } else {
                    Text("\(money(status.spent)) / \(money(status.limit))")
                }
                Spacer()
                if status.isCurrentMonth { PaceText(status: status) }
            }
            .font(.subheadline)

            if status.isCurrentMonth, let projected = status.projected {
                Text("Bu gidişle ay sonu ≈ \(money(projected))")
                    .font(.footnote)
                    .foregroundStyle(status.isProjectedOver || status.level == .over ? Color.orange : Color.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

private struct OverallPrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aylık toplam bir limit belirlersen her gün ne kadar harcayabileceğini burada görürsün.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Genel bütçe belirle", action: action)
                .buttonStyle(.bordered)
        }
    }
}

/// Kategori satırı: sağda kalan (ya da aşan) tutar, altında tempo çubuğu ve tek cümlelik durum.
private struct CategoryBudgetRow: View {
    let status: BudgetStatus
    let category: LedgerCategory?
    @Environment(\.locale) private var locale

    private func money(_ value: Money) -> String { value.formatted(locale: locale, fractionDigits: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                CategoryBadge(systemImage: category?.resolvedSymbol ?? "circle.dashed", color: category?.color.color ?? .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: category?.path ?? "—")
                    caption.font(.footnote)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: money(status.level == .over ? status.spent - status.limit : status.remaining))
                        .font(.headline)
                        .foregroundStyle(status.level == .over ? Color.red : Color.primary)
                    Text(status.level == .over ? "aştı" : "kaldı")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            PaceBar(status: status, height: 6)
        }
        .monospacedDigit()
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var caption: some View {
        if status.level == .over {
            Text("\(money(status.spent)) / \(money(status.limit))").foregroundStyle(.secondary)
        } else if status.isCurrentMonth, status.isProjectedOver, let projected = status.projected {
            Text("Bu gidişle ay sonu ≈ \(money(projected))").foregroundStyle(.orange)
        } else if status.isCurrentMonth {
            Text("günde \(money(status.perDay)) · limit \(money(status.limit))").foregroundStyle(.secondary)
        } else {
            Text("\(money(status.spent)) / \(money(status.limit))").foregroundStyle(.secondary)
        }
    }
}

private struct SuggestionRow: View {
    let category: LedgerCategory
    let limit: Decimal
    let add: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            CategoryBadge(systemImage: category.resolvedSymbol, color: category.color.color)
            Text(verbatim: category.name)
            Spacer()
            Text(verbatim: Money(limit, .TRY).formatted(locale: locale, fractionDigits: 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Ekle", action: add)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
