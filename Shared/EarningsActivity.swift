#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct EarningsAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var baseAmount: Double      // earned at `baseDate`
        var baseDate: Date
        var perSecond: Double
        var endDate: Date
    }
    var currencySymbol: String
}
#endif
