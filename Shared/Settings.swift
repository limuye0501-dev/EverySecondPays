import Foundation

enum AppGroup {
    static let id = (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.limuye.everysecondpays"
    static let defaults = UserDefaults(suiteName: id) ?? .standard
    /// File mirror of the settings blob. WidgetKit on iPad sometimes gets an empty
    /// suite object even when the app-group container itself is readable.
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent("work.settings.v2.json")
    }
}

enum AppLink {
    static let salary = URL(string: "everysecondpays://salary")!
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

    /// No completed onboarding, or a salary that cannot earn. Widgets use `example()` then.
    var showsExampleSalary: Bool { !onboarded || monthlySalary <= 0 }

    static var suggestedCurrency: String {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if lang.hasPrefix("zh") { return "¥" }
        switch Locale.current.region?.identifier {
        case "GB": return "£"
        case "HK": return "HK$"
        case "DE", "FR", "ES", "IT", "NL", "IE", "PT", "AT", "BE", "FI": return "€"
        default: return "$"
        }
    }

    /// Labeled sample used when the reviewer (or a new install) has not entered a salary.
    /// Workdays stay Mon–Fri so weekends render the off-work state instead of a blank.
    static func example() -> WorkSettings {
        var w = WorkSettings()
        w.monthlySalary = 10_000
        w.workDays = [2, 3, 4, 5, 6]
        w.startMinutes = 9 * 60
        w.endMinutes = 18 * 60
        w.lunchBreakMinutes = 60
        w.currencySymbol = suggestedCurrency
        w.onboarded = false
        w.skin = PiggySkin.glass.rawValue
        w.countOvertime = false
        w.yearEndBonusMonths = 0
        let cal = Calendar.current
        w.installDate = cal.dateInterval(of: .month, for: .now)?.start ?? cal.startOfDay(for: .now)
        return w
    }

    /// Settings the widget should render. Never an empty model.
    static func forWidget() -> WorkSettings {
        let saved = load()
        return saved.showsExampleSalary ? example() : saved
    }

    /// A mid-afternoon moment inside working hours, so the widget gallery is never ¥0.
    static func representativeWorkDate(for settings: WorkSettings, around now: Date = .now) -> Date {
        let cal = Calendar.current
        let earnings = Earnings(s: settings)
        let start = cal.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  let at = cal.date(bySettingHour: 15, minute: 30, second: 0, of: day),
                  earnings.isEarning(at) else { continue }
            return at
        }
        return now
    }

    static func load() -> WorkSettings {
        func decode(_ data: Data) -> WorkSettings? { try? JSONDecoder().decode(WorkSettings.self, from: data) }
        let fromDefaults = AppGroup.defaults.data(forKey: key).flatMap(decode)
        let fromFile: WorkSettings? = {
            guard let url = AppGroup.fileURL, let data = try? Data(contentsOf: url) else { return nil }
            return decode(data)
        }()
        switch (fromDefaults, fromFile) {
        case let (d?, f?) where d.showsExampleSalary && !f.showsExampleSalary:
            return f
        case let (d?, _):
            return d
        case let (nil, f?):
            return f
        default:
            return WorkSettings()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: Self.key)
        guard let url = AppGroup.fileURL else { return }
        try? data.write(to: url, options: .atomic)
    }
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
    /// Today's work progress, 0…1. This does not change the piggy picture.
    /// The bank is always drawn half full; this value still drives the lock-screen gauge and the "day complete" paywall.
    func fill(_ now: Date = .now) -> Double { dailyWorkSeconds > 0 ? min(1, workedSeconds(on: now) / dailyWorkSeconds) : 0 }

    func phase(at now: Date) -> WorkPhase {
        if isOvertime(now) {
            let until = cal.startOfDay(for: now).addingTimeInterval(Double(s.overtimeEndMinutes) * 60)
            return .earning(until: until)
        }
        guard isWorkDay(now) else { return .dayOff(next: nextEarningStart(after: now)) }
        let shiftStart = start(of: now)
        let shiftEnd = end(of: now)
        if now < shiftStart { return .beforeShift(starts: shiftStart) }
        if s.lunchBreakMinutes > 0 {
            let lunchStart = cal.startOfDay(for: now).addingTimeInterval(Double(lunchStartMin) * 60)
            let lunchEnd = lunchStart.addingTimeInterval(Double(s.lunchBreakMinutes) * 60)
            if now >= lunchStart && now < lunchEnd { return .lunch(until: lunchEnd) }
        }
        if now < shiftEnd { return .earning(until: shiftEnd) }
        return .afterShift(next: nextEarningStart(after: now))
    }

    /// Next moment earning begins, within the coming week.
    func nextEarningStart(after now: Date) -> Date? {
        let startDay = cal.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: startDay), isWorkDay(day) else { continue }
            let shiftStart = start(of: day)
            if shiftStart > now { return shiftStart }
        }
        return nil
    }

    /// Shift, lunch, overtime and midnight boundaries after `now`, so a timeline can flip state without a reload.
    func scheduleMarks(after now: Date, days: Int = 3) -> [Date] {
        var marks: [Date] = []
        let startDay = cal.startOfDay(for: now)
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: startDay) else { continue }
            var points = [start(of: day), end(of: day)]
            if s.lunchBreakMinutes > 0 {
                let lunchStart = cal.startOfDay(for: day).addingTimeInterval(Double(lunchStartMin) * 60)
                points.append(lunchStart)
                points.append(lunchStart.addingTimeInterval(Double(s.lunchBreakMinutes) * 60))
            }
            if s.countOvertime {
                points.append(cal.startOfDay(for: day).addingTimeInterval(Double(s.overtimeEndMinutes) * 60))
            }
            if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) {
                points.append(midnight)
            }
            marks.append(contentsOf: points.filter { $0 > now })
        }
        return Array(Set(marks)).sorted()
    }
}

enum WorkPhase: Equatable {
    case earning(until: Date)
    case lunch(until: Date)
    case beforeShift(starts: Date)
    case afterShift(next: Date?)
    case dayOff(next: Date?)
}

extension Double {
    func money(_ sym: String, digits: Int = 2) -> String { sym + String(format: "%.\(digits)f", self) }
    /// Shorter form for the circular lock-screen widget.
    func compactMoney(_ sym: String) -> String {
        if abs(self) >= 100 { return sym + String(format: "%.0f", self) }
        return money(sym, digits: 2)
    }
}

enum PiggySkin: String, CaseIterable, Codable, Identifiable {
    case glass, gold, ceramic, crystal, ingot
    var id: String { rawValue }
    var titleKey: String { "skin.\(rawValue)" }
    /// Always the half-full photo. `fill` is accepted so existing call sites can pass
    /// today's progress, but the pile in the picture does not grow.
    func image(fill: Double) -> String {
        _ = fill
        return self == .glass ? "pig_half" : "pig_\(rawValue)_half"
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
