import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Ayarlar › Dışa aktar ve yedekle: dışa aktarma, yedek, geri yükleme, banka ekstresi içe aktarma (specs/09 §3).
struct DataExchangeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var exportDocument: ExportDocument?
    @State private var isExporting = false
    @State private var isPickingStatement = false
    @State private var isPickingBackup = false
    @State private var statement: StatementFile?
    @State private var pendingBackup: Data?
    @State private var message: Message?

    var body: some View {
        Form {
            Section {
                Button("İşlemleri tabloya aktar (CSV)", systemImage: "tablecells") { exportCSV() }
                Button("Tam yedek al", systemImage: "externaldrive") { exportBackup() }
            } header: {
                Text("Dışa aktar")
            } footer: {
                Text("Tablo Excel ve Numbers'da açılır. Yedek tek bir dosyadır; hesapları, kategorileri, işlemleri, bütçeleri, birikimleri, hedefleri ve alarmları içerir, fiş görüntülerini içermez.")
            }
            Section {
                Button("Banka ekstresi içe aktar (CSV)…", systemImage: "doc.text") { isPickingStatement = true }
                    .fileImporter(isPresented: $isPickingStatement, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
                        openStatement(result)
                    }
                Button("Yedekten geri yükle…", systemImage: "arrow.counterclockwise") { isPickingBackup = true }
                    .fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.json]) { result in
                        openBackup(result)
                    }
            } header: {
                Text("İçe aktar")
            } footer: {
                Text("Ekstredeki satırlar taslak olarak gelir; İşlemler'de onaylayana kadar hiçbir toplama girmez. Daha önce alınmış satırlar atlanır.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dışa aktar ve yedekle")
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: exportDocument?.contentType ?? .json,
                      defaultFilename: exportDocument?.filename) { result in
            if case .failure = result { message = Message(title: "Dışa aktarılamadı", body: "Dosya kaydedilemedi.") }
        }
        .sheet(item: $statement) { file in
            StatementImportView(file: file) { summary in
                message = Message(
                    title: summary.created > 0 ? "\(summary.created) taslak eklendi" : "Yeni satır yok",
                    body: summary.duplicates > 0
                        ? "\(summary.duplicates) satır zaten vardı, atlandı. Taslaklar İşlemler'de onay bekliyor."
                        : "Taslaklar İşlemler'de onay bekliyor.")
            }
        }
        .confirmationDialog("Yedek nasıl yüklensin?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
                            titleVisibility: .visible) {
            Button("Birleştir") { restore(.merge) }
            Button("Mevcut verinin yerine koy", role: .destructive) { restore(.replace) }
            Button("Vazgeç", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("Birleştir: yedekte olup burada olmayanlar eklenir. Yerine koy: buradaki veri silinir, yedek yüklenir; önce mevcut verinin bir yedeği Dosyalar'a kaydedilir.")
        }
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
               presenting: message) { _ in
            Button("Tamam") { message = nil }
        } message: { message in
            Text(message.body)
        }
    }

    private var stamp: String { Date.now.formatted(.iso8601.year().month().day()) }

    private func exportCSV() {
        do {
            let text = try ExchangeStore(context: context).transactionsCSV(locale: locale)
            exportDocument = ExportDocument(data: Data(text.utf8), contentType: .commaSeparatedText, filename: "Kumbara-islemler-\(stamp).csv")
            isExporting = true
        } catch {
            message = Message(title: "Dışa aktarılamadı", body: error.localizedDescription)
        }
    }

    private func exportBackup() {
        do {
            exportDocument = ExportDocument(data: try ExchangeStore(context: context).backupJSON(), contentType: .json,
                                            filename: "Kumbara-yedek-\(stamp).json")
            isExporting = true
        } catch {
            message = Message(title: "Yedek alınamadı", body: error.localizedDescription)
        }
    }

    private func openStatement(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result, let data = Self.read(url), let text = Self.decodeText(data) else {
            message = Message(title: "Dosya okunamadı", body: "CSV dosyası açılamadı ya da metin değil.")
            return
        }
        let table = CSV.decode(text)
        guard !table.isEmpty else {
            message = Message(title: "Dosya boş", body: "İçe aktarılacak satır bulunamadı.")
            return
        }
        statement = StatementFile(name: url.lastPathComponent, table: table)
    }

    private func openBackup(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result, let data = Self.read(url) else {
            message = Message(title: "Dosya okunamadı", body: "Yedek dosyası açılamadı.")
            return
        }
        pendingBackup = data
    }

    private func restore(_ mode: ExchangeStore.RestoreMode) {
        guard let data = pendingBackup else { return }
        pendingBackup = nil
        let store = ExchangeStore(context: context)
        do {
            if mode == .replace { try Self.saveSafetyBackup(try store.backupJSON()) }
            try store.restore(data, mode: mode)
            message = Message(title: "Yedek yüklendi", body: mode == .replace
                              ? "Önceki verinin yedeği Dosyalar › Kumbara › Yedekler klasöründe."
                              : "Yedekteki yeni kayıtlar eklendi.")
        } catch ExchangeStore.RestoreError.newerVersion {
            message = Message(title: "Yedek daha yeni bir sürümden", body: "Bu yedeği açmak için Kumbara'yı güncelle.")
        } catch {
            message = Message(title: "Yedek yüklenemedi", body: "Dosya bir Kumbara yedeği değil ya da bozuk. Verine dokunulmadı.")
        }
    }

    /// "Yerine koy"dan önce mevcut veri uygulamanın Belgeler klasörüne yazılır (Dosyalar'da görünür).
    private static func saveSafetyBackup(_ data: Data) throws {
        let folder = URL.documentsDirectory.appending(path: "Yedekler", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "Kumbara-otomatik-yedek-\(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))).json"
            .replacingOccurrences(of: ":", with: "-")
        try data.write(to: folder.appending(path: name), options: .atomic)
    }

    private static func read(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    /// Bankalar UTF-8 ya da Windows-1254 (Türkçe) yazar.
    static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1254)
    }

    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }
}

struct StatementFile: Identifiable {
    let id = UUID()
    let name: String
    let table: [[String]]
}

struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .json]

    var data: Data
    var contentType: UTType
    var filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? "Kumbara"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Ekstre eşleme ekranı

/// Sütun eşleme (specs/09 §3.2): tahmin dolu gelir, kullanıcı düzeltir; önizleme anında güncellenir.
struct StatementImportView: View {
    let file: StatementFile
    let onImported: (ExchangeStore.ImportSummary) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(filter: #Predicate<LedgerAccount> { !$0.isArchived }, sort: \LedgerAccount.sortIndex)
    private var accounts: [LedgerAccount]

    @State private var mapping: CSVImportMapping?
    @State private var accountID: UUID?
    @State private var failed = false

    private var columnCount: Int { file.table.map(\.count).max() ?? 0 }
    private var result: CSVImportResult? { mapping.map { CSVImporter.apply($0, to: file.table) } }

    var body: some View {
        NavigationStack {
            Form {
                if let mapping = Binding($mapping) {
                    previewSection
                    Section("Sütunlar") {
                        Toggle("İlk satır başlık", isOn: mapping.hasHeader)
                        columnPicker("Tarih", selection: mapping.date)
                        columnPicker("Açıklama", selection: mapping.description)
                        Picker("Tutar", selection: amountStyle(mapping)) {
                            Text("Tek sütun").tag(false)
                            Text("Borç / Alacak").tag(true)
                        }
                        switch mapping.wrappedValue.amount {
                        case let .signed(column, positiveIsExpense):
                            columnPicker("Tutar sütunu", selection: Binding(
                                get: { column },
                                set: { mapping.wrappedValue.amount = .signed(column: $0, positiveIsExpense: positiveIsExpense) }))
                            Toggle("Artı tutarlar harcama", isOn: Binding(
                                get: { positiveIsExpense },
                                set: { mapping.wrappedValue.amount = .signed(column: column, positiveIsExpense: $0) }))
                        case let .split(debit, credit):
                            columnPicker("Borç (çıkan)", selection: Binding(
                                get: { debit }, set: { mapping.wrappedValue.amount = .split(debit: $0, credit: credit) }))
                            columnPicker("Alacak (giren)", selection: Binding(
                                get: { credit }, set: { mapping.wrappedValue.amount = .split(debit: debit, credit: $0) }))
                        }
                    }
                    Section("Biçim") {
                        Picker("Tarih biçimi", selection: mapping.dateFormat) {
                            ForEach(CSVImporter.dateFormats, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                        Picker("Ondalık ayırıcı", selection: Binding(
                            get: { String(mapping.wrappedValue.decimalSeparator) },
                            set: { mapping.wrappedValue.decimalSeparator = $0.first ?? "," })) {
                            Text(verbatim: "1.234,56").tag(",")
                            Text(verbatim: "1,234.56").tag(".")
                        }
                    }
                    Section {
                        Picker("Hesap", selection: $accountID) {
                            ForEach(accounts) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    } footer: {
                        Text("Satırlar bu hesaba taslak olarak eklenir.")
                    }
                } else {
                    ContentUnavailableView("Sütunlar tanınamadı", systemImage: "tablecells.badge.ellipsis",
                                           description: Text("Dosyada tarih ve tutar sütunu bulunamadı. Bankanın CSV ya da Excel'den kaydedilmiş CSV dosyasını dene."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: file.name))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("İçe aktar", action: importRows)
                        .primaryActionStyle()
                        .disabled(result?.rows.isEmpty != false || accountID == nil)
                }
            }
            .alert("İçe aktarılamadı", isPresented: $failed) { Button("Tamam") {} }
            .onAppear {
                if mapping == nil { mapping = CSVImporter.guessMapping(for: file.table) }
                if accountID == nil { accountID = (accounts.first { $0.kind == .bank } ?? accounts.first)?.id }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private var previewSection: some View {
        if let result {
            Section {
                ForEach(result.rows.prefix(5), id: \.line) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.description).lineLimit(1)
                            Text(row.date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: (row.kind == .expense ? "−" : "+") + row.amount.formattedNumber(locale: locale, fractionDigits: 2...2))
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Önizleme")
            } footer: {
                if result.issues.isEmpty {
                    Text("\(result.rows.count) satır okunacak.")
                } else {
                    let lines = result.issues.prefix(5).map { String($0.line) }.joined(separator: ", ")
                    Text("\(result.rows.count) satır okunacak · \(result.issues.count) satır okunamadı (satır \(lines)).")
                }
            }
        }
    }

    private func columnTitle(_ index: Int) -> String {
        if mapping?.hasHeader == true, let header = file.table.first, index < header.count, !header[index].isEmpty {
            return header[index]
        }
        let sample = file.table.dropFirst(mapping?.hasHeader == true ? 1 : 0).first.flatMap { index < $0.count ? $0[index] : nil } ?? ""
        return String(localized: "Sütun \(index + 1)") + (sample.isEmpty ? "" : " · \(sample.prefix(16))")
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<columnCount, id: \.self) { Text(verbatim: columnTitle($0)).tag($0) }
        }
    }

    private func amountStyle(_ mapping: Binding<CSVImportMapping>) -> Binding<Bool> {
        Binding(
            get: { if case .split = mapping.wrappedValue.amount { true } else { false } },
            set: { split in
                let current = mapping.wrappedValue.amount
                switch (split, current) {
                case (true, let .signed(column, _)):
                    mapping.wrappedValue.amount = .split(debit: column, credit: min(column + 1, max(columnCount - 1, 0)))
                case (false, let .split(debit, _)):
                    mapping.wrappedValue.amount = .signed(column: debit, positiveIsExpense: false)
                default: break
                }
            })
    }

    private func importRows() {
        guard let result, let account = accounts.first(where: { $0.id == accountID }) else { return }
        do {
            let summary = try ExchangeStore(context: context).importRows(result.rows, into: account)
            dismiss()
            onImported(summary)
        } catch {
            failed = true
        }
    }
}
