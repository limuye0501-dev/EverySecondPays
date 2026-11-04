import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let e = store.earnings, sym = store.settings.currencySymbol
        HStack(spacing: 14) {
            cell("history.month", e.monthTotal().money(sym))
            cell("history.year", e.yearTotal().money(sym))
        }
    }
    private func cell(_ k: LocalizedStringKey, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(Palette.cream.opacity(0.7))
            Text(v).font(.system(.callout, design: .serif).monospacedDigit().weight(.semibold)).foregroundStyle(Color(hex: 0xF2D690))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.28)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08))))
    }
}
