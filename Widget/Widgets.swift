import WidgetKit
import SwiftUI
import ActivityKit

struct Entry: TimelineEntry {
    let date: Date
    let s: WorkSettings
}

enum WidgetPalette {
    static let gold = Color(red: 0.95, green: 0.84, blue: 0.56)
    static let cream = Color(red: 0.984, green: 0.953, blue: 0.882)
    static let bgTop = Color(red: 0.29, green: 0.17, blue: 0.10)
    static let bgBottom = Color(red: 0.18, green: 0.10, blue: 0.06)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        let s = WorkSettings.example()
        return Entry(date: WorkSettings.representativeWorkDate(for: s), s: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let s = WorkSettings.forWidget()
        let date = context.isPreview ? WorkSettings.representativeWorkDate(for: s) : Date()
        completion(Entry(date: date, s: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = WorkSettings.forWidget()
        let now = Date()
        let plan = WidgetTimelinePlan.dates(for: s, now: now)
        let entries = plan.dates.map { Entry(date: $0, s: s) }
        completion(Timeline(entries: entries, policy: .after(plan.reload)))
    }
}

/// Second-by-second entries while earning (so the amount ticks), then minute steps.
/// Off the clock, one entry per schedule boundary keeps today's total on screen.
enum WidgetTimelinePlan {
    static func dates(for settings: WorkSettings, now: Date) -> (dates: [Date], reload: Date) {
        let earnings = Earnings(s: settings)
        var dates: [Date] = [now]
        if earnings.isEarning(now) {
            let fineUntil = now.addingTimeInterval(5 * 60)
            var t = now.addingTimeInterval(1)
            while t < fineUntil {
                dates.append(t)
                t = t.addingTimeInterval(1)
            }
            let coarseUntil = now.addingTimeInterval(3 * 60 * 60)
            var m = fineUntil
            while m < coarseUntil {
                dates.append(m)
                m = m.addingTimeInterval(60)
            }
            dates.append(contentsOf: earnings.scheduleMarks(after: now, days: 2).filter { $0 < coarseUntil.addingTimeInterval(60) })
        } else {
            dates.append(contentsOf: earnings.scheduleMarks(after: now, days: 3))
        }
        let unique = Array(Set(dates)).sorted()
        let capped = unique.count > 520 ? Array(unique.prefix(520)) : unique
        let last = capped.last ?? now.addingTimeInterval(15 * 60)
        let reload = max(last.addingTimeInterval(1), now.addingTimeInterval(60))
        return (capped.isEmpty ? [now] : capped, reload)
    }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var earnings: Earnings { Earnings(s: entry.s) }
    private var phase: WorkPhase { earnings.phase(at: entry.date) }
    private var amount: String { earnings.earnedToday(entry.date).money(entry.s.currencySymbol) }
    private var month: String { earnings.monthTotal(entry.date).money(entry.s.currencySymbol) }
    private var perSecond: String { earnings.perSecond.money(entry.s.currencySymbol, digits: 4) }
    private var perDay: String { earnings.perDay.money(entry.s.currencySymbol) }
    private var fill: Double { earnings.fill(entry.date) }
    private var piggy: String {
        let skin = PiggySkin(rawValue: entry.s.skin) ?? .glass
        let allowed = Entitlements.allows(skin: skin) ? skin : .glass
        return allowed.image(fill: fill)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemSmall: small
            case .systemMedium: medium
            case .systemExtraLarge: extraLarge.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            default: large.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(AppLink.salary)
        .accessibilityElement(children: .combine)
    }

    private var padding: CGFloat {
        switch family {
        case .systemSmall: return 8
        case .systemMedium: return 10
        case .systemLarge, .systemExtraLarge: return 14
        case .accessoryRectangular: return 2
        default: return 0
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    if entry.s.showsExampleSalary { exampleBadge }
                    Text("main.today").font(.system(size: 10)).foregroundStyle(WidgetPalette.cream.opacity(0.78)).lineLimit(1)
                }
                Spacer(minLength: 0)
                piggyImage(26)
            }
            moneyText(amount, size: 20)
            progress
            status(compact: true).font(.system(size: 10))
            if entry.s.showsExampleSalary {
                Text("widget.tapToSet").font(.system(size: 10, weight: .medium)).foregroundStyle(WidgetPalette.gold)
                    .lineLimit(2).minimumScaleFactor(0.65)
            } else if earnings.monthTotal(entry.date) >= 0.01 || earnings.earnedToday(entry.date) >= 0.01 {
                statLine("widget.month", month)
            } else {
                statLine("main.perDay", perDay)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 10) {
            piggyImage(96)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("main.today").font(.caption2).foregroundStyle(WidgetPalette.cream.opacity(0.78))
                    if entry.s.showsExampleSalary { exampleBadge }
                }
                moneyText(amount, size: 28)
                progress
                status(compact: false).font(.caption2)
                HStack(spacing: 10) {
                    statLine("widget.month", month)
                    statLine("main.perSecond", perSecond)
                }
                if entry.s.showsExampleSalary { tapHint }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("app.name").font(.headline).foregroundStyle(WidgetPalette.cream)
                Spacer()
                if entry.s.showsExampleSalary { exampleBadge }
            }
            HStack(alignment: .center, spacing: 12) {
                piggyImage(118)
                VStack(alignment: .leading, spacing: 4) {
                    Text("main.today").font(.caption).foregroundStyle(WidgetPalette.cream.opacity(0.78))
                    moneyText(amount, size: 34)
                    progress
                    status(compact: false).font(.caption)
                }
            }
            HStack(spacing: 8) {
                metric("widget.month", month)
                metric("main.perSecond", perSecond)
                metric("main.perDay", perDay)
            }
            if entry.s.showsExampleSalary { tapHint }
        }
    }

    private var extraLarge: some View {
        HStack(alignment: .center, spacing: 16) {
            piggyImage(200)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("app.name").font(.title3.weight(.semibold)).foregroundStyle(WidgetPalette.cream)
                    if entry.s.showsExampleSalary { exampleBadge }
                    Spacer()
                }
                Text("main.today").font(.caption).foregroundStyle(WidgetPalette.cream.opacity(0.78))
                moneyText(amount, size: 42)
                progress
                status(compact: false).font(.callout)
                HStack(spacing: 12) {
                    metric("widget.month", month)
                    metric("main.perSecond", perSecond)
                    metric("main.perDay", perDay)
                }
                if entry.s.showsExampleSalary { tapHint }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("main.today").font(.caption2)
                if entry.s.showsExampleSalary { Text("widget.example").font(.caption2.weight(.bold)) }
            }
            Text(amount).font(.headline.monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1).widgetAccentable()
            status(compact: true).font(.caption2)
            statLine("widget.month", month).font(.caption2)
        }
        .foregroundStyle(.primary)
    }

    private var circular: some View {
        Gauge(value: min(1, max(0, fill))) {
            EmptyView()
        } currentValueLabel: {
            circularLabel
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    @ViewBuilder private var circularLabel: some View {
        switch phase {
        case .beforeShift(let starts) where entry.date < starts:
            Text(timerInterval: entry.date...starts, countsDown: true)
                .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
        case .dayOff:
            Text(gaugeText(earnings.monthTotal(entry.date)))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
        default:
            Text(gaugeText(earnings.earnedToday(entry.date)))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
        }
    }

    private var inline: some View {
        HStack(spacing: 4) {
            if entry.s.showsExampleSalary { Text("widget.example") }
            Text("main.today")
            Text(amount).monospacedDigit().widgetAccentable()
            status(compact: true)
        }
        .font(.caption2)
    }

    /// Compact center label for the circular Lock Screen widget.
    private func gaugeText(_ value: Double) -> String {
        let sym = entry.s.currencySymbol
        let v = abs(value)
        if v >= 1000 {
            let n = v / 1000
            return sym + (n >= 10 ? String(format: "%.0fk", n) : String(format: "%.1fk", n))
        }
        return value.compactMoney(sym)
    }

    private func piggyImage(_ side: CGFloat) -> some View {
        Image(piggy)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous).stroke(WidgetPalette.gold.opacity(0.45), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func moneyText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .serif))
            .monospacedDigit()
            .foregroundStyle(WidgetPalette.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .contentTransition(.numericText())
            .widgetAccentable()
    }

    private var progress: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(WidgetPalette.gold)
                            .frame(width: geo.size.width * min(1, max(0, fill)))
                    }
                }
                .frame(height: 6)
                .clipped()
            Text(fill, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.cream.opacity(0.85))
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 14)
    }

    @ViewBuilder private func status(compact: Bool) -> some View {
        let style = compact ? Font.caption2 : Font.caption
        Group {
            switch phase {
            case .earning(let until):
                countdown("widget.offIn", until: until)
            case .lunch(let until):
                countdown("widget.lunch", until: until)
            case .beforeShift(let starts):
                countdown("widget.startsAt", until: starts)
            case .afterShift(let next):
                labeledNext("widget.done", next: next, compact: compact)
            case .dayOff(let next):
                labeledNext("widget.dayOff", next: next, compact: compact)
            }
        }
        .font(style)
        .foregroundStyle(onHomeScreen ? AnyShapeStyle(WidgetPalette.cream.opacity(0.9)) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var onHomeScreen: Bool {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular: return false
        default: return true
        }
    }

    private func countdown(_ key: LocalizedStringKey, until end: Date) -> some View {
        HStack(spacing: 3) {
            Text(key)
            if entry.date < end {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .monospacedDigit()
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder private func labeledNext(_ key: LocalizedStringKey, next: Date?, compact: Bool) -> some View {
        if let next, !compact {
            HStack(spacing: 3) {
                Text(key)
                Text("widget.nextShift")
                Text(next, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .monospacedDigit()
            }
        } else {
            Text(key)
        }
    }

    private var exampleBadge: some View {
        Text("widget.example")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(WidgetPalette.gold.opacity(0.22)))
            .foregroundStyle(WidgetPalette.gold)
    }

    private var tapHint: some View {
        Text("widget.tapToSet")
            .font(.caption2.weight(.medium))
            .foregroundStyle(WidgetPalette.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func statLine(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(key).foregroundStyle(onHomeScreen ? AnyShapeStyle(WidgetPalette.cream.opacity(0.7)) : AnyShapeStyle(.secondary))
            Text(value).monospacedDigit().foregroundStyle(onHomeScreen ? AnyShapeStyle(WidgetPalette.cream) : AnyShapeStyle(.primary)).widgetAccentable()
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func metric(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key).font(.system(size: 10)).foregroundStyle(WidgetPalette.cream.opacity(0.65))
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(WidgetPalette.gold)
                .lineLimit(1).minimumScaleFactor(0.5).widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.28)))
    }
}

struct WidgetChrome: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            AccessoryWidgetBackground()
        default:
            LinearGradient(colors: [WidgetPalette.bgTop, WidgetPalette.bgBottom], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct EarningsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EarningsWidget", provider: Provider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetChrome() }
        }
        .configurationDisplayName(Text("app.name"))
        .description(Text("widget.description"))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

struct TickingAmount: View {
    let state: EarningsAttributes.ContentState
    let symbol: String
    var font: Font = .title2.bold()

    var body: some View {
        TimelineView(.periodic(from: state.baseDate, by: 1)) { ctx in
            let cap = max(0, state.endDate.timeIntervalSince(state.baseDate))
            let elapsed = min(cap, max(0, ctx.date.timeIntervalSince(state.baseDate)))
            Text((state.baseAmount + state.perSecond * elapsed).money(symbol))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .contentTransition(.numericText())
        }
    }
}

struct EarningsActivityBanner: View {
    let symbol: String
    let state: EarningsAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image("pig_half").resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("main.today").font(.caption2).foregroundStyle(WidgetPalette.cream.opacity(0.75))
                TickingAmount(state: state, symbol: symbol, font: .title2.bold())
                activityStatus.font(.caption2).foregroundStyle(WidgetPalette.cream.opacity(0.9))
            }
            Spacer(minLength: 4)
            activityStatusBlock
        }
        .padding(.horizontal, 4)
        .widgetURL(AppLink.salary)
    }

    @ViewBuilder private var activityStatus: some View {
        if state.perSecond > 0, Date() < state.endDate {
            Text("widget.offIn")
        } else if state.perSecond > 0 {
            Text("main.overtime")
        } else {
            Text("widget.done")
        }
    }

    @ViewBuilder private var activityStatusBlock: some View {
        if state.perSecond > 0, Date() < state.endDate {
            VStack(alignment: .trailing, spacing: 2) {
                Text("widget.offIn").font(.caption2).foregroundStyle(WidgetPalette.cream.opacity(0.75))
                Text(timerInterval: Date()...state.endDate, countsDown: true)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WidgetPalette.cream)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        } else {
            Group {
                if state.perSecond > 0 { Text("main.overtime") } else { Text("widget.done") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetPalette.cream)
            .multilineTextAlignment(.trailing)
        }
    }
}

struct EarningsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarningsAttributes.self) { ctx in
            EarningsActivityBanner(symbol: ctx.attributes.currencySymbol, state: ctx.state)
                .padding()
                .activityBackgroundTint(WidgetPalette.bgBottom)
                .activitySystemActionForegroundColor(WidgetPalette.gold)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("pig_half").resizable().scaledToFit().frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TickingAmount(state: ctx.state, symbol: ctx.attributes.currencySymbol, font: .title3.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("main.today").font(.caption2)
                        Spacer()
                        if ctx.state.perSecond > 0, Date() < ctx.state.endDate {
                            Text("widget.offIn")
                            Text(timerInterval: Date()...ctx.state.endDate, countsDown: true).monospacedDigit()
                        } else {
                            if ctx.state.perSecond > 0 { Text("main.overtime") } else { Text("widget.done") }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.cream)
                }
            } compactLeading: {
                Image("pig_half").resizable().scaledToFill().frame(width: 18, height: 18).clipShape(Circle())
            } compactTrailing: {
                TickingAmount(state: ctx.state, symbol: ctx.attributes.currencySymbol, font: .caption.bold())
            } minimal: {
                TickingAmount(state: ctx.state, symbol: ctx.attributes.currencySymbol, font: .system(size: 9, weight: .bold))
            }
            .widgetURL(AppLink.salary)
        }
    }
}

@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget { EarningsWidget(); EarningsLiveActivity() }
}

enum WidgetSamples {
    static func clock(_ hour: Int, _ minute: Int, on base: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    static var afternoon: Date { WorkSettings.representativeWorkDate(for: WorkSettings.example()) }

    static var exampleEarning: Entry {
        let s = WorkSettings.example()
        return Entry(date: WorkSettings.representativeWorkDate(for: s), s: s)
    }

    static var configuredEarning: Entry {
        var s = WorkSettings.example()
        s.onboarded = true
        s.monthlySalary = 20_000
        s.currencySymbol = "¥"
        return Entry(date: WorkSettings.representativeWorkDate(for: s), s: s)
    }

    static var beforeShift: Entry {
        var s = WorkSettings.example()
        s.onboarded = true
        s.currencySymbol = "¥"
        return Entry(date: clock(7, 40, on: afternoon), s: s)
    }

    static var lunch: Entry {
        var s = WorkSettings.example()
        s.onboarded = true
        s.currencySymbol = "¥"
        return Entry(date: clock(12, 30, on: afternoon), s: s)
    }

    static var afterShift: Entry {
        var s = WorkSettings.example()
        s.onboarded = true
        s.currencySymbol = "¥"
        return Entry(date: clock(19, 10, on: afternoon), s: s)
    }

    static var dayOff: Entry {
        var s = WorkSettings.example()
        s.onboarded = true
        s.currencySymbol = "¥"
        let cal = Calendar.current
        var day = cal.startOfDay(for: afternoon)
        for _ in 0..<8 {
            if cal.component(.weekday, from: day) == 7 { break }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return Entry(date: clock(11, 0, on: day), s: s)
    }

}

#Preview("Small", as: .systemSmall) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.beforeShift
    WidgetSamples.lunch
    WidgetSamples.afterShift
    WidgetSamples.dayOff
}

#Preview("Medium", as: .systemMedium) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.beforeShift
    WidgetSamples.lunch
    WidgetSamples.afterShift
    WidgetSamples.dayOff
}

#Preview("Large", as: .systemLarge) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.beforeShift
    WidgetSamples.lunch
    WidgetSamples.afterShift
    WidgetSamples.dayOff
}

#Preview("iPad Extra Large", as: .systemExtraLarge) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.afterShift
    WidgetSamples.dayOff
}

#Preview("Lock Rectangular", as: .accessoryRectangular) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.beforeShift
    WidgetSamples.dayOff
}

#Preview("Lock Circular", as: .accessoryCircular) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.beforeShift
    WidgetSamples.dayOff
}

#Preview("Lock Inline", as: .accessoryInline) {
    EarningsWidget()
} timeline: {
    WidgetSamples.exampleEarning
    WidgetSamples.configuredEarning
    WidgetSamples.afterShift
    WidgetSamples.dayOff
}

#Preview("Live Activity") {
    EarningsActivityBanner(
        symbol: "¥",
        state: EarningsAttributes.ContentState(
            baseAmount: 317.28,
            baseDate: .now,
            perSecond: 0.016,
            endDate: .now.addingTimeInterval(2.5 * 3600)
        )
    )
    .padding()
    .background(WidgetPalette.bgBottom)
}
