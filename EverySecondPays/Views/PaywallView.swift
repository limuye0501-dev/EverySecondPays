import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var store = StoreManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://limuye0501-dev.github.io/everysecondpays-site/privacy.html")!

    var body: some View {
        ZStack {
            WalnutBackground()
            ScrollView {
                VStack(spacing: 20) {
                    HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Palette.cream.opacity(0.6)) }
                        .accessibilityLabel(Text("common.close")) }
                    Image("pig_gold_half").resizable().scaledToFit().frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.brass, lineWidth: 3))
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
                    BrassPlate { Text("paywall.title").font(.system(.title2, design: .serif).bold()).embossed() }

                    VStack(alignment: .leading, spacing: 12) {
                        feature("speaker.wave.2.fill", "paywall.f.sounds")
                        feature("rectangle.3.group.fill", "paywall.f.widgets")
                        feature("sparkles", "paywall.f.skins")
                        feature("clock.badge.checkmark", "paywall.f.custom")
                        feature("chart.bar.fill", "paywall.f.history")
                        feature("square.and.arrow.up", "paywall.f.share")
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(glassCard)

                    if store.isPro {
                        Label("paywall.owned", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Color(hex: 0xF2D690))
                    } else {
                        Button { if let p = store.pro { Task { await store.buy(p) } } } label: {
                            HStack {
                                if store.purchasing == ProductID.pro { ProgressView().tint(.black) }
                                Text("paywall.buy \(store.pro?.displayPrice ?? "…")").font(.headline)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Capsule().fill(Palette.brass).shadow(color: .black.opacity(0.5), radius: 6, y: 4))
                            .foregroundStyle(Color(hex: 0x3A2608))
                        }
                        .disabled(store.pro == nil || store.purchasing != nil)
                        Text("paywall.lifetime").font(.footnote).foregroundStyle(Palette.cream.opacity(0.7))
                    }

                    TipJar()

                    HStack(spacing: 18) {
                        Button("paywall.restore") { Task { await store.restore() } }
                        Link("paywall.terms", destination: Self.terms)
                        Link("paywall.privacy", destination: Self.privacy)
                    }
                    .font(.footnote).foregroundStyle(Palette.cream.opacity(0.8))
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 22)
            }
        }
        .alert(Text("store.error"), isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("common.done") {}
        } message: { Text(store.lastError ?? "") }
        .alert(Text("tip.thanks.title"), isPresented: $store.thankYou) { Button("common.done") {} } message: { Text("tip.thanks.body") }
        .task { if store.products.isEmpty { await store.load() } }
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
            .environment(\.colorScheme, .dark)
    }
    private func feature(_ icon: String, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Color(hex: 0xF2D690))
            Text(key).foregroundStyle(Palette.cream)
        }.font(.callout)
    }
}

struct TipJar: View {
    @ObservedObject var store = StoreManager.shared
    var body: some View {
        VStack(spacing: 10) {
            Text("tip.title").font(.system(.headline, design: .serif)).foregroundStyle(Color(hex: 0xF2D690))
            Text("tip.subtitle").font(.caption).foregroundStyle(Palette.cream.opacity(0.7)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                ForEach(store.tips) { p in
                    Button { Task { await store.buy(p) } } label: {
                        VStack(spacing: 4) {
                            Text(icon(p.id)).font(.title2)
                            Text(p.displayName).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                            Text(p.displayPrice).font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.3)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.brass, lineWidth: 1)))
                        .foregroundStyle(Palette.cream)
                    }.disabled(store.purchasing != nil)
                }
            }
        }
    }
    private func icon(_ id: String) -> String { id.hasSuffix("small") ? "🪙" : id.hasSuffix("medium") ? "💰" : "🧧" }
}

/// Small lock badge used on Pro-only rows.
struct ProBadge: View {
    var body: some View {
        Text("PRO").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Palette.brass)).foregroundStyle(Color(hex: 0x3A2608))
    }
}
