import SwiftUI
import WidgetKit

@MainActor
final class Store: ObservableObject {
    @Published var settings = WorkSettings.load() {
        didSet { settings.save(); WidgetCenter.shared.reloadAllTimelines(); CoinSound.shared.prepare(settings) }
    }
    var earnings: Earnings { Earnings(s: settings) }
    init() { CoinSound.shared.prepare(settings) }
}
