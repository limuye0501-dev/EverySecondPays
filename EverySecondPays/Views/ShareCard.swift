import SwiftUI

/// Vertical 9:16 story card (1080×1920 @3x). Rendered with ImageRenderer and shared via ShareLink.
/// Watermark for free users.
struct ShareCardView: View {
    var amount: Double
    var symbol: String
    var skin: PiggySkin
    var fill: Double
    var watermark: Bool
    var body: some View {
        ZStack {
            WalnutBackground()
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                Text("share.headline").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.cream)
                BrassPlate {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(symbol).font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(String(format: "%.2f", amount)).font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                    }.embossed().lineLimit(1).minimumScaleFactor(0.4)
                }
                Image(skin.image(fill: fill)).resizable().scaledToFit().frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                Text(Date.now, format: .dateTime.year().month().day().weekday()).font(.system(.body, design: .rounded)).foregroundStyle(Palette.cream.opacity(0.75))
                Spacer(minLength: 0)
                Text("share.tagline").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Palette.cream.opacity(0.55))
                    .padding(.bottom, 36)
            }.padding(.horizontal, 24)
        }
        .overlay(alignment: .bottomTrailing) {
            if watermark {
                Label("app.name", systemImage: "bitcoinsign.circle.fill").font(.caption.bold())
                    .foregroundStyle(Palette.cream.opacity(0.85)).padding(10)
                    .background(Capsule().fill(.black.opacity(0.35))).padding(14)
            }
        }
        .frame(width: 360, height: 640)
        .environment(\.dynamicTypeSize, .large)     // fixed layout for the exported image
    }
}

struct ShareButton: View {
    @EnvironmentObject var store: Store
    @ObservedObject var iap = StoreManager.shared
    var body: some View {
        let e = store.earnings, s = store.settings
        let skin = PiggySkin(rawValue: s.skin).flatMap { Entitlements.allows(skin: $0) ? $0 : nil } ?? .glass
        let card = ShareCardView(amount: e.earnedToday(), symbol: s.currencySymbol, skin: skin, fill: e.fill(), watermark: !iap.isPro)
        let r = ImageRenderer(content: card); let _ = (r.scale = 3)
        if let ui = r.uiImage {
            let img = Image(uiImage: ui)
            ShareLink(item: img, preview: SharePreview(Text("share.headline"), image: img)) {
                Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(Palette.brass)
            }
            .accessibilityLabel(Text("share.title"))
        }
    }
}
