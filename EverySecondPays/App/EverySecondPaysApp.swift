import SwiftUI

@main
struct EverySecondPaysApp: App {
    @StateObject private var store = Store()
    init() { _ = StoreManager.shared }  // start Transaction.updates listener at launch
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
