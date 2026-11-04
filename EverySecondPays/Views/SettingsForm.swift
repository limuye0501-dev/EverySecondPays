import SwiftUI

/// Shared salary / schedule fields used by onboarding and settings.
struct WorkFields: View {
    @Binding var s: WorkSettings
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    var body: some View {
        Section("settings.salary") {
            HStack {
                Text(s.currencySymbol)
                TextField("settings.salary.placeholder", value: $s.monthlySalary, format: .number).keyboardType(.decimalPad)
            }
            Picker("settings.currency", selection: $s.currencySymbol) { ForEach(["¥", "$", "€", "£", "HK$"], id: \.self) { Text($0) } }
        }
        Section("settings.schedule") {
            HStack {
                ForEach(1...7, id: \.self) { d in
                    let on = s.workDays.contains(d)
                    Button(weekdaySymbols[d - 1]) { if on { s.workDays.remove(d) } else { s.workDays.insert(d) } }
                        .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color(hex: 0xE9C46A) : .gray.opacity(0.2)))
                        .foregroundStyle(on ? .black : .primary).buttonStyle(.plain)
                }
            }
            DatePicker("settings.start", selection: minutesBinding(\.startMinutes), displayedComponents: .hourAndMinute)
            DatePicker("settings.end", selection: minutesBinding(\.endMinutes), displayedComponents: .hourAndMinute)
        }
    }
    private func minutesBinding(_ kp: WritableKeyPath<WorkSettings, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(s[keyPath: kp]) * 60) },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); s[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
}

/// Pro-only: lunch, overtime, year-end bonus.
struct ProFields: View {
    @Binding var s: WorkSettings
    var isPro: Bool
    var onLocked: () -> Void
    var body: some View {
        Section {
            Group {
                Stepper(value: $s.lunchBreakMinutes, in: 0...180, step: 15) { Text("settings.lunch \(s.lunchBreakMinutes)") }
                Toggle("settings.overtime", isOn: $s.countOvertime)
                if s.countOvertime {
                    Stepper(value: $s.overtimeMultiplier, in: 1...3, step: 0.5) { Text("settings.overtime.rate \(String(format: "%.1f", s.overtimeMultiplier))") }
                    DatePicker("settings.overtime.end", selection: Binding(
                        get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(s.overtimeEndMinutes) * 60) },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); s.overtimeEndMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
                        displayedComponents: .hourAndMinute)
                }
                Stepper(value: $s.yearEndBonusMonths, in: 0...12, step: 0.5) { Text("settings.bonus \(String(format: "%.1f", s.yearEndBonusMonths))") }
            }
            .disabled(!isPro)
        } header: {
            HStack { Text("settings.advanced"); if !isPro { ProBadge() } }
        } footer: {
            if !isPro { Button("paywall.unlock", action: onLocked) }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @ObservedObject var iap = StoreManager.shared
    @State private var showPaywall = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Button { showPaywall = true } label: {
                    HStack { Image(systemName: iap.isPro ? "checkmark.seal.fill" : "crown.fill").foregroundStyle(Color(hex: 0xE9C46A))
                        Text(iap.isPro ? "paywall.owned" : "paywall.title"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }.foregroundStyle(.primary) }
                WorkFields(s: $store.settings)
                ProFields(s: $store.settings, isPro: iap.isPro) { showPaywall = true }
                Section("settings.skin") {
                    ForEach(PiggySkin.allCases) { k in
                        let ok = Entitlements.allows(skin: k)
                        Button { if ok { store.settings.skin = k.rawValue } else { showPaywall = true } } label: {
                            HStack {
                                Image(k.image(fill: 1)).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(LocalizedStringKey(k.titleKey))
                                Spacer()
                                if !ok { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                else if store.settings.skin == k.rawValue { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0xE9C46A)) }
                            }
                        }.foregroundStyle(.primary)
                    }
                }
                Section("settings.sound") {
                    Toggle("settings.mute", isOn: $store.settings.muted)
                    ForEach(SoundOption.allCases) { o in
                        let ok = Entitlements.allows(sound: o.rawValue)
                        Button {
                            CoinSound.shared.preview(o.rawValue)
                            if ok { store.settings.soundID = o.rawValue } else { showPaywall = true }
                        } label: {
                            HStack { Text(LocalizedStringKey(o.titleKey)); Spacer()
                                if !ok { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                if store.settings.soundID == o.rawValue { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0xE9C46A)) } }
                        }.foregroundStyle(.primary)
                    }
                    Picker("settings.frequency", selection: $store.settings.playEveryN) {
                        Text("settings.every1").tag(1); Text("settings.every5").tag(5); Text("settings.every10").tag(10); Text("settings.every60").tag(60)
                    }
                    HStack { Image(systemName: "speaker.fill"); Slider(value: $store.settings.volume, in: 0.05...0.8); Image(systemName: "speaker.wave.2.fill") }
                    Toggle("settings.haptics", isOn: $store.settings.haptics)
                }
                Section { Button { if iap.isPro { LiveActivityManager.startOrUpdate(store.earnings) } else { showPaywall = true } } label: {
                    HStack { Text("settings.liveActivity"); if !iap.isPro { Spacer(); ProBadge() } } } }
                Section("settings.about") {
                    Link("paywall.privacy", destination: PaywallView.privacy)
                    Link("paywall.terms", destination: PaywallView.terms)
                }
            }
            .navigationTitle(Text("settings.title"))
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .toolbar { Button("common.done") { dismiss() } }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @State private var draft = WorkSettings.load()
    var body: some View {
        NavigationStack {
            Form {
                Section { Image("pig_empty").resizable().scaledToFit().frame(height: 180).frame(maxWidth: .infinity) }
                    footer: { Text("onboarding.subtitle") }
                WorkFields(s: $draft)
                Section {
                    let p = Earnings(s: draft).perSecond
                    LabeledContent("main.perSecond", value: p.money(draft.currencySymbol, digits: 4))
                }
                Button("onboarding.start") { draft.onboarded = true; store.settings = draft }
                    .frame(maxWidth: .infinity).bold()
                    .disabled(draft.monthlySalary <= 0 || draft.workDays.isEmpty || draft.endMinutes <= draft.startMinutes)
            }
            .navigationTitle(Text("onboarding.title"))
        }
    }
}
