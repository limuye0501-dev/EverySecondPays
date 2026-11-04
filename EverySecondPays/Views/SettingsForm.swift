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
            Stepper(value: $s.lunchBreakMinutes, in: 0...180, step: 15) {
                Text("settings.lunch \(s.lunchBreakMinutes)")
            }
        }
    }
    private func minutesBinding(_ kp: WritableKeyPath<WorkSettings, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(s[keyPath: kp]) * 60) },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); s[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Form {
                WorkFields(s: $store.settings)
                Section("settings.sound") {
                    Toggle("settings.mute", isOn: $store.settings.muted)
                    ForEach(SoundOption.allCases) { o in
                        Button {
                            store.settings.soundID = o.rawValue; CoinSound.shared.preview(o.rawValue)
                        } label: {
                            HStack { Text(LocalizedStringKey(o.titleKey)); Spacer()
                                if store.settings.soundID == o.rawValue { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0xE9C46A)) } }
                        }.foregroundStyle(.primary)
                    }
                    Picker("settings.frequency", selection: $store.settings.playEveryN) {
                        Text("settings.every1").tag(1); Text("settings.every5").tag(5); Text("settings.every10").tag(10); Text("settings.every60").tag(60)
                    }
                    HStack { Image(systemName: "speaker.fill"); Slider(value: $store.settings.volume, in: 0.05...0.8); Image(systemName: "speaker.wave.2.fill") }
                    Toggle("settings.haptics", isOn: $store.settings.haptics)
                }
                Section { Button("settings.liveActivity") { LiveActivityManager.startOrUpdate(store.earnings) } }
            }
            .navigationTitle(Text("settings.title"))
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
