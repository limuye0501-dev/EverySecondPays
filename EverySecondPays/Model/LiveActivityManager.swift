import ActivityKit
import Foundation

enum LiveActivityManager {
    static func startOrUpdate(_ e: Earnings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let state = EarningsAttributes.ContentState(baseAmount: e.earnedToday(now), baseDate: now,
                                                    perSecond: e.isEarning(now) ? e.perSecond : 0, endDate: e.end(of: now))
        let content = ActivityContent(state: state, staleDate: e.end(of: now))
        Task {
            if let a = Activity<EarningsAttributes>.activities.first { await a.update(content); return }
            guard e.isEarning(now) else { return }
            _ = try? Activity.request(attributes: EarningsAttributes(currencySymbol: e.s.currencySymbol), content: content)
        }
    }
    static func endAll() {
        Task { for a in Activity<EarningsAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
