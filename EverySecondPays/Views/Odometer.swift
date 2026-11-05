import SwiftUI

/// Rolling money counter: SF Rounded, monospaced digits, numericText content transition, Dynamic Type.
struct Odometer: View {
    var value: Double
    var symbol: String
    var style: Font.TextStyle = .largeTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let str = String(format: "%.2f", value)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(symbol).font(.system(style, design: .rounded).weight(.semibold))
            Text(str)
                .font(.system(style, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
                .animation(.snappy(duration: 0.45), value: value)
        }
        .embossed()
        .lineLimit(1).minimumScaleFactor(0.5)
        .accessibilityElement().accessibilityLabel(Text(symbol + str))
    }
}
