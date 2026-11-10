import SwiftUI

@main
struct EverySecondPaysApp: App {
    @StateObject private var store = Store()
    init() {
        // App Store screenshot mode: -ESPDemo main|paywall|settings
        if let demo = UserDefaults.standard.string(forKey: "ESPDemo") {
            var w = WorkSettings(); w.onboarded = true; w.monthlySalary = 20000; w.workDays = Set(1...7)
            w.startMinutes = 0; w.endMinutes = 23 * 60 + 59; w.lunchBreakMinutes = 0; w.muted = true
            w.skin = demo == "settings" ? PiggySkin.glass.rawValue : PiggySkin.glass.rawValue
            w.currencySymbol = Locale.current.language.languageCode?.identifier == "zh" ? "¥" : "$"
            w.installDate = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
            w.save()
        }
        _ = StoreManager.shared
    }  // start Transaction.updates listener at launch
    var body: some Scene {
        WindowGroup {
            Group {
                if store.settings.onboarded { MainView() } else { OnboardingView() }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard url.scheme == "everysecondpays", store.settings.onboarded else { return }
                store.openSettingsRequest = true
            }
        }
    }
}
