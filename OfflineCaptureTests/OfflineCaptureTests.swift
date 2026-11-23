import XCTest
@testable import EverySecondPays

final class OfflineCaptureTests: XCTestCase {
    @MainActor
    func testRenderMarketingFrames() throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("esp-marketing", isDirectory: true)
        try OfflineCapture.renderAll(to: dir)
        let en = dir.appendingPathComponent("01-en-main/frame-00030.jpg")
        let later = dir.appendingPathComponent("01-en-main/frame-00048.jpg")
        let a = try Data(contentsOf: en)
        let b = try Data(contentsOf: later)
        XCTAssertNotEqual(a, b, "Consecutive coin frames were identical, so the drop was not rendered")
        let landings = try Data(contentsOf: dir.appendingPathComponent("01-en-main/landings.json"))
        XCTAssertGreaterThan(landings.count, 20)
    }
}
