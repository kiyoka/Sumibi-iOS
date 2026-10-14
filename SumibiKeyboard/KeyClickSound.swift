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

    func playback(enabled: Bool, hasFullAccess: Bool, available: Bool) -> Playback {
        guard enabled else { return .silent }
        guard hasFullAccess, available else { return .standard }
        return .custom(self)
    }
}

#if canImport(UIKit)
import AudioToolbox
import UIKit

/// Preloads the three tiny files before typing. Playback does not do file I/O,
/// change AVAudioSession, or use alert playback to bypass silent mode.
@MainActor
final class KeyClickSoundPlayer {
    private var sounds: [KeyClickSound: SystemSoundID] = [:]
    private var prepared = false

    func prepare(bundle: Bundle = .main) {
        guard !prepared else { return }
        prepared = true
        for kind in KeyClickSound.allCases {
            guard let url = bundle.url(forResource: kind.rawValue, withExtension: "wav", subdirectory: "Sounds") else {
                continue
            }
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else {
                continue
            }
            // Keep default UI-sound behavior. Never force an audible alert.
            var isUISound: UInt32 = 1
            let status = AudioServicesSetProperty(
                kAudioServicesPropertyIsUISound,
                UInt32(MemoryLayout<SystemSoundID>.size), &id,
                UInt32(MemoryLayout<UInt32>.size), &isUISound
            )
            guard status == noErr else {
                AudioServicesDisposeSystemSoundID(id)
                continue
            }
            sounds[kind] = id
        }
    }

    func play(_ kind: KeyClickSound, enabled: Bool, hasFullAccess: Bool) {
        switch kind.playback(enabled: enabled, hasFullAccess: hasFullAccess, available: sounds[kind] != nil) {
        case .silent:
            break
        case .standard:
            UIDevice.current.playInputClick()
        case .custom:
            if let id = sounds[kind] {
                AudioServicesPlaySystemSoundWithCompletion(id, nil)
            }
        }
    }

    deinit {
        for id in sounds.values {
            AudioServicesDisposeSystemSoundID(id)
        }
    }
}

final class SoundFeedbackButton: UIButton {
    var clickSound: KeyClickSound = .character
}
#endif
