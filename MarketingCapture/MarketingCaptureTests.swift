import XCTest

/// Drives the salary screen and the share sheet for marketing recordings.
/// QuiescenceBypass.m keeps taps working while SpriteKit coins are in motion.
final class MarketingCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    func testMainEnglish() {
        holdMain(lang: "en", loc: "en_US", seconds: 50, name: "main-en")
    }

    func testMainChinese() {
        holdMain(lang: "zh-Hans", loc: "zh_CN", seconds: 42, name: "main-zh")
    }

    func testSettingsFlow() {
        let app = openDemo()
        let gear = app.buttons["Settings"]
        guard gear.waitForExistence(timeout: 20) else {
            logTree(app, "settings-no-gear")
            return
        }
        signal("settings-ready")
        pump(7, app: app)
        gear.tap()
        let titled = app.navigationBars["Settings"].buttons["Done"]
        let any = app.buttons["Done"]
        let open = titled.waitForExistence(timeout: 8) || any.waitForExistence(timeout: 2)
        signal(open ? "settings-open" : "settings-missing")
        pump(8, app: app)
        if titled.exists { titled.tap() }
        else if any.exists { any.tap() }
        else { logTree(app, "settings-no-done") }
        signal("settings-closed")
        pump(18, app: app)
        signal("settings-done")
    }

    func testShareCard() {
        let app = openDemo()
        let share = app.buttons["Share"]
        guard share.waitForExistence(timeout: 20) else {
            logTree(app, "share-no-button")
            return
        }
        signal("share-ready")
        pump(6, app: app)
        share.tap()
        signal("share-tapped")
        pump(14, app: app)
        signal("share-done")
    }

    /// Best-effort home-screen widget. Signals widget-visible only after the widget gallery's Add succeeds.
    func testHomeWidget() {
        let app = openDemo()
        guard app.buttons["Share"].waitForExistence(timeout: 20) else {
            signal("widget-skip")
            return
        }
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = sb.icons["Every Second Pays"]
        guard icon.waitForExistence(timeout: 8) else {
            signal("widget-skip")
            return
        }
        icon.press(forDuration: 1.3)
        // iOS 18+ puts Add Widget on the long-press menu. Older systems need Edit Home Screen, then +.
        let menuAdd = sb.buttons["Add Widget"].firstMatch
        let menuAddItem = sb.menuItems["Add Widget"].firstMatch
        let edit = sb.buttons["Edit Home Screen"].firstMatch
        if menuAdd.waitForExistence(timeout: 3) {
            menuAdd.tap()
        } else if menuAddItem.waitForExistence(timeout: 2) {
            menuAddItem.tap()
        } else if edit.waitForExistence(timeout: 2) {
            edit.tap()
            Thread.sleep(forTimeInterval: 1)
            let plus = sb.buttons["Add Widget"].firstMatch
            let plusMark = sb.buttons["+"].firstMatch
            if plus.waitForExistence(timeout: 3) { plus.tap() }
            else if plusMark.waitForExistence(timeout: 2) { plusMark.tap() }
            else { signal("widget-skip"); return }
        } else {
            signal("widget-skip")
            return
        }
        let search = sb.searchFields.firstMatch
        if search.waitForExistence(timeout: 6) {
            search.tap()
            search.typeText("Every Second")
        }
        Thread.sleep(forTimeInterval: 1.5)
        let row = sb.cells.containing(NSPredicate(format: "label CONTAINS[c] 'Every Second'")).firstMatch
        let text = sb.staticTexts["Every Second Pays"].firstMatch
        if row.waitForExistence(timeout: 5) { row.tap() }
        else if text.waitForExistence(timeout: 3) { text.tap() }
        else { signal("widget-skip"); return }
        Thread.sleep(forTimeInterval: 1)
        let add = sb.buttons["Add Widget"]
        guard add.waitForExistence(timeout: 5) else { signal("widget-skip"); return }
        add.tap()
        if sb.buttons["Done"].waitForExistence(timeout: 4) { sb.buttons["Done"].tap() }
        signal("widget-visible")
        pump(8, app: sb)
        signal("widget-done")
    }

    private func holdMain(lang: String, loc: String, seconds: TimeInterval, name: String) {
        let app = openDemo(lang: lang, loc: loc)
        // English label is Share; Simplified Chinese is 分享.
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if app.buttons["Share"].exists || app.buttons["分享"].exists { break }
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard app.buttons["Share"].exists || app.buttons["分享"].exists else {
            logTree(app, "\(name)-missing")
            return
        }
        signal("\(name)-ready")
        pump(seconds, app: app)
        signal("\(name)-done")
    }

    /// Asking for the hierarchy keeps the simulator painting. A plain sleep lets it
    /// drop to a fraction of a frame per second, and the falling coin disappears.
    private func pump(_ seconds: TimeInterval, app: XCUIApplication) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            _ = app.buttons.firstMatch.exists
            Thread.sleep(forTimeInterval: 0.03)
        }
    }

    @discardableResult
    private func openDemo(lang: String = "en", loc: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ESPDemo", "main", "-AppleLanguages", "(\(lang))", "-AppleLocale", loc]
        app.launch()
        dismissSystemAlerts()
        return app
    }

    private func dismissSystemAlerts() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = sb.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        for label in ["Allow", "OK", "Not Now", "Don't Allow", "Don’t Allow"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
    }

    private func signal(_ name: String) {
        NSLog("%@", "ESP_SIGNAL \(name)" as NSString)
        fputs("ESP_SIGNAL \(name)\n", stderr)
        fflush(stderr)
        let url = URL(fileURLWithPath: "/tmp/esp-signal-\(name)")
        try? Data("ok".utf8).write(to: url)
    }

    private func logTree(_ app: XCUIApplication, _ name: String) {
        let labels = app.buttons.allElementsBoundByIndex.prefix(30).map(\.label).joined(separator: " | ")
        NSLog("%@", "ESP_BUTTONS \(labels)" as NSString)
        signal(name)
    }
}
