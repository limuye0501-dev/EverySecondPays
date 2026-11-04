import SwiftUI

/// Mechanical rolling counter — each digit wheel rolls independently.
struct Odometer: View {
    var value: Double
    var symbol: String
    var body: some View {
        let str = String(format: "%.2f", value)
        HStack(spacing: 2) {
            Text(symbol).font(.system(size: 30, weight: .semibold, design: .serif)).embossed().padding(.trailing, 4)
            ForEach(Array(str.enumerated()), id: \.offset) { i, ch in
                if let d = ch.wholeNumberValue { DigitWheel(digit: d) }
                else { Text(String(ch)).font(.system(size: 34, weight: .bold, design: .serif)).embossed() }
            }
        }
        .monospacedDigit()
        .accessibilityElement().accessibilityLabel(Text(symbol + str))
    }
}

struct DigitWheel: View {
    var digit: Int
    private let h: CGFloat = 46
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<10) { n in
                Text("\(n)").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(Palette.cream).frame(height: h)
            }
        }
        .offset(y: -CGFloat(digit) * h + 4.5 * h)
        .frame(width: 28, height: h).clipped()
        .background(LinearGradient(colors: [.black, Color(hex: 0x1A1A1A), .black], startPoint: .top, endPoint: .bottom))
        .overlay(LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: digit)
    }
}
