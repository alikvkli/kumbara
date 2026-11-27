import Foundation
import KumbaraCore

// Kalıcı modeller ↔ KumbaraCore değer tipleri.

extension LedgerAccount {
    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    public var currency: CurrencyCode {
        get { CurrencyCode(rawValue: currencyRaw) ?? .TRY }
        set { currencyRaw = newValue.rawValue }
    }

    public var openingBalance: Money {
        get { Money(Decimal(canonical: openingBalanceRaw) ?? 0, currency) }
        set {
            precondition(newValue.currency == currency, "Açılış bakiyesi hesabın para biriminde olmalı")
            openingBalanceRaw = newValue.amount.canonicalString
        }
    }

    public var ref: TransactionDraft.AccountRef { .init(id: id, currency: currency) }

    /// İlişkiler üzerinden bakiye (taslaklar hariç).
    public var balance: Money {
        let outgoing = (transactions ?? []).map(\.entry)
        let incoming = (incomingTransfers ?? []).map(\.entry)
        return AccountBalance.compute(accountID: id, opening: openingBalance, entries: outgoing + incoming)
    }
}

extension LedgerCategory {
    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var color: CategoryColor {
        get { CategoryColor(rawValue: colorRaw) ?? .gray }
        set { colorRaw = newValue.rawValue }
    }

    /// Alt kategoride sembol boşsa üst kategorininki.
    public var resolvedSymbol: String {
        if !symbol.isEmpty { return symbol }
        return parent?.resolvedSymbol ?? "circle"
    }

    /// "Market › Gıda" biçiminde tam ad.
    public var path: String {
        if let parent { return "\(parent.name) › \(name)" }
        return name
    }

    public var ref: TransactionDraft.CategoryRef { .init(id: id, kind: kind) }

    public var sortedChildren: [LedgerCategory] {
        (children ?? []).filter { !$0.isArchived }.sorted { $0.sortIndex < $1.sortIndex }
    }
}

extension LedgerTransaction {
    public var amount: Money {
        get { Money(Decimal(canonical: amountRaw) ?? 0, CurrencyCode(rawValue: currencyRaw) ?? .TRY) }
        set {
            precondition(newValue.amount > 0, "Tutar pozitif büyüklük olarak saklanır")
            amountRaw = newValue.amount.canonicalString
            currencyRaw = newValue.currency.rawValue
        }
    }

    public var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    public var origin: TransactionOrigin {
        get { TransactionOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    /// Gelir +, gider −, transfer 0.
    public var signedAmount: Money { entry.signedAmount }

    /// Satırda gösterilecek başlık: satıcı, yoksa kategori, yoksa tür.
    public var displayTitle: String? {
        merchant ?? category?.name
    }

    public var entry: LedgerEntry {
        LedgerEntry(id: id, date: date, amount: amount, kind: kind, status: status,
                    accountID: account?.id, toAccountID: toAccount?.id,
                    categoryID: category?.id, merchant: merchant, sharedAmount: sharedAmount)
    }

    /// Bölünen giderde başkalarının payı (specs/10 §4).
    public var sharedAmount: Decimal {
        get { sharedRaw.flatMap { Decimal(canonical: $0) } ?? 0 }
        set { sharedRaw = newValue > 0 ? newValue.canonicalString : nil }
    }

    /// Düzenleme formu için taslak.
    public var draft: TransactionDraft {
        TransactionDraft(kind: kind, amount: amount.amount, date: date,
                         account: account?.ref, toAccount: toAccount?.ref, category: category?.ref,
                         merchant: merchant ?? "", note: note)
    }
}

extension MerchantMemory {
    var rule: MerchantRule? {
        guard let category else { return nil }
        return MerchantRule(key: key, displayName: displayName, categoryID: category.id,
                            lastUsed: lastUsed, useCount: useCount)
    }
}
