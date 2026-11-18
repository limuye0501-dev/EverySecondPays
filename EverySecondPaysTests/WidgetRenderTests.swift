import XCTest
import SwiftUI
import UIKit
import WidgetKit

/// Renders every widget family the way a fresh iPad/iPhone install and a configured salary look.
/// ImageRenderer output is saved under the test container's Documents/widget-snapshots.
final class WidgetRenderTests: XCTestCase {
    func testEmptyStoreUsesSampleAndTimelineTicks() {
        AppGroup.defaults.removeObject(forKey: WorkSettings.key)
        if let url = AppGroup.fileURL { try? FileManager.default.removeItem(at: url) }
        let loaded = WorkSettings.forWidget()
        XCTAssertTrue(loaded.showsExampleSalary)
        XCTAssertGreaterThan(loaded.monthlySalary, 0)
        let now = Date()
        let earnings = Earnings(s: loaded)
        XCTAssertGreaterThan(earnings.perSecond, 0)
        XCTAssertGreaterThan(earnings.earnedToday(now) + earnings.perHour, 0)
        let plan = WidgetTimelinePlan.dates(for: loaded, now: now)
        XCTAssertFalse(plan.dates.isEmpty)
        XCTAssertLessThanOrEqual(plan.dates.count, 160)
        XCTAssertLessThanOrEqual(plan.dates[0].timeIntervalSince(now), 1)
        if earnings.isEarning(now) {
            XCTAssertGreaterThan(plan.dates.count, 30)
            XCTAssertGreaterThan(earnings.earnedToday(now.addingTimeInterval(30)), earnings.earnedToday(now))
        }
    }

    func testRendersEveryFamilyFreshSalaryAndOffWork() throws {
        let fresh = Entry(date: .now, s: WorkSettings.example())
        let office = WidgetSamples.office()
        let afternoon = WorkSettings.representativeWorkDate(for: office)
        let earning = Entry(date: afternoon, s: office)
        let offDate = Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: afternoon) ?? afternoon
        let off = Entry(date: offDate, s: office)
        XCTAssertGreaterThan(Earnings(s: office).earnedToday(afternoon), 1)
        XCTAssertGreaterThan(Earnings(s: office).earnedToday(offDate), 1)
        XCTAssertFalse(Earnings(s: office).isEarning(offDate))

        let cases = [("fresh", fresh), ("salary", earning), ("offwork", off)]
        let families: [(String, WidgetFamily, CGSize)] = [
            ("ipad-small", .systemSmall, CGSize(width: 155, height: 155)),
            ("ipad-medium", .systemMedium, CGSize(width: 342, height: 155)),
            ("ipad-large", .systemLarge, CGSize(width: 342, height: 342)),
            ("ipad-extralarge", .systemExtraLarge, CGSize(width: 716, height: 342)),
            ("iphone-small", .systemSmall, CGSize(width: 170, height: 170)),
            ("iphone-medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("iphone-large", .systemLarge, CGSize(width: 364, height: 382)),
            ("lock-rect", .accessoryRectangular, CGSize(width: 172, height: 76)),
            ("lock-circ", .accessoryCircular, CGSize(width: 76, height: 76)),
            ("lock-inline", .accessoryInline, CGSize(width: 260, height: 28)),
        ]
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("widget-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        print("WIDGET_SNAPSHOT_DIR \(dir.path)")
        for (state, entry) in cases {
            let text = Earnings(s: entry.s).earnedToday(entry.date).money(entry.s.currencySymbol, digits: 3)
            XCTAssertTrue(text.contains(where: { $0.isNumber }), "\(state) amount was \(text)")
            for (name, family, size) in families {
                let image = try render(entry: entry, family: family, size: size)
                let bright = brightPixelCount(image)
                XCTAssertGreaterThan(bright, 6, "\(idiom) \(state) \(name) looked blank (\(bright) bright pixels, amount \(text))")
                let file = "\(idiom)-\(state)-\(name).png"
                try image.pngData()?.write(to: dir.appendingPathComponent(file))
                let attachment = XCTAttachment(image: image)
                attachment.name = file
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func render(entry: Entry, family: WidgetFamily, size: CGSize) throws -> UIImage {
        let view = HomeWidgetView(entry: entry)
            .environment(\.widgetFamily, family)
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
            .background {
                if family == .systemSmall || family == .systemMedium || family == .systemLarge || family == .systemExtraLarge {
                    WidgetChrome().environment(\.widgetFamily, family)
                } else {
                    Color(white: 0.12)
                }
            }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage else {
            XCTFail("ImageRenderer returned nil for \(family)")
            throw CocoaError(.fileNoSuchFile)
        }
        return image
    }

    private func brightPixelCount(_ image: UIImage) -> Int {
        let w = 48, h = 48
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = image.cgImage else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var bright = 0
        var i = 0
        while i < pixels.count {
            let sum = Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
            if sum > 280 { bright += 1 }
            i += 4
        }
        return bright
    }
}
