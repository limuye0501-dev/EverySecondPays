import SwiftUI
import WidgetKit

@MainActor
final class Store: ObservableObject {
    @Published var settings = WorkSettings.load() {
        didSet { settings.save(); WidgetCenter.shared.reloadAllTimelines(); CoinSound.shared.prepare(settings) }
    }
    /// Set when a widget deep link should open the salary screen.
    @Published var openSettingsRequest = false
    var earnings: Earnings { Earnings(s: settings) }
    init() {
        CoinSound.shared.prepare(settings)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
