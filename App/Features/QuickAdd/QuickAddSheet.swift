import KumbaraCore
import SwiftUI

/// Hızlı ekleme sayfası (REQ-L4). Kalıcı kayıt M1'de (T1.3) bağlanır.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var amountText = ""
    @State private var direction: Direction = .expense
    @FocusState private var amountFocused: Bool

    enum Direction: Hashable { case expense, income }

    private var amount: Decimal? {
        AmountParser(locale: locale).parse(amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $direction) {
                        Text("Gider").tag(Direction.expense)
                        Text("Gelir").tag(Direction.income)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    TextField("Tutar", text: $amountText, prompt: Text(verbatim: "0"))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .focused($amountFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle(direction == .expense ? "Yeni gider" : "Yeni gelir")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .disabled(amount == nil)
                }
            }
            .sensoryFeedback(.selection, trigger: direction)
        }
        .onAppear { amountFocused = true }
    }
}

/// Boş durumlardaki tek eylem (specs/06 §9: boş durum = ContentUnavailableView + tek eylem).
struct AddTransactionButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button("İşlem ekle") { router.isPresentingQuickAdd = true }
    }
}
