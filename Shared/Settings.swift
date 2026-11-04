import Foundation

enum AppGroup {
    static let id = (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.limuye.everysecondpays"
    static let defaults = UserDefaults(suiteName: id) ?? .standard
}

struct WorkSettings: Codable, Equatable {
    var monthlySalary: Double = 10000
    var workDays: Set<Int> = [2, 3, 4, 5, 6]          // Calendar weekday: 1=Sun … 7=Sat
    var startMinutes: Int = 9 * 60
    var endMinutes: Int = 18 * 60
    var lunchBreakMinutes: Int = 60
    var currencySymbol: String = "¥"
    var soundID: String = SoundOption.pennySlot.rawValue
    var muted: Bool = false
    var playEveryN: Int = 1                           // 1 = every coin
    var volume: Float = 0.35
    var haptics: Bool = true
    var onboarded: Bool = false

    static let key = "work.settings.v2"
    static func load() -> WorkSettings {
        guard let d = AppGroup.defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(WorkSettings.self, from: d) else { return WorkSettings() }
        return s
    }
    func save() { AppGroup.defaults.set(try? JSONEncoder().encode(self), forKey: Self.key) }
}

enum SoundOption: String, CaseIterable, Codable, Identifiable {
    case emptyPig = "empty_pig", coinPile = "coin_pile", ceramicPig = "ceramic_pig", glassBowl = "glass_bowl", pennySlot = "penny_slot"
    var id: String { rawValue }
    var titleKey: String { "sound.\(rawValue)" }
}

/// Pure earnings math, shared by app, widgets and Live Activity.
struct Earnings {
    let s: WorkSettings
    var cal = Calendar.current

    var dailyWorkSeconds: Double { Double(max(0, s.endMinutes - s.startMinutes - s.lunchBreakMinutes)) * 60 }
    /// Average work days per month = days/week × 52/12
    var workDaysPerMonth: Double { Double(max(1, s.workDays.count)) * 52.0 / 12.0 }
    var perSecond: Double { dailyWorkSeconds > 0 ? s.monthlySalary / workDaysPerMonth / dailyWorkSeconds : 0 }
    var perDay: Double { perSecond * dailyWorkSeconds }

    func start(of d: Date) -> Date { cal.startOfDay(for: d).addingTimeInterval(Double(s.startMinutes) * 60) }
    func end(of d: Date) -> Date { cal.startOfDay(for: d).addingTimeInterval(Double(s.endMinutes) * 60) }
    func isWorkDay(_ d: Date) -> Bool { s.workDays.contains(cal.component(.weekday, from: d)) }

    /// Lunch break centred at 12:00–(12:00+lunch).
    private var lunchStartMin: Int { 12 * 60 }
    func workedSeconds(on d: Date) -> Double {
        guard isWorkDay(d) else { return 0 }
        let a = start(of: d), b = min(end(of: d), d)
        guard b > a else { return 0 }
        var secs = b.timeIntervalSince(a)
        let ls = cal.startOfDay(for: d).addingTimeInterval(Double(lunchStartMin) * 60)
        let le = ls.addingTimeInterval(Double(s.lunchBreakMinutes) * 60)
        let overlap = max(0, min(b, le).timeIntervalSince(max(a, ls)))
        secs -= overlap
        return max(0, secs)
    }
    func earnedToday(_ now: Date = .now) -> Double { workedSeconds(on: now) * perSecond }
    func isEarning(_ now: Date = .now) -> Bool {
        guard isWorkDay(now), now >= start(of: now), now < end(of: now) else { return false }
        let ls = cal.startOfDay(for: now).addingTimeInterval(Double(lunchStartMin) * 60)
        return !(now >= ls && now < ls.addingTimeInterval(Double(s.lunchBreakMinutes) * 60))
    }
    /// Fill 0…1 of the piggy bank (today's progress).
    func fill(_ now: Date = .now) -> Double { dailyWorkSeconds > 0 ? min(1, workedSeconds(on: now) / dailyWorkSeconds) : 0 }
}

extension Double {
    func money(_ sym: String, digits: Int = 2) -> String { sym + String(format: "%.\(digits)f", self) }
}
