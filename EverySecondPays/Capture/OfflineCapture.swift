#if DEBUG
import Metal
import SpriteKit
import SwiftUI
import UIKit

/// Renders marketing frames by stepping the real coin scene at a fixed rate.
/// Compiled out of Release, so the App Store build does not include it.
enum OfflineCapture {
    static let fps = 30
    static let scale: CGFloat = 3
    static let pointSize = CGSize(width: 440, height: 956)

    struct Clip {
        var name: String
        var seconds: Double
        var language: String
        var salary: Double
        var symbol: String
        /// Seconds of the settings screen before the piggy. Zero skips it.
        var settingsLead: Double = 0
    }

    struct Landing: Codable {
        var coin: Int
        var time: Double
        var frame: Int
    }

    struct LandingFile: Codable {
        var fps: Int
        var frames: Int
        var duration: Double
        var width: Int
        var height: Int
        var salary: Double
        var currency: String
        var clock: String
        var schedule: String
        var landings: [Landing]
    }

    @MainActor
    static func renderAll(to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clock = afternoon()
        let clips = [
            Clip(name: "01-en-main", seconds: 30, language: "en", salary: 5_000, symbol: "$"),
            Clip(name: "02-zh-Hans-main", seconds: 20, language: "zh-Hans", salary: 15_000, symbol: "¥"),
            Clip(name: "03-en-settings", seconds: 20, language: "en", salary: 5_000, symbol: "$", settingsLead: 8),
        ]
        for clip in clips {
            try render(clip, clock: clock, to: root.appendingPathComponent(clip.name, isDirectory: true))
        }
        try renderShareCards(clock: clock, to: root)
        print("ESP_CAPTURE_DIR \(root.path)")
    }

    @MainActor
    private static func render(_ clip: Clip, clock: Date, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = schedule(salary: clip.salary, symbol: clip.symbol)
        let strings = Strings(language: clip.language)
        let walnut = try swiftImage(WalnutBackground().frame(width: pointSize.width, height: pointSize.height))
        let engine = try CoinEngine()
        let leadFrames = Int((clip.settingsLead * Double(fps)).rounded())
        let total = Int((clip.seconds * Double(fps)).rounded())
        let lands = LandingBox()
        engine.onLand = { frame in
            lands.items.append(Landing(
                coin: lands.items.count + 1,
                time: Double(frame) / Double(fps),
                frame: frame))
        }
        let fadeFrames = clip.settingsLead > 0 ? Int(0.45 * Double(fps)) : 0
        let mainStart = leadFrames
        var settingsCache: [String: UIImage] = [:]
        func cachedSettings(_ progress: Double) throws -> UIImage {
            let key = typedSalary(progress: progress)
            if let cached = settingsCache[key] { return cached }
            let image = try settingsImage(clip, strings: strings, progress: progress)
            settingsCache[key] = image
            return image
        }

        for frame in 0..<total {
            try autoreleasepool {
            let t = Double(frame) / Double(fps)
            let showMain = frame >= mainStart - fadeFrames
            let image: UIImage
            if showMain {
                let mainTime = max(0, t - clip.settingsLead)
                let now = clock.addingTimeInterval(mainTime)
                let earned = Earnings(s: settings).earnedToday(now)
                let piggy = try engine.frame(at: frame, mainStart: mainStart)
                let main = try swiftImage(CaptureMainView(
                    walnut: walnut, piggy: piggy, title: strings["app.name"],
                    today: strings["main.today"], amount: earned, symbol: clip.symbol,
                    perSecondLabel: strings["main.perSecond"],
                    perSecond: Earnings(s: settings).perSecond.money(clip.symbol, digits: 4),
                    perDayLabel: strings["main.perDay"],
                    perDay: Earnings(s: settings).perDay.money(clip.symbol),
                    locked: strings["history.locked"],
                    status: strings["main.earning"]
                ))
                if frame < mainStart {
                    let u = Double(frame - (mainStart - fadeFrames)) / Double(max(fadeFrames, 1))
                    image = blend(try cachedSettings(1), main, CGFloat(u))
                } else {
                    image = main
                }
            } else {
                image = try cachedSettings(t / max(clip.settingsLead, 0.01))
            }
            let url = dir.appendingPathComponent(String(format: "frame-%05d.jpg", frame + 1))
            guard let data = image.jpegData(compressionQuality: 0.92) else { throw CaptureError.encode }
            try data.write(to: url)
            }
        }

        let file = LandingFile(
            fps: fps, frames: total, duration: Double(total) / Double(fps),
            width: Int(pointSize.width * scale), height: Int(pointSize.height * scale),
            salary: clip.salary, currency: clip.symbol,
            clock: "2026-11-18 14:30",
            schedule: "Mon–Fri 09:00–18:00, 60 min lunch",
            landings: lands.items)
        let data = try JSONEncoder.pretty.encode(file)
        try data.write(to: dir.appendingPathComponent("landings.json"))
        guard lands.items.count >= Int(clip.seconds - clip.settingsLead) - 2 else {
            throw CaptureError.fewLandings(lands.items.count)
        }
        // A coin that covers the chute in one step means the physics clock jumped.
        let delays = lands.items.map { landing -> Int in
            let drop = mainStart + 8 + (landing.coin - 1) * fps
            return landing.frame - drop
        }.sorted()
        let median = delays[delays.count / 2]
        print("ESP_FALL_MEDIAN \(clip.name) \(median)")
        guard median >= 10 else { throw CaptureError.fastFall(median) }
    }

    @MainActor
    private static func renderShareCards(clock: Date, to root: URL) throws {
        let cards: [(String, String, Double, String)] = [
            ("share-card-en.png", "en", 5_000, "$"),
            ("share-card-zh.png", "zh-Hans", 15_000, "¥"),
        ]
        for (name, lang, salary, symbol) in cards {
            let settings = schedule(salary: salary, symbol: symbol)
            let earned = Earnings(s: settings).earnedToday(clock)
            let strings = Strings(language: lang)
            let df = DateFormatter()
            df.locale = Locale(identifier: lang == "en" ? "en_US" : "zh_CN")
            df.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
            let image = try swiftImage(CaptureShareCard(
                headline: strings["share.headline"], amount: earned, symbol: symbol,
                date: df.string(from: clock), tagline: strings["share.tagline"]
            ), size: CGSize(width: 360, height: 640))
            guard let png = image.pngData() else { throw CaptureError.encode }
            try png.write(to: root.appendingPathComponent(name))
        }
    }

    private static func afternoon() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Calendar.current.timeZone
        return cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14, minute: 30))!
    }

    private static func schedule(salary: Double, symbol: String) -> WorkSettings {
        var s = WorkSettings()
        s.onboarded = true
        s.monthlySalary = salary
        s.workDays = [2, 3, 4, 5, 6]
        s.startMinutes = 9 * 60
        s.endMinutes = 18 * 60
        s.lunchBreakMinutes = 60
        s.currencySymbol = symbol
        s.muted = true
        s.skin = PiggySkin.glass.rawValue
        s.installDate = afternoon().addingTimeInterval(-86_400 * 40)
        return s
    }

    @MainActor
    private static func settingsImage(_ clip: Clip, strings: Strings, progress: Double) throws -> UIImage {
        let typed = typedSalary(progress: progress)
        return try swiftImage(CaptureSettingsView(
            title: strings["settings.title"], done: strings["common.done"],
            unlock: strings["paywall.title"], salaryHeader: strings["settings.salary"],
            salary: typed, placeholder: strings["settings.salary.placeholder"],
            currency: strings["settings.currency"], symbol: clip.symbol,
            schedule: strings["settings.schedule"],
            days: Calendar.current.shortWeekdaySymbols,
            startLabel: strings["settings.start"], start: "9:00 AM",
            endLabel: strings["settings.end"], end: "6:00 PM"
        ))
    }

    /// Types 5,000 across the settings lead. `progress` is 0…1.
    private static func typedSalary(progress: Double) -> String {
        let marks = [0.18, 0.34, 0.50, 0.66]
        let stages = ["5", "50", "500", "5,000"]
        var text = ""
        for (mark, stage) in zip(marks, stages) where progress >= mark { text = stage }
        return text
    }

    @MainActor
    private static func swiftImage<V: View>(_ view: V, size: CGSize = pointSize) throws -> UIImage {
        let content = view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true
        guard let image = renderer.uiImage, image.size.width > 8 else { throw CaptureError.blank }
        return image
    }

    private static func blend(_ a: UIImage, _ b: UIImage, _ t: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: a.size.width * a.scale, height: a.size.height * a.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            a.draw(in: CGRect(origin: .zero, size: size))
            b.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: min(1, max(0, t)))
        }
    }
}

/// Steps `PiggyBankScene` with `SKRenderer` so every frame exists even when the
/// simulator is not presenting in real time.
private final class CoinEngine {
    var onLand: ((Int) -> Void)?
    private let renderer: SKRenderer
    private let scene: PiggyBankScene
    private let queue: MTLCommandQueue
    private let device: MTLDevice
    private let width: Int
    private let height: Int
    private let dt = 1.0 / Double(OfflineCapture.fps)
    // Metal's texture read is bottom-up relative to the scene, which otherwise
    // draws the piggy standing on its head.
    private var flip = true
    private var primed = false
    private var currentFrame = 0
    private var simTime = 10_000.0
    private var lastWall = 0.0
    /// Extra scale so a coin's fall lasts about 0.6 s even if the world speed is not linear.
    private var bias = 1.0
    private var probing = false

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CaptureError.noMetal
        }
        self.device = device
        self.queue = queue
        width = 1020
        height = Int((1020 * (1 + PiggyBankScene.sky)).rounded())
        scene = PiggyBankScene(size: CGSize(width: width, height: height))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.apply(skin: .glass)
        renderer = SKRenderer(device: device)
        renderer.scene = scene
        scene.onHit = { [weak self] hit in
            guard let self, case .land = hit else { return }
            self.onLand?(self.currentFrame)
        }
    }

    func frame(at index: Int, mainStart: Int) throws -> UIImage {
        currentFrame = index
        if !primed {
            tuneFall()
            primed = true
        }
        guard index >= mainStart else {
            lastWall = CACurrentMediaTime()
            return try draw(flip: flip)
        }
        let into = index - mainStart
        if into % OfflineCapture.fps == 8 { scene.drop() }
        step(simDt: dt, bias: bias)
        return try draw(flip: flip)
    }

    /// Find a speed scale that lets one coin stay in the air for about 18 frames.
    private func tuneFall() {
        let saved = onLand
        var trial = 1.0
        for _ in 0..<4 {
            let delay = sampleFall(bias: trial)
            print(String(format: "ESP_PROBE delay %d bias %.3f", delay, trial))
            if (14...26).contains(delay) { break }
            // Higher speed lands sooner, so a short fall means the next trial must be slower.
            let next = min(8, max(0.02, trial * Double(max(delay, 1)) / 18.0))
            if abs(next - trial) < 0.005 { break }
            trial = next
        }
        bias = trial
        onLand = saved
        scene.resetForOfflineCapture()
        lastWall = CACurrentMediaTime()
        print(String(format: "ESP_BIAS %.3f", bias))
    }

    private func sampleFall(bias: Double) -> Int {
        scene.resetForOfflineCapture()
        lastWall = CACurrentMediaTime()
        var landedAt: Int?
        onLand = { landedAt = $0 }
        probing = true
        for i in 0..<48 {
            currentFrame = i
            if i == 6 { scene.drop() }
            step(simDt: dt, bias: bias)
            if landedAt != nil { break }
            Thread.sleep(forTimeInterval: 0.15)
        }
        probing = false
        return (landedAt ?? 90) - 6
    }

    /// The renderer integrates wall-clock time. Physics-world speed turns that gap into `simDt`.
    /// Contacts are delivered by the render pass, so a probe has to draw as well as step.
    private func step(simDt: Double, bias: Double) {
        let wall = CACurrentMediaTime()
        let elapsed = lastWall == 0 ? simDt : max(wall - lastWall, 1.0 / 500)
        lastWall = wall
        simTime += simDt
        PhysicsTime.override = simTime
        scene.isPaused = false
        scene.speed = 1
        scene.physicsWorld.speed = CGFloat(min(12, simDt / elapsed * bias))
        renderer.update(atTime: wall)
        scene.guideOfflineFalls()
        if probing { _ = try? draw(flip: flip) }
    }

    private func draw(flip: Bool) throws -> UIImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let buffer = queue.makeCommandBuffer() else { throw CaptureError.encode }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        renderer.render(
            withViewport: CGRect(x: 0, y: 0, width: width, height: height),
            commandBuffer: buffer, renderPassDescriptor: pass)
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        if flip { bytes = Self.flipped(bytes, width: width, height: height) }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw CaptureError.encode }
        return UIImage(cgImage: cg, scale: OfflineCapture.scale, orientation: .up)
    }

    private static func flipped(_ bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        let row = width * 4
        var out = [UInt8](repeating: 0, count: bytes.count)
        for y in 0..<height {
            let src = y * row
            let dst = (height - 1 - y) * row
            out.replaceSubrange(dst..<(dst + row), with: bytes[src..<(src + row)])
        }
        return out
    }
}

private struct Strings {
    var language: String
    subscript(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? key : value
    }
}

private struct CaptureMainView: View {
    var walnut: UIImage
    var piggy: UIImage
    var title: String
    var today: String
    var amount: Double
    var symbol: String
    var perSecondLabel: String
    var perSecond: String
    var perDayLabel: String
    var perDay: String
    var locked: String
    var status: String

    var body: some View {
        ZStack(alignment: .top) {
            Image(uiImage: walnut).resizable().ignoresSafeArea()
            VStack(spacing: 22) {
                Color.clear.frame(height: 48)
                HStack {
                    Text(title).font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Palette.cream)
                    Spacer()
                    Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(Palette.brass)
                    ProBadge()
                    Image(systemName: "gearshape.fill").font(.title2).foregroundStyle(Palette.brass)
                }.padding(.horizontal)
                BrassPlate {
                    VStack(spacing: 6) {
                        Text(today).font(.caption.weight(.semibold)).embossed()
                        Odometer(value: amount, symbol: symbol)
                    }
                }
                ZStack(alignment: .top) {
                    Color.clear.frame(width: 340, height: 340)
                    Image(uiImage: piggy).resizable().scaledToFit()
                        .frame(width: 340, height: 340 * (1 + PiggyBankScene.sky))
                        .offset(y: -340 * PiggyBankScene.sky)
                }.frame(maxWidth: 360)
                HStack(spacing: 14) {
                    stat(perSecondLabel, perSecond)
                    stat(perDayLabel, perDay)
                }
                Label(locked, systemImage: "lock.fill").font(.caption).foregroundStyle(Palette.cream.opacity(0.7))
                Text(status).font(.footnote).foregroundStyle(Palette.cream.opacity(0.7))
                Spacer(minLength: 0)
            }
            statusBar
        }
    }

    private var statusBar: some View {
        ZStack {
            Capsule().fill(.black).frame(width: 126, height: 36).padding(.top, 12)
            HStack {
                Text("9:41").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "cellularbars").font(.system(size: 14, weight: .semibold))
                Image(systemName: "wifi").font(.system(size: 14, weight: .semibold))
                Image(systemName: "battery.100").font(.system(size: 18, weight: .regular))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .frame(height: 54)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Palette.cream.opacity(0.7))
            Text(value).font(.system(.callout, design: .rounded).monospacedDigit().weight(.semibold)).foregroundStyle(Color(hex: 0xF2D690))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.28)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08))))
    }
}

private struct CaptureSettingsView: View {
    var title: String
    var done: String
    var unlock: String
    var salaryHeader: String
    var salary: String
    var placeholder: String
    var currency: String
    var symbol: String
    var schedule: String
    var days: [String]
    var startLabel: String
    var start: String
    var endLabel: String
    var end: String

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Text(done).font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }.padding(.top, 58)
                Text(title).font(.largeTitle.bold()).foregroundStyle(.white)
                row {
                    HStack {
                        Image(systemName: "crown.fill").foregroundStyle(Color(hex: 0xE9C46A))
                        Text(unlock).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                section(salaryHeader) {
                    HStack {
                        Text(symbol).foregroundStyle(.white)
                        Text(salary.isEmpty ? placeholder : salary)
                            .foregroundStyle(salary.isEmpty ? Color.white.opacity(0.35) : .white)
                        Spacer()
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Text(currency).foregroundStyle(.white)
                        Spacer()
                        Text(symbol).foregroundStyle(.secondary)
                    }
                }
                section(schedule) {
                HStack {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let on = (2...6).contains(index + 1)
                        Text(String(day.prefix(3)))
                            .font(.caption2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(on ? Color(hex: 0xE9C46A) : Color.white.opacity(0.12)))
                            .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                    }
                }
                    time(startLabel, start)
                    time(endLabel, end)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            statusBar
        }
    }

    private var statusBar: some View {
        HStack {
            Text("9:41").font(.system(size: 16, weight: .semibold))
            Spacer()
            Image(systemName: "cellularbars")
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(height: 54, alignment: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
            row(content: content)
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func time(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        }
    }
}

private struct CaptureShareCard: View {
    var headline: String
    var amount: Double
    var symbol: String
    var date: String
    var tagline: String

    var body: some View {
        ZStack {
            WalnutBackground()
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                Text(headline).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.cream)
                BrassPlate {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(symbol).font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(String(format: "%.2f", amount)).font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                    }.embossed().lineLimit(1).minimumScaleFactor(0.4)
                }
                Image("pig_half").resizable().scaledToFit().frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                Text(date).font(.system(.body, design: .rounded)).foregroundStyle(Palette.cream.opacity(0.75))
                Spacer(minLength: 0)
                Text(tagline).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Palette.cream.opacity(0.55))
                    .padding(.bottom, 36)
            }.padding(.horizontal, 24)
        }
    }
}

private final class LandingBox {
    var items: [OfflineCapture.Landing] = []
}

private enum CaptureError: Error {
    case noMetal, encode, blank, fewLandings(Int), fastFall(Int)
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
#endif
