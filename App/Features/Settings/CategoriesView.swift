import KumbaraCore
import KumbaraData
import SwiftData
import SwiftUI

/// Kategoriler (REQ-L5): iki seviyeli; yeniden adlandırma, ekleme, arşivleme.
/// Kullanılmış kategori silinmez, arşivlenir (geçmiş kayıtlar bozulmasın).
struct CategoriesView: View {
    @Query(sort: \LedgerCategory.sortIndex) private var all: [LedgerCategory]
    @State private var kind = CategoryKind.expense
    @State private var editing: CategoryEditor.Target?

    private var tops: [LedgerCategory] {
        all.filter { $0.parent == nil && $0.kind == kind }
    }

    var body: some View {
        List {
            Section {
                Picker("Tür", selection: $kind) {
                    ForEach(CategoryKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
            }
            ForEach(tops) { top in
                Section {
                    row(top)
                    ForEach((top.children ?? []).sorted { $0.sortIndex < $1.sortIndex }) { child in
                        row(child).padding(.leading, 28)
                    }
                    Button("Alt kategori ekle", systemImage: "plus") { editing = .new(kind: kind, parent: top) }
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Kategoriler")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Kategori ekle", systemImage: "plus") { editing = .new(kind: kind, parent: nil) }
            }
        }
        .sheet(item: $editing) { target in
            CategoryEditor(target: target, nextSortIndex: (all.map(\.sortIndex).max() ?? 0) + 1)
        }
    }

    private func row(_ category: LedgerCategory) -> some View {
        Button {
            editing = .existing(category)
        } label: {
            HStack {
                CategoryBadge(systemImage: category.resolvedSymbol, color: category.color.color)
                Text(verbatim: category.name)
                    .foregroundStyle(category.isArchived ? .secondary : .primary)
                Spacer()
                if category.isArchived {
                    Text("Arşivde").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }
}

struct CategoryEditor: View {
    enum Target: Identifiable {
        case new(kind: CategoryKind, parent: LedgerCategory?)
        case existing(LedgerCategory)

        var id: String {
            switch self {
            case .new(let kind, let parent): "new-\(kind.rawValue)-\(parent?.id.uuidString ?? "top")"
            case .existing(let category): category.id.uuidString
            }
        }
    }

    let target: Target
    let nextSortIndex: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = CategoryColor.gray
    @State private var isArchived = false
    @State private var didLoad = false

    private var existing: LedgerCategory? {
        if case .existing(let category) = target { return category }
        return nil
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $name)
                    if existing?.parent == nil, !isNewChild {
                        Picker("Renk", selection: $color) {
                            ForEach(CategoryColor.allCases, id: \.self) { color in
                                Label {
                                    Text(color.label)
                                } icon: {
                                    Image(systemName: "circle.fill").foregroundStyle(color.color)
                                }
                                .tag(color)
                            }
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Toggle("Arşivle", isOn: $isArchived)
                    } footer: {
                        Text("Arşivlenen kategori yeni işlemlerde görünmez; geçmiş kayıtlar korunur.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Yeni kategori" : "Kategoriyi düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!isValid)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                if let existing {
                    name = existing.name
                    color = existing.color
                    isArchived = existing.isArchived
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    private var isNewChild: Bool {
        if case .new(_, let parent) = target { return parent != nil }
        return false
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .existing(let category):
            category.name = trimmed
            category.isArchived = isArchived
            if category.parent == nil { category.color = color }
        case .new(let kind, let parent):
            context.insert(LedgerCategory(name: trimmed, kind: kind,
                                          symbol: parent == nil ? "circle" : "",
                                          color: parent?.color ?? color,
                                          parent: parent, sortIndex: nextSortIndex))
        }
        try? context.save()
        dismiss()
    }
}
