import SwiftUI

/// Glass piggy bank: baked images cross-faded by fill level, with a falling-coin overlay.
/// The landing sound, AHAP haptic and visual impact are fired together from the render loop
/// at the frame the coin actually reaches the slot.
struct PiggyView: View {
    var fill: Double              // 0…1
    var skin: PiggySkin = .glass
    var dropTrigger: Int          // increments once per second while earning
    @State private var coins: [FallingCoin] = []
    @State private var impacts = 0
    @State private var lastImpact = Date.distantPast
    @State private var lastFullness = 0.0
    @StateObject private var landing = LandingTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    static let fall: TimeInterval = 0.9
    static let landT = 0.92

    var body: some View {
        ZStack {
            pig
                .keyframeAnimator(initialValue: 1.0, trigger: impacts) { v, s in v.scaleEffect(x: 2 - s, y: s, anchor: .bottom) } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1.0 : 1 - 0.012 - 0.02 * lastFullness, duration: 0.06)
                        SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    }
                }
            if !reduceMotion { SpecularHighlight(skin: skin, fill: fill) }
            TimelineView(.animation(paused: coins.isEmpty)) { tl in
                Canvas { ctx, size in
                    let now = tl.date
                    let slot = CGPoint(x: size.width * 0.52, y: size.height * 0.24)
                    for c in coins {
                        let t = now.timeIntervalSince(c.start) / Self.fall
                        if t >= Self.landT { landing.land(c.id) }
                        guard t >= 0, t <= 1, !reduceMotion else { continue }
                        let y = -30 + (slot.y + 30) * pow(t, 2)       // gravity ease-in
                        let x = slot.x + c.dx * (1 - t)
                        let squash = t > Self.landT ? 0.75 : 1.0
                        let w: CGFloat = 30, h = w * (0.25 + 0.75 * abs(cos(t * .pi * 3 + c.phase))) * squash
                        let r = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                        ctx.opacity = t > 0.95 ? (1 - t) * 20 : 1
                        ctx.fill(Ellipse().path(in: r), with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE49A), Color(hex: 0xE9C46A), Color(hex: 0x9C7A2E)]), startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                        ctx.stroke(Ellipse().path(in: r.insetBy(dx: 3, dy: 3 * h / w)), with: .color(Color(hex: 0x8A6A24).opacity(0.7)), lineWidth: 1)
                    }
                    // Impact flash at the slot
                    let it = now.timeIntervalSince(lastImpact) / 0.45
                    if it >= 0, it < 1 {
                        ctx.opacity = 1
                        let rad = reduceMotion ? 18.0 : 10 + 34 * it
                        let rr = CGRect(x: slot.x - rad, y: slot.y - rad * 0.35, width: rad * 2, height: rad * 0.7)
                        ctx.stroke(Ellipse().path(in: rr), with: .color(Color(hex: 0xFFE49A).opacity((1 - it) * 0.8)), lineWidth: 2)
                        ctx.fill(Ellipse().path(in: rr.insetBy(dx: rad * 0.5, dy: rad * 0.17)), with: .color(.white.opacity((1 - it) * 0.35)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement().accessibilityLabel(Text("a11y.piggy \(Int(fill * 100))"))
        .onAppear { landing.onLand = { onLand() } }
        .onChange(of: dropTrigger) { _, _ in
            guard scenePhase == .active else { return }
            let now = Date()
            coins.removeAll { now.timeIntervalSince($0.start) > 1.2 }
            coins.append(FallingCoin(start: now, dx: .random(in: -14...14), phase: .random(in: 0...3)))
        }
    }

    private func onLand() {
        lastFullness = fill
        lastImpact = .now
        impacts &+= 1
        CoinSound.shared.coinLanded(fullness: fill)
    }

    private var pig: some View {
        ZStack {
            Image(skin.image(fill: 0)).resizable().scaledToFit()
            Image(skin.image(fill: 1)).resizable().scaledToFit().opacity(min(1, fill * 2))
            // Heaped coins above half — extra stacked coins rendered procedurally
            if fill > 0.5 { CoinHeap(amount: (fill - 0.5) * 2).allowsHitTesting(false) }
        }
    }
}

/// Fires exactly once per coin, from inside the Canvas render pass, hopping to the main queue.
final class LandingTracker: ObservableObject {
    var onLand: (() -> Void)?
    private var landed = Set<UUID>()
    func land(_ id: UUID) {
        guard !landed.contains(id) else { return }
        landed.insert(id)
        if landed.count > 64 { landed.removeAll(); landed.insert(id) }
        DispatchQueue.main.async { [weak self] in self?.onLand?() }
    }
}

struct FallingCoin { let id = UUID(); let start: Date; let dx: CGFloat; let phase: Double }

/// Soft glass specular that slides with device tilt (CoreMotion), masked to the piggy silhouette.
struct SpecularHighlight: View {
    var skin: PiggySkin
    var fill: Double
    @ObservedObject private var tilt = TiltManager.shared
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: w * 0.22))
                .frame(width: w * 0.5, height: w * 0.28)
                .rotationEffect(.degrees(-25))
                .position(x: w * (0.42 - 0.18 * tilt.tilt.width), y: g.size.height * (0.36 + 0.12 * tilt.tilt.height))
                .animation(.easeOut(duration: 0.25), value: tilt.tilt)
        }
        .blendMode(.screen)
        .mask { Image(skin.image(fill: fill)).resizable().scaledToFit() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { TiltManager.shared.start() }
        .onDisappear { TiltManager.shared.stop() }
    }
}

struct CoinHeap: View {
    var amount: Double
    var body: some View {
        GeometryReader { g in
            let n = Int(amount * 40)
            ForEach(0..<n, id: \.self) { i in
                let rx = sin(Double(i) * 12.9898) * 0.5, ry = cos(Double(i) * 78.233) * 0.5
                Ellipse().fill(LinearGradient(colors: [Color(hex: 0xFFE49A), Color(hex: 0x9C7A2E)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 9).opacity(0.85)
                    .position(x: g.size.width * (0.5 + rx * 0.45), y: g.size.height * (0.62 - amount * 0.18 + ry * 0.1))
            }
        }
        .blendMode(.screen).opacity(0.8)
    }
}
