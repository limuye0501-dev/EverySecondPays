import SwiftUI

@main
struct EverySecondPaysApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.settings.onboarded { MainView() } else { OnboardingView() }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
    }
}
