import Combine
import QuartzCore
import SpriteKit
import UIKit

/// One real collision. `land` is the coin's first solid hit (glass spring).
/// Later `bounce` events are the following impacts on glass, the fixed pile, or another coin.
enum PiggyHit {
    case land(strength: Double, sound: Bool)
    case bounce(strength: Double, sound: Bool)

    var strength: Double {
        switch self {
        case .land(let s, _), .bounce(let s, _): return s
        }
    }
    var sound: Bool {
        switch self {
        case .land(_, let sound), .bounce(_, let sound): return sound
        }
    }
}

extension PiggySkin {
    /// Face tint so a dropped coin matches the coins baked into that skin's photo.
    var coinTint: (UIColor, CGFloat) {
        switch self {
        case .ceramic: return (UIColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1), 0.86)
        case .ingot: return (UIColor(red: 0.86, green: 0.50, blue: 0.24, alpha: 1), 0.58)
        default: return (.white, 0)
        }
    }
}

/// Owns the SpriteKit world and turns contact callbacks into sound, haptics, and a spring token.
final class PiggyBridge: ObservableObject {
    let scene = PiggyBankScene(size: CGSize(width: 400, height: 400))
    /// Today's earnings progress (0…1). Colors the clink. It does not move the pile.
    var fill: Double = 0.5
    /// Bumps once per coin when that coin's first solid impact happens, so the glass can spring.
    @Published private(set) var landToken = 0
    private(set) var landFill = 0.5
    /// While true, SwiftUI unpauses the SpriteView. Idle banks do not burn frames.
    @Published var simulating = false

    init() {
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.onHit = { [weak self] hit in
            guard let self else { return }
            let fire = {
                CoinSound.shared.impact(strength: hit.strength, fullness: self.fill, playSound: hit.sound)
            }
            if Thread.isMainThread { fire() } else { DispatchQueue.main.async(execute: fire) }
            guard case .land = hit else { return }
            let f = self.fill
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.landFill = f
                self.landToken &+= 1
            }
        }
        scene.onIdle = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.scene.hasActiveCoins else { return }
                self.simulating = false
            }
        }
    }
}

/// Rigid-body coin inside the glass. Removed after it rests, so it cannot raise the pile.
private final class CoinNode: SKSpriteNode {
    let born = CACurrentMediaTime()
    var slow: TimeInterval = 0
    var settling = false
    var didLand = false
    var audible = false
    var soundsPlayed = 0
    var hapticsPlayed = 0
    var lastHaptic = 0.0
    var lastSound = 0.0

    init(diameter: CGFloat) {
        super.init(texture: CoinArt.texture, color: .white, size: CGSize(width: diameter, height: diameter))
    }

    required init?(coder: NSCoder) { fatalError("CoinNode is built in code") }
}

/// Full-path coin drop. SpriteKit integrates gravity and solves collisions with the glass
/// edge loop, the fixed half-full pile, and other coins still in motion.
///
/// The pile colliders are static and the photo is always the half-full asset. A coin that
/// comes to rest fades out and is deleted. It is never baked into the pile, so the fill
/// level on screen cannot grow.
final class PiggyBankScene: SKScene, SKPhysicsContactDelegate {
    var onHit: ((PiggyHit) -> Void)?
    var onIdle: (() -> Void)?

    private enum Mask {
        static let coin: UInt32 = 1 << 0
        static let glass: UInt32 = 1 << 1
        static let pile: UInt32 = 1 << 2
    }

    /// Glass interior in photo space: x right, y down, both 0…1 across the square image.
    /// The neck is the slot chute. Checked so the static coins sit inside this outline.
    private static let outline: [(CGFloat, CGFloat)] = [
        (0.448, 0.000), (0.448, 0.250), (0.450, 0.302), (0.420, 0.360),
        (0.378, 0.440), (0.342, 0.520), (0.338, 0.590), (0.365, 0.655),
        (0.450, 0.708), (0.560, 0.716), (0.655, 0.685), (0.712, 0.615),
        (0.738, 0.525), (0.728, 0.440), (0.685, 0.375), (0.625, 0.338),
        (0.572, 0.305), (0.572, 0.250), (0.572, 0.000),
    ]

    /// Fixed half-full pile. (x, y down, radius), all in photo space. These bodies never move.
    private static let pile: [(CGFloat, CGFloat, CGFloat)] = [
        (0.458, 0.558, 0.036),
        (0.450, 0.625, 0.034),
        (0.500, 0.655, 0.034),
        (0.555, 0.650, 0.034),
        (0.610, 0.640, 0.032),
        (0.545, 0.598, 0.032),
        (0.610, 0.585, 0.034),
        (0.665, 0.580, 0.030),
        (0.490, 0.590, 0.028),
        (0.400, 0.630, 0.028),
        (0.415, 0.645, 0.030),
        (0.640, 0.610, 0.028),
        (0.680, 0.590, 0.026),
        (0.430, 0.600, 0.030),
        (0.470, 0.670, 0.028),
    ]

    private let crop = SKCropNode()
    private var builtFor: CGSize = .zero
    private var glassReady = false
    private var pending = 0
    private var wasEmpty = true
    private var lastStep = 0.0
    private var settleQueue: [CoinNode] = []
    private var coinColor: UIColor = .white
    private var coinBlend: CGFloat = 0
    /// Set after `init` finishes so a `didChangeSize` from `super.init` cannot build early.
    private var acceptsLayout = false

    var hasActiveCoins: Bool { !crop.children.isEmpty }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        anchorPoint = .zero
        scaleMode = .aspectFit
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
        addChild(crop)
        acceptsLayout = true
        rebuildIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("PiggyBankScene is built in code") }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 120
        isPaused = false
        rebuildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard acceptsLayout else { return }
        rebuildIfNeeded()
    }

    func apply(skin: PiggySkin) {
        let tint = skin.coinTint
        coinColor = tint.0
        coinBlend = tint.1
        for coin in crop.children.compactMap({ $0 as? CoinNode }) {
            coin.color = coinColor
            coin.colorBlendFactor = coinBlend
        }
    }

    func clearCoins() {
        pending = 0
        removeCoinNodes()
    }

    private func removeCoinNodes() {
        settleQueue.removeAll()
        crop.children.forEach {
            $0.removeAllActions()
            $0.removeFromParent()
        }
    }

    /// Drop one coin through the slot. Extra calls that arrive before layout are queued.
    func drop() {
        rebuildIfNeeded()
        guard glassReady else { pending += 1; return }
        spawn()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let coins = [contact.bodyA.node, contact.bodyB.node].compactMap { $0 as? CoinNode }
        guard let coin = coins.max(by: { speed(of: $0) < speed(of: $1) }), !coin.settling else { return }
        let mass = max(coin.physicsBody?.mass ?? 0, 0.0001)
        let dv = CGFloat(contact.collisionImpulse) / mass
        let characteristic = impactSpeed
        guard characteristic > 1 else { return }
        let strength = min(1, max(0, Double(dv / characteristic)))
        guard strength >= 0.16 else { return }
        let now = CACurrentMediaTime()
        guard coin.hapticsPlayed < 6, now - coin.lastHaptic >= 0.07 else { return }
        coin.lastHaptic = now
        coin.hapticsPlayed += 1
        let primary = !coin.didLand && strength >= 0.20
        if primary { coin.didLand = true }
        let playSound = shouldSound(coin, strength: strength, primary: primary, now: now)
        flash(at: contact.contactPoint, strength: CGFloat(strength))
        onHit?(primary
            ? .land(strength: strength, sound: playSound)
            : .bounce(strength: strength, sound: playSound))
    }

    override func didSimulatePhysics() {
        let now = CACurrentMediaTime()
        let dt = lastStep == 0 || now - lastStep > 0.1 ? 1.0 / 60 : min(0.05, now - lastStep)
        lastStep = now
        let restV = max(18, size.height * 0.035)
        for coin in crop.children.compactMap({ $0 as? CoinNode }) where !coin.settling {
            let v = speed(of: coin)
            let spin = abs(coin.physicsBody?.angularVelocity ?? 0)
            if v < restV && spin < 1.6 { coin.slow += dt } else { coin.slow = 0 }
            let yDown = 1 - coin.position.y / max(size.height, 1)
            if yDown < 0.36, coin.slow > 0.40, let body = coin.physicsBody {
                body.applyImpulse(CGVector(dx: 0, dy: -body.mass * size.height * 0.85))
                coin.slow = 0
            }
            let age = now - coin.born
            let supported = coin.physicsBody?.allContactedBodies().contains { body in
                let name = body.node?.name
                return name == "pile" || name == "glass"
            } ?? false
            let parked = coin.slow > 0.30 && supported && yDown > 0.40
            if parked || age > 3.4 {
                coin.settling = true
                settleQueue.append(coin)
            }
        }
    }

    override func didFinishUpdate() {
        if !settleQueue.isEmpty {
            let batch = settleQueue
            settleQueue.removeAll()
            batch.forEach(finishSettle)
        }
        let empty = crop.children.isEmpty
        if empty && !wasEmpty { onIdle?() }
        wasEmpty = empty
    }

    private func rebuildIfNeeded() {
        guard size.width > 20, size.height > 20 else { return }
        if glassReady, abs(size.width - builtFor.width) < 0.5, abs(size.height - builtFor.height) < 0.5 { return }
        if builtFor != .zero {
            let hadCoins = hasActiveCoins
            removeCoinNodes()
            if hadCoins { pending = max(pending, 1) }
        }
        children.filter { $0.name == "glass" || $0.name == "pile" }.forEach { $0.removeFromParent() }
        builtFor = size
        let drop = 0.42 * size.height
        physicsWorld.gravity = CGVector(dx: 0, dy: -(2 * drop / (0.50 * 0.50)))
        let path = outlinePath()
        let glass = SKNode()
        glass.name = "glass"
        let wall = SKPhysicsBody(edgeLoopFrom: path)
        wall.isDynamic = false
        wall.restitution = 0.52
        wall.friction = 0.10
        wall.categoryBitMask = Mask.glass
        wall.collisionBitMask = Mask.coin
        wall.contactTestBitMask = Mask.coin
        glass.physicsBody = wall
        addChild(glass)

        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        mask.lineWidth = 0
        crop.maskNode = mask

        for coin in Self.pile {
            let node = SKNode()
            node.name = "pile"
            node.position = point(coin.0, coin.1)
            let body = SKPhysicsBody(circleOfRadius: coin.2 * size.width)
            body.isDynamic = false
            body.restitution = 0.36
            body.friction = 0.62
            body.categoryBitMask = Mask.pile
            body.collisionBitMask = Mask.coin
            body.contactTestBitMask = Mask.coin
            node.physicsBody = body
            addChild(node)
        }
        glassReady = true
        if pending > 0 {
            let n = min(pending, 2)
            pending = 0
            for _ in 0..<n { spawn() }
        }
    }

    private func spawn() {
        let live = crop.children.compactMap { $0 as? CoinNode }
        if live.count >= 8, let oldest = live.min(by: { $0.born < $1.born }) {
            oldest.removeAllActions()
            oldest.removeFromParent()
        }
        let r = 0.036 * size.width
        let coin = CoinNode(diameter: r * 2)
        coin.name = "coin"
        coin.color = coinColor
        coin.colorBlendFactor = coinBlend
        coin.zPosition = 2
        let nx = CGFloat.random(in: 0.500...0.520)
        coin.position = point(nx, 0.150)
        coin.zRotation = CGFloat.random(in: 0 ... .pi * 2)
        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.allowsRotation = true
        body.restitution = 0.46
        body.friction = 0.48
        body.linearDamping = 0.20
        body.angularDamping = 0.32
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Mask.coin
        body.collisionBitMask = Mask.glass | Mask.pile | Mask.coin
        body.contactTestBitMask = Mask.glass | Mask.pile | Mask.coin
        coin.physicsBody = body
        coin.audible = CoinSound.shared.armCoin()
        wasEmpty = false
        crop.addChild(coin)
        body.velocity = CGVector(
            dx: CGFloat.random(in: -0.05...0.05) * size.width,
            dy: CGFloat.random(in: -0.22 ... -0.08) * size.height)
        body.angularVelocity = CGFloat.random(in: -5.5...5.5)
    }

    /// Fade the sprite in place and drop its body so later coins still land on the fixed pile.
    /// Body removal is outside the solver step (`didFinishUpdate`).
    private func finishSettle(_ coin: CoinNode) {
        guard coin.parent != nil else { return }
        if !coin.didLand {
            coin.didLand = true
            let playSound = coin.audible && coin.soundsPlayed == 0
            if playSound { coin.soundsPlayed = 1 }
            flash(at: coin.position, strength: 0.45)
            onHit?(.land(strength: 0.45, sound: playSound))
        }
        coin.physicsBody = nil
        coin.run(.sequence([
            .wait(forDuration: 0.16),
            .fadeOut(withDuration: 0.40),
            .removeFromParent(),
        ]))
    }

    private func shouldSound(_ coin: CoinNode, strength: Double, primary: Bool, now: TimeInterval) -> Bool {
        guard coin.audible, coin.soundsPlayed < 3 else { return false }
        guard now - coin.lastSound >= 0.12 else { return false }
        if !primary && strength < 0.42 { return false }
        coin.soundsPlayed += 1
        coin.lastSound = now
        return true
    }

    private func flash(at p: CGPoint, strength: CGFloat) {
        let radius = 7 + 16 * strength
        let ring = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: radius))
        ring.position = p
        ring.zPosition = 4
        ring.strokeColor = UIColor(red: 1, green: 0.89, blue: 0.60, alpha: 0.9)
        ring.fillColor = UIColor(white: 1, alpha: 0.28)
        ring.lineWidth = 1.5
        ring.glowWidth = 0
        crop.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 2.1, duration: 0.26), .fadeOut(withDuration: 0.26)]),
            .removeFromParent(),
        ]))
    }

    private func speed(of coin: CoinNode) -> CGFloat {
        let v = coin.physicsBody?.velocity ?? .zero
        return hypot(v.dx, v.dy)
    }

    /// Speed a coin reaches falling from the slot onto the pile. Impact strength is relative to this.
    private var impactSpeed: CGFloat {
        let drop = 0.42 * size.height
        let g = abs(physicsWorld.gravity.dy)
        return sqrt(max(1, 2 * g * drop))
    }

    private func point(_ nx: CGFloat, _ nyDown: CGFloat) -> CGPoint {
        CGPoint(x: nx * size.width, y: (1 - nyDown) * size.height)
    }

    private func outlinePath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: Self.outline.map { point($0.0, $0.1) })
        path.closeSubpath()
        return path
    }
}

private enum CoinArt {
    static let texture: SKTexture = {
        let s: CGFloat = 128
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format).image { ctx in
            let c = ctx.cgContext
            c.addEllipse(in: CGRect(x: 1, y: 1, width: s - 2, height: s - 2))
            c.clip()
            let colors = [
                UIColor(red: 1.00, green: 0.94, blue: 0.74, alpha: 1).cgColor,
                UIColor(red: 0.91, green: 0.77, blue: 0.42, alpha: 1).cgColor,
                UIColor(red: 0.54, green: 0.39, blue: 0.13, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.55, 1]
            let grad = locations.withUnsafeBufferPointer { buffer in
                CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: buffer.baseAddress)
            }
            if let grad {
                c.drawRadialGradient(
                    grad,
                    startCenter: CGPoint(x: s * 0.36, y: s * 0.34), startRadius: 2,
                    endCenter: CGPoint(x: s * 0.50, y: s * 0.50), endRadius: s * 0.58,
                    options: [])
            }
            c.setStrokeColor(UIColor(red: 0.45, green: 0.32, blue: 0.09, alpha: 0.85).cgColor)
            c.setLineWidth(3)
            c.move(to: CGPoint(x: s * 0.50, y: s * 0.50))
            c.addLine(to: CGPoint(x: s * 0.50, y: s * 0.27))
            c.strokePath()
            c.setStrokeColor(UIColor(red: 0.40, green: 0.28, blue: 0.08, alpha: 0.95).cgColor)
            c.setLineWidth(7)
            c.strokeEllipse(in: CGRect(x: 6, y: 6, width: s - 12, height: s - 12))
            c.setStrokeColor(UIColor(red: 1, green: 0.95, blue: 0.80, alpha: 0.75).cgColor)
            c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: 16, y: 16, width: s - 32, height: s - 32))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}
