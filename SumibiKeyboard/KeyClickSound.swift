import Foundation

/// Original, bundled clicks. No undocumented iOS sound identifiers are used.
enum KeyClickSound: String, CaseIterable, Sendable {
    case character = "key-character"
    case deletion = "key-delete"
    case operation = "key-operation"

    enum Role: CaseIterable {
        case letter, number, symbol, space, delete, returnKey, convert, shift, symbolToggle, nextKeyboard

        var sound: KeyClickSound {
            switch self {
            case .letter, .number, .symbol: .character
            case .delete: .deletion
            case .space, .returnKey, .convert, .shift, .symbolToggle, .nextKeyboard: .operation
            }
        }
    }

    enum Playback: Equatable {
        case silent, standard, custom(KeyClickSound)
    }

    func playback(enabled: Bool, hasFullAccess: Bool, available: Bool, interrupted: Bool = false) -> Playback {
        guard enabled else { return .silent }
        if hasFullAccess && interrupted { return .silent }
        guard hasFullAccess, available else { return .standard }
        return .custom(self)
    }
}

#if canImport(UIKit)
import AVFAudio
import UIKit

/// Owns observer tokens without actor-isolated deinit work.
private final class KeyClickAudioNotifications {
    var tokens: [NSObjectProtocol] = []

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

/// Preloads the three tiny files before typing. The ambient session respects
/// silent mode, mixes with other audio, and uses the OS media output volume.
@MainActor
final class KeyClickSoundPlayer {
    private var players: [KeyClickSound: AVAudioPlayer] = [:]
    private let session = AVAudioSession.sharedInstance()
    private let notifications = KeyClickAudioNotifications()
    private var didLoadSounds = false
    private var sessionActive = false
    private var interrupted = false

    init() {
        notifications.tokens.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                self?.interruptionChanged(began: type == AVAudioSession.InterruptionType.began.rawValue)
            }
        })
        notifications.tokens.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Recreate players/session on the next permitted key press.
                self?.players.removeAll()
                self?.didLoadSounds = false
                self?.sessionActive = false
                self?.interrupted = false
            }
        })
    }

    func prepare(bundle: Bundle = .main) {
        guard !interrupted else { return }
        var didActivate = false
        if !sessionActive {
            do {
                // ambient mixes by default; never use playback/duckOthers here.
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                sessionActive = true
                didActivate = true
            } catch {
                return
            }
        }
        if didLoadSounds {
            if didActivate {
                for player in players.values { _ = player.prepareToPlay() }
            }
            return
        }
        didLoadSounds = true
        for kind in KeyClickSound.allCases {
            guard let url = bundle.url(forResource: kind.rawValue, withExtension: "wav", subdirectory: "Sounds") else {
                continue
            }
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                continue
            }
            // Relative gain only. OS output volume is applied by AVFAudio;
            // multiplying by outputVolume again would attenuate it twice.
            player.volume = 1
            guard player.prepareToPlay() else { continue }
            players[kind] = player
        }
    }

    func play(_ kind: KeyClickSound, enabled: Bool, hasFullAccess: Bool) {
        if !enabled || !hasFullAccess {
            suspend()
        } else if !interrupted {
            prepare()
        }
        // No deferred click is queued during phone/Siri interruptions.
        switch kind.playback(enabled: enabled, hasFullAccess: hasFullAccess,
                             available: sessionActive && players[kind] != nil,
                             interrupted: interrupted) {
        case .silent:
            break
        case .standard:
            UIDevice.current.playInputClick()
        case .custom:
            if let player = players[kind] {
                player.currentTime = 0
                if !player.play() {
                    // Recover on the next press, never replay this click later.
                    suspend()
                    didLoadSounds = false
                    players.removeAll()
                }
            }
        }
    }

    func suspend() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
        guard sessionActive else { return }
        // A failed deactivation must not be treated as a successful release.
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        } catch {}
    }

    private func interruptionChanged(began: Bool) {
        interrupted = began
        if began {
            for player in players.values { player.stop(); player.currentTime = 0 }
            // iOS deactivated the session. A future tap will reactivate it,
            // but no audio resumes merely because an interruption ended.
            sessionActive = false
        }
    }
}

final class SoundFeedbackButton: UIButton {
    var clickSound: KeyClickSound = .character
}
#endif
