import AVFoundation
import CoreHaptics
import UIKit

/// Coin-landing feedback: the slot sound and a Core Haptics (AHAP) transient fire in the same call,
/// at the frame the coin actually lands. Audio uses the .ambient category, so it mixes with other
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
    /// `fullness` 0…1 makes the clink heavier/duller as the piggy fills up.
    static func ahap(fullness f: Double) -> [CHHapticPattern.Key: Any] {
        let intensity = 0.35 + 0.55 * f, sharp = 0.85 - 0.5 * f
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
                    CHHapticPattern.Key.eventDuration: 0.08 + 0.06 * f,
                    CHHapticPattern.Key.eventParameters: [
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticIntensity.rawValue, CHHapticPattern.Key.parameterValue: intensity * 0.35],
                        [CHHapticPattern.Key.parameterID: CHHapticEvent.ParameterID.hapticSharpness.rawValue, CHHapticPattern.Key.parameterValue: 0.2]]]],
            ]
        ]
    }

    /// Call exactly when the coin hits the slot.
    func coinLanded(fullness: Double = 0) {
        counter += 1
        let f = min(1, max(0, fullness))
        let playSound = !s.muted && counter % max(1, s.playEveryN) == 0 && !players.isEmpty
        if s.haptics { playHaptic(f) }
        guard playSound else { return }
        let p = players[idx % players.count]; idx += 1
        p.volume = s.volume * Float(0.8 + 0.2 * f)
        p.currentTime = 0; p.play()
    }

    private func playHaptic(_ f: Double) {
        guard let engine, let pattern = try? CHHapticPattern(dictionary: Self.ahap(fullness: f)) else {
            fallback.impactOccurred(intensity: 0.35 + 0.55 * f); return
        }
        do { try engine.start(); try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate) }
        catch { fallback.impactOccurred(intensity: 0.35 + 0.55 * f) }
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
