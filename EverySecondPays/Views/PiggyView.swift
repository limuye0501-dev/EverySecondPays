import SwiftUI

/// Glass piggy bank. The picture is always the half-full photo.
/// Each earned second drops one coin through the slot. SpriteKit then runs gravity,
/// bounces, and collisions with the glass and the coins already inside, until the coin rests.
/// Rested coins fade away. They are not added to the pile, so the fill level never rises.
struct PiggyView: View {
    var fill: Double              // today's earnings progress, 0…1 — sound/haptics only, not the picture
    var skin: PiggySkin = .glass
    var dropTrigger: Int          // increments once per second while earning
    @StateObject private var bridge = PiggyBridge()
    @State private var impacts = 0
    @State private var lastFullness = 0.0
    @State private var lastCoin = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The photo is the bottom layer and does not depend on SpriteKit.
        // The coin view is transparent, so a paused or failed scene cannot cover the piggy with gray.
        Image(skin.image(fill: 1))
            .resizable()
            .scaledToFit()
            .overlay {
                if !reduceMotion { SpecularHighlight(skin: skin, fill: 1) }
            }
            .keyframeAnimator(initialValue: 1.0, trigger: impacts) { view, scale in
                view.scaleEffect(x: 2 - scale, y: scale, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(reduceMotion ? 1.0 : 1 - 0.012 - 0.02 * lastFullness, duration: 0.06)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                }
            }
            .overlay(alignment: .top) {
                // Taller than the photo and shifted up, so the coin can start above the piggy
                // without pushing the rest of the screen down. Not inside the spring scale.
                if !reduceMotion {
                    GeometryReader { g in
                        let tall = g.size.height * (1 + PiggyBankScene.sky)
                        TransparentCoinView(
                            scene: bridge.scene,
                            skin: skin,
                            running: bridge.simulating && scenePhase == .active
                        )
                        .frame(width: g.size.width, height: tall)
                        .offset(y: -g.size.height * PiggyBankScene.sky)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("a11y.piggy \(Int(fill * 100))"))
            .onAppear {
                bridge.fill = fill
                bridge.scene.apply(skin: skin)
            }
            .onChange(of: fill) { _, new in bridge.fill = new }
            .onChange(of: skin) { _, new in bridge.scene.apply(skin: new) }
            .onChange(of: reduceMotion) { _, on in
                guard on else { return }
                bridge.simulating = false
                bridge.scene.clearCoins()
            }
            .onChange(of: bridge.landToken) { _, _ in
                lastFullness = bridge.landFill
                impacts &+= 1
            }
            .onChange(of: dropTrigger) { _, _ in
                guard scenePhase == .active else { return }
                let now = Date()
                // One coin animation per second. Extra earnings ticks do not add coins.
                guard now.timeIntervalSince(lastCoin) >= PiggyBankScene.dropInterval else { return }
                lastCoin = now
                bridge.fill = fill
                if reduceMotion {
                    // No travel and no bounce. One clink at the moment the coin would have landed.
                    CoinSound.shared.coinLanded(fullness: fill)
                    return
                }
                bridge.simulating = true
                bridge.scene.drop()
            }
    }
}

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
