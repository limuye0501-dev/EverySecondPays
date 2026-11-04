import SwiftUI

/// Rendered with ImageRenderer and shared via ShareLink. Watermark for free users.
struct ShareCardView: View {
    var amount: Double
    var symbol: String
    var skin: PiggySkin
    var fill: Double
    var watermark: Bool
    var body: some View {
        ZStack {
            WalnutBackground()
            VStack(spacing: 18) {
                Text("share.headline").font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(Palette.cream)
                Image(skin.image(fill: fill)).resizable().scaledToFit().frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                BrassPlate { Odometer(value: amount, symbol: symbol) }
                Text(Date.now, format: .dateTime.year().month().day()).font(.footnote).foregroundStyle(Palette.cream.opacity(0.7))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if watermark {
                Label("app.name", systemImage: "bitcoinsign.circle.fill").font(.caption.bold())
                    .foregroundStyle(Palette.cream.opacity(0.85)).padding(10)
                    .background(Capsule().fill(.black.opacity(0.35))).padding(14)
            }
        }
        .frame(width: 390, height: 600)
    }
}

struct ShareButton: View {
    @EnvironmentObject var store: Store
    @ObservedObject var iap = StoreManager.shared
    var body: some View {
        let e = store.earnings, s = store.settings
        let card = ShareCardView(amount: e.earnedToday(), symbol: s.currencySymbol, skin: PiggySkin(rawValue: s.skin) ?? .glass,
                                 fill: e.fill(), watermark: !iap.isPro)
        let r = ImageRenderer(content: card); let _ = (r.scale = 3)
        if let ui = r.uiImage {
            let img = Image(uiImage: ui)
            ShareLink(item: img, preview: SharePreview(Text("app.name"), image: img)) {
                Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(Palette.brass)
            }
            .accessibilityLabel(Text("share.title"))
        }
    }
}
