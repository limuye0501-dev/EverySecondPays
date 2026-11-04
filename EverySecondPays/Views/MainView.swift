import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var now = Date()
    @State private var tick = 0
    @State private var showSettings = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let e = store.earnings
        ZStack {
            WalnutBackground()
            VStack(spacing: 22) {
                HStack {
                    Text("app.name").font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Palette.cream)
                    Spacer()
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill").font(.title2).foregroundStyle(Palette.brass) }
                        .accessibilityLabel(Text("settings.title"))
                }.padding(.horizontal)

                BrassPlate {
                    VStack(spacing: 6) {
                        Text("main.today").font(.caption.weight(.semibold)).embossed()
                        Odometer(value: e.earnedToday(now), symbol: store.settings.currencySymbol)
                    }
                }

                PiggyView(fill: e.fill(now), dropTrigger: tick).frame(maxWidth: 360)

                HStack(spacing: 14) {
                    stat("main.perSecond", e.perSecond.money(store.settings.currencySymbol, digits: 4))
                    stat("main.perDay", e.perDay.money(store.settings.currencySymbol))
                }
                Text(e.isEarning(now) ? "main.earning" : "main.resting")
                    .font(.footnote).foregroundStyle(Palette.cream.opacity(0.7))
                Spacer(minLength: 0)
            }.padding(.top)
        }
        .onReceive(timer) { d in
            now = d
            if store.earnings.isEarning(d) { tick &+= 1 }
            if Int(d.timeIntervalSince1970) % 60 == 0 { LiveActivityManager.startOrUpdate(store.earnings) }
        }
        .onAppear { LiveActivityManager.startOrUpdate(e) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
    }

    private func stat(_ key: LocalizedStringKey, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(key).font(.caption2).foregroundStyle(Palette.cream.opacity(0.7))
            Text(v).font(.system(.callout, design: .serif).monospacedDigit().weight(.semibold)).foregroundStyle(Color(hex: 0xF2D690))
        }
        .padding(10).frame(maxWidth: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.28)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08))))
    }
}
