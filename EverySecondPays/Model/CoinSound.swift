import AVFoundation
import UIKit

/// Gentle coin sound + soft haptic. Mixes with other audio and respects the silent switch.
final class CoinSound {
    static let shared = CoinSound()
    private var players: [AVAudioPlayer] = []
    private var idx = 0
    private var counter = 0
    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private var s = WorkSettings()

    func prepare(_ settings: WorkSettings) {
        s = settings
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let id = Entitlements.allows(sound: settings.soundID) ? settings.soundID : SoundOption.pennySlot.rawValue
        guard let url = Bundle.main.url(forResource: id, withExtension: "wav") else { return }
        players = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }   // round-robin so overlaps ring out
        players.forEach { $0.volume = settings.volume; $0.prepareToPlay() }
        haptic.prepare()
    }

    func coinLanded() {
        counter += 1
        if s.haptics { haptic.impactOccurred(intensity: 0.45) }
        guard !s.muted, counter % max(1, s.playEveryN) == 0, !players.isEmpty else { return }
        let p = players[idx % players.count]; idx += 1
        p.currentTime = 0; p.play()
    }

    func preview(_ id: String) {
        guard let url = Bundle.main.url(forResource: id, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = s.volume; p.play(); players.append(p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.prepare(self?.s ?? WorkSettings()) }
    }
}
