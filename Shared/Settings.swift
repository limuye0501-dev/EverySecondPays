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
    var skin: String = PiggySkin.glass.rawValue
    // Pro: custom extras
    var overtimeMultiplier: Double = 1.5          // pay rate after end time
    var countOvertime: Bool = false
    var overtimeEndMinutes: Int = 21 * 60
    var yearEndBonusMonths: Double = 0            // e.g. 1 = 13th-month salary, spread over the year
    var installDate: Date = Calendar.current.startOfDay(for: .now)

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
    var monthlyIncome: Double { s.monthlySalary * (1 + s.yearEndBonusMonths / 12) }
    var perSecond: Double { dailyWorkSeconds > 0 ? monthlyIncome / workDaysPerMonth / dailyWorkSeconds : 0 }
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
    func overtimeSeconds(on d: Date) -> Double {
        guard s.countOvertime, isWorkDay(d) else { return 0 }
        let a = end(of: d), b = min(cal.startOfDay(for: d).addingTimeInterval(Double(s.overtimeEndMinutes) * 60), d)
        return max(0, b.timeIntervalSince(a))
    }
    func isOvertime(_ now: Date = .now) -> Bool {
        s.countOvertime && isWorkDay(now) && now >= end(of: now) && now < cal.startOfDay(for: now).addingTimeInterval(Double(s.overtimeEndMinutes) * 60)
    }
    func earned(on d: Date) -> Double { workedSeconds(on: d) * perSecond + overtimeSeconds(on: d) * perSecond * s.overtimeMultiplier }
    func earnedToday(_ now: Date = .now) -> Double { earned(on: now) }
    /// Sum from `from` (start of day) through `now`, using the current settings. Days before install are excluded.
    func total(since from: Date, now: Date = .now) -> Double {
        var d = max(cal.startOfDay(for: from), cal.startOfDay(for: s.installDate)); var sum = 0.0
        let today = cal.startOfDay(for: now)
        while d < today { sum += earned(on: d.addingTimeInterval(86_399)); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return sum + earned(on: now)
    }
    func monthTotal(_ now: Date = .now) -> Double { total(since: cal.dateInterval(of: .month, for: now)!.start, now: now) }
    func yearTotal(_ now: Date = .now) -> Double { total(since: cal.dateInterval(of: .year, for: now)!.start, now: now) }
    func isEarning(_ now: Date = .now) -> Bool {
        if isOvertime(now) { return true }
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

enum PiggySkin: String, CaseIterable, Codable, Identifiable {
    case glass, gold, ceramic, crystal, ingot
    var id: String { rawValue }
    var titleKey: String { "skin.\(rawValue)" }
    func image(fill: Double) -> String {
        let n = fill > 0.25 ? "half" : "empty"
        return self == .glass ? "pig_\(n)" : "pig_\(rawValue)_\(n)"
    }
    var needsPro: Bool { self == .gold || self == .ceramic || self == .crystal }
    var needsTip: Bool { self == .ingot }
}

/// Purchase state mirrored to the App Group so widgets / Live Activity can read it.
enum Entitlements {
    static var isPro: Bool {
        get { AppGroup.defaults.bool(forKey: "ent.pro") }
        set { AppGroup.defaults.set(newValue, forKey: "ent.pro") }
    }
    static var hasTipped: Bool {
        get { AppGroup.defaults.bool(forKey: "ent.tipped") }
        set { AppGroup.defaults.set(newValue, forKey: "ent.tipped") }
    }
    static func allows(sound: String) -> Bool { isPro || sound == SoundOption.pennySlot.rawValue }
    static func allows(skin: PiggySkin) -> Bool { skin.needsTip ? hasTipped : (!skin.needsPro || isPro) }
}
