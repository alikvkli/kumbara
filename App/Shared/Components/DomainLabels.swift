import KumbaraCore
import SwiftUI

extension TransactionKind {
    var label: LocalizedStringKey {
        switch self {
        case .expense: "Gider"
        case .income: "Gelir"
        case .transfer: "Transfer"
        }
    }

    var newTitle: LocalizedStringKey {
        switch self {
        case .expense: "Yeni gider"
        case .income: "Yeni gelir"
        case .transfer: "Yeni transfer"
        }
    }
}

extension AccountKind {
    var label: LocalizedStringKey {
        switch self {
        case .cash: "Nakit"
        case .bank: "Banka hesabı"
        case .card: "Kredi kartı"
        case .savings: "Birikim hesabı"
        }
    }

    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .card: "creditcard"
        case .savings: "archivebox"
        }
    }
}

extension CategoryKind {
    var label: LocalizedStringKey {
        switch self {
        case .expense: "Gider"
        case .income: "Gelir"
        }
    }
}

extension CategoryColor {
    var label: LocalizedStringKey {
        switch self {
        case .gray: "Gri"
        case .teal: "Camgöbeği"
        case .green: "Yeşil"
        case .mint: "Nane"
        case .orange: "Turuncu"
        case .brown: "Kahverengi"
        case .purple: "Mor"
        case .indigo: "Çivit"
        }
    }

    /// Sistem renkleri: koyu mod ve yüksek karşıtlık varyantları otomatik (specs/06 §3).
    var color: Color {
        switch self {
        case .gray: .gray
        case .teal: .teal
        case .green: .green
        case .mint: .mint
        case .orange: .orange
        case .brown: .brown
        case .purple: .purple
        case .indigo: .indigo
        }
    }
}

extension TransactionDraft.Issue {
    var message: LocalizedStringKey {
        switch self {
        case .missingAmount: "Tutar gir."
        case .nonPositiveAmount: "Tutar sıfırdan büyük olmalı."
        case .missingAccount: "Bir hesap seç."
        case .missingDestination: "Hedef hesabı seç."
        case .sameAccountTransfer: "Aynı hesaba transfer yapılamaz."
        case .transferCurrencyMismatch: "Farklı para birimli hesaplar arasında transfer henüz desteklenmiyor."
        case .categoryKindMismatch: "Kategori bu işlem türüne uymuyor."
        }
    }
}
