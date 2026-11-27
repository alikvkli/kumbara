import SwiftUI

extension AppSection {
    var title: LocalizedStringKey {
        switch self {
        case .summary: "Özet"
        case .ledger: "İşlemler"
        case .portfolio: "Birikim"
        case .budget: "Bütçe"
        }
    }

    @ViewBuilder
    var rootView: some View {
        switch self {
        case .summary: SummaryView()
        case .ledger: LedgerView()
        case .portfolio: PortfolioView()
        case .budget: BudgetView()
        }
    }
}
