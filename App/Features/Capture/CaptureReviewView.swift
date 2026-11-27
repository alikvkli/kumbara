import CoreGraphics
import KumbaraCapture
import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// OCR önerilerinin onayı (REQ-C3…C6, specs/04 §3, specs/06 §6.5). Hiçbir öneri onaysız kaydedilmez (C5).
struct CaptureReviewView: View {
    let review: CaptureSession.Review
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if review.result.drafts.count > 1 {
                    MultiDraftReview(review: review)
                } else if let draft = review.result.drafts.first {
                    SingleDraftReview(review: review, suggestion: draft)
                } else {
                    ContentUnavailableView("Tutar bulunamadı", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Görüntüde bir toplam tutar tanıyamadım. İşlemi elle ekleyebilirsin."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    CorpusExportButton(lines: review.lines, kind: review.result.kind)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
        #endif
    }
}

// MARK: Tek taslak

private struct SingleDraftReview: View {
    let review: CaptureSession.Review
    let suggestion: CapturedDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var date = Date.now
    @State private var category: LedgerCategory?
    @State private var account: LedgerAccount?
    @State private var duplicate: LedgerEntry?
    @State private var didLoad = false
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case amount, merchant, date }

    private var store: LedgerStore { LedgerStore(context: context) }

    private var draft: TransactionDraft {
        TransactionDraft(kind: suggestion.kind, amount: AmountParser(locale: locale).parse(amountText), date: date,
                         account: account?.ref, category: category?.ref, merchant: merchant)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let preview = review.preview {
                ReceiptPreview(image: preview, highlights: highlights)
                    .overlay(alignment: .bottom) { chips.padding(12) }
                    .frame(maxHeight: 340)
            }
            Form {
                Section {
                    reviewField(lowConfidence: suggestion.amount?.isLowConfidence ?? true) {
                        HStack(alignment: .firstTextBaseline) {
                            TextField("Tutar", text: $amountText)
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                                .focused($focus, equals: .amount)
                                .accessibilityIdentifier("review.amount")
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text(verbatim: (account?.currency ?? suggestion.currency).rawValue).foregroundStyle(.secondary)
                        }
                    }
                    reviewField(lowConfidence: suggestion.merchant?.isLowConfidence ?? true) {
                        TextField("Satıcı", text: $merchant).focused($focus, equals: .merchant)
                            .accessibilityIdentifier("review.merchant")
                    }
                    reviewField(lowConfidence: suggestion.date.isLowConfidence) {
                        DatePicker("Tarih", selection: $date).focused($focus, equals: .date)
                    }
                } footer: {
                    if (suggestion.amount?.isLowConfidence ?? true) || suggestion.date.isLowConfidence {
                        Text("Turuncu işaretli alanlardan emin olamadım; kontrol et.")
                    }
                }
                Section {
                    NavigationLink {
                        CategoryPicker(kind: CategoryKind(suggestion.kind) ?? .expense, selection: $category)
                    } label: {
                        LabeledContent("Kategori") { Text(verbatim: category?.path ?? "—") }
                    }
                    Picker("Hesap", selection: $account) {
                        ForEach(accounts) { Text(verbatim: $0.name).tag(Optional($0)) }
                    }
                    if let vat = suggestion.vat {
                        LabeledContent("KDV") { Text(verbatim: Money(vat, .TRY).formatted(locale: locale)).monospacedDigit() }
                    }
                }
                if let duplicate {
                    Section {
                        Label {
                            Text("Benzer bir kayıt var: \(duplicate.merchant ?? "—") · \(duplicate.amount.formatted(locale: locale)) · \(duplicate.date.formatted(date: .abbreviated, time: .omitted))")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    } footer: {
                        Text("Yine de kaydedebilirsin.")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle(review.result.kind == .notification ? "Bildirim" : "Fiş")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Onayla", action: save)
                    .primaryActionStyle()
                    .disabled(!draft.isValid)
            }
        }
        .alert("Kaydedilemedi", isPresented: $saveFailed) { Button("Tamam", role: .cancel) {} }
        .onChange(of: amountText) { _, _ in checkDuplicate() }
        .onChange(of: date) { _, _ in checkDuplicate() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            load()
        }
    }

    private var highlights: [ReceiptPreview.Highlight] {
        var result: [ReceiptPreview.Highlight] = []
        if let amount = suggestion.amount { result += amount.boxes.map { .init(box: $0, lowConfidence: amount.isLowConfidence) } }
        if let merchant = suggestion.merchant { result += merchant.boxes.map { .init(box: $0, lowConfidence: merchant.isLowConfidence) } }
        result += suggestion.date.boxes.map { .init(box: $0, lowConfidence: suggestion.date.isLowConfidence) }
        return result
    }

    /// Görüntü üstünde yüzen alan kapsülleri: düzenlenen değeri gösterir, dokununca alanı odaklar (specs/06 §6.5).
    private var chips: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                chip(Text(verbatim: amountText.isEmpty ? "—" : amountText), low: suggestion.amount?.isLowConfidence ?? true, field: .amount)
                chip(Text(date, format: .dateTime.day().month(.abbreviated)), low: suggestion.date.isLowConfidence, field: .date)
                chip(Text(verbatim: merchant.isEmpty ? "—" : merchant), low: suggestion.merchant?.isLowConfidence ?? true, field: .merchant)
            }
        }
    }

    private func chip(_ label: Text, low: Bool, field: Field) -> some View {
        Button { focus = field } label: { label.lineLimit(1).monospacedDigit() }
            .buttonStyle(.glass)
            .overlay(Capsule().strokeBorder(Color.orange, lineWidth: low ? 1.5 : 0))
            .accessibilityHint(low ? Text("Emin değilim, kontrol et") : Text(""))
    }

    private func reviewField<Content: View>(lowConfidence: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowBackground(lowConfidence ? Color.orange.opacity(0.12) : nil)
    }

    private func load() {
        if let amount = suggestion.amount?.value {
            var text = amount.formattedNumber(locale: locale, fractionDigits: 2...2)
            if let grouping = locale.groupingSeparator, !grouping.isEmpty { text = text.replacingOccurrences(of: grouping, with: "") }
            amountText = text
        }
        merchant = suggestion.merchant?.value ?? ""
        date = suggestion.date.value
        account = (try? store.defaultAccount()) ?? accounts.first
        // Kullanıcının satıcı hafızası rehberin önerisinden önce gelir (REQ-L6).
        category = (try? store.suggestedCategory(forMerchant: merchant))
            ?? suggestion.categoryKey.flatMap { try? store.category(seedKey: $0) }
        if let category, category.kind != CategoryKind(suggestion.kind) { self.category = nil }
        focus = (suggestion.amount?.isLowConfidence ?? true) ? .amount : nil
        checkDuplicate()
    }

    private func checkDuplicate() {
        guard let amount = draft.amount else { duplicate = nil; return }
        duplicate = (try? store.entries(around: date))?.first {
            DuplicateCheck.isLikelyDuplicate(amount: amount, date: date, merchant: merchant, existing: $0, calendar: .current)
        }
    }

    private func save() {
        do {
            try store.save(draft, origin: .ocr)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

// MARK: Çoklu taslak (banka listesi, REQ-C5)

private struct MultiDraftReview: View {
    let review: CaptureSession.Review
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var rows: [Row] = []
    @State private var account: LedgerAccount?
    @State private var didLoad = false
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    struct Row: Identifiable {
        let id = UUID()
        var draft: CapturedDraft
        var category: LedgerCategory?
        var include: Bool
        var isDuplicate: Bool
    }

    private var store: LedgerStore { LedgerStore(context: context) }

    var body: some View {
        List {
            if let preview = review.preview {
                Section {
                    ReceiptPreview(image: preview, highlights: rows.flatMap { $0.draft.amount?.boxes ?? [] }.map { .init(box: $0, lowConfidence: false) })
                        .frame(maxHeight: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                Picker("Hesap", selection: $account) {
                    ForEach(accounts) { Text(verbatim: $0.name).tag(Optional($0)) }
                }
            }
            Section {
                ForEach($rows) { $row in
                    Toggle(isOn: $row.include) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.draft.merchant?.value ?? String(localized: "Açıklamasız"))
                                HStack(spacing: 4) {
                                    Text(row.draft.date.value, format: .dateTime.day().month(.abbreviated))
                                    if let category = row.category { Text(verbatim: "· \(category.name)") }
                                    if row.isDuplicate { Text("· olası mükerrer").foregroundStyle(.orange) }
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let amount = row.draft.amount?.value {
                                AmountText(Money(amount, .TRY), kind: row.draft.kind)
                            }
                        }
                    }
                }
            } header: {
                Text("\(rows.count) hareket bulundu")
            } footer: {
                Text("Mükerrer olabilecekler seçili gelmez. Eklemek istemediklerinin işaretini kaldır.")
            }
        }
        .navigationTitle("Hesap hareketleri")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("\(rows.filter(\.include).count) işlemi ekle", action: save)
                    .primaryActionStyle()
                    .disabled(!rows.contains(where: \.include) || account == nil)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            account = (try? store.defaultAccount()) ?? accounts.first
            rows = review.result.drafts.map { draft in
                let merchant = draft.merchant?.value ?? ""
                let category = draft.kind == .transfer ? nil
                    : ((try? store.suggestedCategory(forMerchant: merchant)) ?? draft.categoryKey.flatMap { try? store.category(seedKey: $0) })
                let duplicate = draft.amount.map { amount in
                    ((try? store.entries(around: draft.date.value)) ?? []).contains {
                        DuplicateCheck.isLikelyDuplicate(amount: amount.value, date: draft.date.value, merchant: merchant,
                                                         existing: $0, calendar: .current)
                    }
                } ?? false
                return Row(draft: draft, category: category, include: !duplicate, isDuplicate: duplicate)
            }
        }
    }

    private func save() {
        guard let account else { return }
        for row in rows where row.include {
            guard let amount = row.draft.amount?.value else { continue }
            let category = row.category.flatMap { CategoryKind(row.draft.kind) == $0.kind ? $0 : nil }
            let draft = TransactionDraft(kind: row.draft.kind, amount: amount, date: row.draft.date.value,
                                         account: account.ref, category: category?.ref, merchant: row.draft.merchant?.value ?? "")
            try? store.save(draft, origin: .ocr)
        }
        dismiss()
    }
}

// MARK: Görüntü + kanıt çerçeveleri

struct ReceiptPreview: View {
    struct Highlight: Hashable {
        let box: TextBox
        let lowConfidence: Bool
    }

    let image: CGImage
    let highlights: [Highlight]

    var body: some View {
        GeometryReader { geometry in
            let size = fittedSize(in: geometry.size)
            let origin = CGPoint(x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                ForEach(highlights, id: \.self) { highlight in
                    Rectangle()
                        .strokeBorder(highlight.lowConfidence ? Color.orange : Color.accentColor, lineWidth: 2)
                        .frame(width: highlight.box.width * size.width + 8, height: highlight.box.height * size.height + 6)
                        .offset(x: highlight.box.x * size.width - 4, y: highlight.box.y * size.height - 3)
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: origin.x, y: origin.y)
        }
        .background(Color.secondary.opacity(0.08))
        .accessibilityLabel(Text("Fiş görüntüsü; tanınan alanlar çerçeveli"))
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let ratio = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let width = min(container.width, container.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}

/// Gerçek fişlerden test korpusu toplamak için OCR çıktısını paylaş (T3.1).
private struct CorpusExportButton: View {
    let lines: [TextLine]
    let kind: DocumentKind

    var body: some View {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kumbara-ocr-\(kind.rawValue).json")
        let _ = try? CorpusExport.json(lines: lines, description: "").write(to: url)
        ShareLink(item: url) {
            Label("OCR çıktısını paylaş", systemImage: "square.and.arrow.up")
        }
    }
}
