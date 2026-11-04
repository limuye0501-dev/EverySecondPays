import WidgetKit
import SwiftUI
import ActivityKit

struct Entry: TimelineEntry { let date: Date; let s: WorkSettings }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, s: WorkSettings()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now, s: .load())) }
    /// Minute-granularity entries (WidgetKit can't redraw a money value every second);
    /// the live ticking element is Text(timerInterval:).
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = WorkSettings.load(), now = Date()
        let entries = (0..<60).map { Entry(date: now.addingTimeInterval(Double($0) * 60), s: s) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private extension Entry {
    var e: Earnings { Earnings(s: s) }
    var amount: String { e.earnedToday(date).money(s.currencySymbol) }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        let e = entry.e
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("main.today").font(.caption2)
                Text(entry.amount).font(.headline.monospacedDigit())
                if e.isEarning(entry.date) { Text(timerInterval: entry.date...e.end(of: entry.date), countsDown: true).font(.caption2) }
            }
        case .accessoryCircular:
            Gauge(value: e.fill(entry.date)) { Image(systemName: "dollarsign.circle") }.gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Text(entry.amount)
        case .systemMedium:
            HStack {
                Image(e.fill(entry.date) > 0.25 ? "pig_half" : "pig_empty").resizable().scaledToFit()
                info(e)
            }
        default:
            ZStack(alignment: .bottomLeading) {
                Image(e.fill(entry.date) > 0.25 ? "pig_half" : "pig_empty").resizable().scaledToFit().opacity(0.9)
                info(e)
            }
        }
    }
    func info(_ e: Earnings) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("main.today").font(.caption2).foregroundStyle(.secondary)
            Text(entry.amount).font(.system(.title3, design: .serif).bold().monospacedDigit()).foregroundStyle(Color(red: 0.95, green: 0.84, blue: 0.56))
            if e.isEarning(entry.date) {
                HStack(spacing: 2) { Text("widget.offIn"); Text(timerInterval: entry.date...e.end(of: entry.date), countsDown: true) }
                    .font(.caption2).foregroundStyle(.secondary)
            } else { Text("main.resting").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct EarningsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EarningsWidget", provider: Provider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [Color(red: 0.29, green: 0.17, blue: 0.10), Color(red: 0.18, green: 0.10, blue: 0.06)], startPoint: .top, endPoint: .bottom) }
        }
        .configurationDisplayName(Text("app.name"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct EarningsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarningsAttributes.self) { ctx in
            HStack {
                Image("pig_half").resizable().scaledToFit().frame(width: 56)
                VStack(alignment: .leading) {
                    Text("app.name").font(.caption).foregroundStyle(.secondary)
                    Text(ctx.state.baseAmount.money(ctx.attributes.currencySymbol)).font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Color(red: 0.95, green: 0.84, blue: 0.56))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("widget.offIn").font(.caption2)
                    Text(timerInterval: Date()...max(Date(), ctx.state.endDate), countsDown: true).font(.headline.monospacedDigit()).frame(width: 80)
                }
            }
            .padding().activityBackgroundTint(Color(red: 0.18, green: 0.10, blue: 0.06))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image("pig_half").resizable().scaledToFit() }
                DynamicIslandExpandedRegion(.center) {
                    Text(ctx.state.baseAmount.money(ctx.attributes.currencySymbol)).font(.title2.bold().monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Text("widget.offIn"); Text(timerInterval: Date()...max(Date(), ctx.state.endDate), countsDown: true) }.font(.caption)
                }
            } compactLeading: {
                Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.yellow)
            } compactTrailing: {
                Text(ctx.state.baseAmount.money(ctx.attributes.currencySymbol, digits: 0)).monospacedDigit()
            } minimal: { Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.yellow) }
        }
    }
}

@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget { EarningsWidget(); EarningsLiveActivity() }
}
