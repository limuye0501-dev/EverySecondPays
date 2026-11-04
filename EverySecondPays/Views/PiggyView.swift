import SwiftUI

/// Glass piggy bank: baked images cross-faded by fill level, with a falling-coin overlay.
struct PiggyView: View {
    var fill: Double              // 0…1
    var dropTrigger: Int          // increments once per second while earning
    @State private var coins: [FallingCoin] = []

    var body: some View {
        ZStack {
            Image("pig_empty").resizable().scaledToFit()
            Image("pig_half").resizable().scaledToFit().opacity(min(1, fill * 2))
            // Heaped coins above half — extra stacked coins rendered procedurally
            if fill > 0.5 { CoinHeap(amount: (fill - 0.5) * 2).allowsHitTesting(false) }
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let now = tl.date
                    for c in coins {
                        let t = now.timeIntervalSince(c.start) / 0.9
                        guard t >= 0, t <= 1 else { continue }
                        let slot = CGPoint(x: size.width * 0.52, y: size.height * 0.24)
                        let y = -30 + (slot.y + 30) * pow(t, 2)       // gravity ease-in
                        let x = slot.x + c.dx * (1 - t)
                        let squash = t > 0.92 ? 0.75 : 1.0
                        let w: CGFloat = 30, h = w * (0.25 + 0.75 * abs(cos(t * .pi * 3 + c.phase))) * squash
                        let r = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                        ctx.opacity = t > 0.95 ? (1 - t) * 20 : 1
                        ctx.fill(Ellipse().path(in: r), with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE49A), Color(hex: 0xE9C46A), Color(hex: 0x9C7A2E)]), startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                        ctx.stroke(Ellipse().path(in: r.insetBy(dx: 3, dy: 3 * h / w)), with: .color(Color(hex: 0x8A6A24).opacity(0.7)), lineWidth: 1)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: dropTrigger) { _, _ in
            let now = Date()
            coins.removeAll { now.timeIntervalSince($0.start) > 1.2 }
            coins.append(FallingCoin(start: now, dx: .random(in: -14...14), phase: .random(in: 0...3)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { CoinSound.shared.coinLanded() }
        }
    }
}

struct FallingCoin { let start: Date; let dx: CGFloat; let phase: Double }

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
