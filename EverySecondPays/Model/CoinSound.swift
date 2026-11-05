import AVFoundation
import CoreHaptics
import UIKit

/// Coin-impact feedback. Sound and a Core Haptics (AHAP) transient fire in the same call,
/// at a real collision — not on a timer. Audio uses the .ambient category, so it mixes with other
/// audio and is silenced by the Ring/Silent switch; haptics follow the in-app toggle and system settings.
final class CoinSound {
    static let shared = CoinSound()
    private var players: [AVAudioPlayer] = []
    private var idx = 0
    private var counter = 0
    private var s = WorkSettings()
    private var engine: CHHapticEngine?
    private let fallback = UIImpactFeedbackGenerator(style: .soft)
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare(_ settings: WorkSettings) {
        s = settings
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let id = Entitlements.allows(sound: settings.soundID) ? settings.soundID : SoundOption.pennySlot.rawValue
        if let url = Bundle.main.url(forResource: id, withExtension: "wav") {
            players = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }   // round-robin so overlaps ring out
            players.forEach { $0.volume = settings.volume; $0.prepareToPlay() }
        } else { players = [] }
        prepareHaptics()
    }

    private func prepareHaptics() {
        guard supportsHaptics, s.haptics else { engine?.stop(); engine = nil; fallback.prepare(); return }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = true            // low power: idles between coins
            engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    /// AHAP pattern: a crisp "clink" transient followed by a short soft settle.
    /// `fullness` 0…1 makes the clink heavier as the workday progresses.
    /// `strength` 0…1 is the collision speed relative to a full drop. 1 keeps the original curve.
    static func ahap(fullness f: Double, strength: Double = 1) -> [CHHapticPattern.Key: Any] {
        let k = min(1, max(0.15, strength))
        let intensity = min(1, (0.35 + 0.55 * f) * (0.45 + 0.55 * k))
        let sharp = min(1, max(0, (0.85 - 0.5 * f) * (0.65 + 0.35 * k)))
        let duration = (0.08 + 0.06 * f) * (0.70 + 0.30 * k)
        return [
            .version: 1.0,
            .pattern: [
                [CHHapticPattern.Key.event: [
                    CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient.rawValue,
                    CHHapticPattern.Key.time: 0.0,
                    CHHapticPattern.Key.eventParameters: [
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue, CHHapticPattern.Key.parameterValue: intensity],
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue, CHHapticPattern.Key.parameterValue: sharp]]]],
                [CHHapticPattern.Key.event: [
                    CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticContinuous.rawValue,
                    CHHapticPattern.Key.time: 0.02,
                    CHHapticPattern.Key.eventDuration: duration,
                    CHHapticPattern.Key.eventParameters: [
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue, CHHapticPattern.Key.parameterValue: intensity * 0.35],
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue, CHHapticPattern.Key.parameterValue: 0.2]]]],
            ]
        ]
    }

    /// Call once per dropped coin, before its impacts. `playEveryN` still means every Nth coin.
    /// Returns whether this coin may play the slot sound.
    func armCoin() -> Bool {
        counter += 1
        return !s.muted && !players.isEmpty && counter % max(1, s.playEveryN) == 0
    }

    /// Reduce Motion path: no flight, one impact at full strength.
    func coinLanded(fullness: Double = 0) {
        impact(strength: 1, fullness: fullness, playSound: armCoin())
    }

    /// Call from the physics contact callback, on the frame of a real hit.
    func impact(strength: Double, fullness: Double, playSound: Bool) {
        let f = min(1, max(0, fullness))
        let k = min(1, max(0, strength))
        if s.haptics { playHaptic(f, strength: k) }
        guard playSound, !s.muted, !players.isEmpty else { return }
        let p = players[idx % players.count]; idx += 1
        p.volume = s.volume * Float(0.72 + 0.28 * k) * Float(0.85 + 0.15 * f)
        p.currentTime = 0
        p.play()
    }

    private func playHaptic(_ f: Double, strength: Double = 1) {
        let k = min(1, max(0, strength))
        let fallbackIntensity = min(1, (0.35 + 0.55 * f) * (0.45 + 0.55 * max(0.15, k)))
        guard let engine, let pattern = try? CHHapticPattern(dictionary: Self.ahap(fullness: f, strength: k)) else {
            fallback.impactOccurred(intensity: fallbackIntensity); return
        }
        do { try engine.start(); try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate) }
        catch { fallback.impactOccurred(intensity: fallbackIntensity) }
    }

    /// Bigger "piggy is full" celebration.
    func piggyFull() {
        guard s.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func preview(_ id: String) {
        guard let url = Bundle.main.url(forResource: id, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = s.volume; p.play(); players.append(p)
        if s.haptics { playHaptic(0.5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.prepare(self?.s ?? WorkSettings()) }
    }
}
