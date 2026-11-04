import SwiftUI

enum Palette {
    static let brass = LinearGradient(colors: [Color(hex: 0xF2D690), Color(hex: 0xE9C46A), Color(hex: 0x9C7A2E), Color(hex: 0xE9C46A)], startPoint: .top, endPoint: .bottom)
    static let cream = Color(hex: 0xFBF3E1)
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}

/// Procedural walnut desk: warm gradient + fine grain lines.
struct WalnutBackground: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x4A2C1A), Color(hex: 0x2E1A0F), Color(hex: 0x3B2213)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            var rng = SystemRandomNumberGenerator()
            for i in 0..<90 {
                var p = Path(); let y0 = CGFloat(i) / 90 * size.height
                p.move(to: CGPoint(x: 0, y: y0))
                let amp = CGFloat.random(in: 4...18, using: &rng)
                p.addCurve(to: CGPoint(x: size.width, y: y0 + .random(in: -10...10, using: &rng)),
                           control1: CGPoint(x: size.width * 0.3, y: y0 - amp), control2: CGPoint(x: size.width * 0.7, y: y0 + amp))
                ctx.stroke(p, with: .color(.black.opacity(.random(in: 0.05...0.18, using: &rng))), lineWidth: .random(in: 0.5...2, using: &rng))
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

/// Embossed brass plate.
struct BrassPlate<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.brass)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1).blendMode(.overlay))
                .shadow(color: .black.opacity(0.55), radius: 8, y: 5))
            .overlay(alignment: .topLeading) { Screw().padding(6) }
            .overlay(alignment: .topTrailing) { Screw().padding(6) }
    }
}
struct Screw: View {
    var body: some View {
        Circle().fill(RadialGradient(colors: [Color(hex: 0xFFF6D0), Color(hex: 0x8A6A24)], center: .topLeading, startRadius: 0, endRadius: 6))
            .frame(width: 7, height: 7).overlay(Rectangle().fill(.black.opacity(0.4)).frame(width: 5, height: 1).rotationEffect(.degrees(35)))
    }
}
extension View {
    /// Letterpress / embossed text.
    func embossed() -> some View {
        self.foregroundStyle(Color(hex: 0x3A2608))
            .shadow(color: .white.opacity(0.55), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: -0.5)
    }
}
