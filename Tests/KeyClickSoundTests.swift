import Foundation

@main
private struct KeyClickSoundTests {
    static func main() throws {
        let expected: [KeyClickSound.Role: KeyClickSound] = [
            .letter: .character, .number: .character, .symbol: .character,
            .delete: .deletion, .space: .operation, .returnKey: .operation,
            .convert: .operation, .shift: .operation, .symbolToggle: .operation, .nextKeyboard: .operation,
        ]
        precondition(expected.count == KeyClickSound.Role.allCases.count)
        for role in KeyClickSound.Role.allCases {
            precondition(role.sound == expected[role], "Unexpected key sound: \(role)")
        }
        var crossings: [KeyClickSound: Int] = [:]
        for sound in KeyClickSound.allCases {
            for access in [false, true] {
                for available in [false, true] {
                    precondition(sound.playback(enabled: false, hasFullAccess: access, available: available) == .silent)
                    let expectedPlayback: KeyClickSound.Playback = access && available ? .custom(sound) : .standard
                    precondition(sound.playback(enabled: true, hasFullAccess: access, available: available) == expectedPlayback)
                }
            }
            let path = "SumibiKeyboard/Sounds/\(sound.rawValue).wav"
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            func text(_ start: Int, _ length: Int) -> String {
                String(decoding: data[start..<(start + length)], as: UTF8.self)
            }
            func u16(_ offset: Int) -> Int {
                Int(data[offset]) | (Int(data[offset + 1]) << 8)
            }
            func u32(_ offset: Int) -> Int {
                u16(offset) | (u16(offset + 2) << 16)
            }
            precondition(data.count > 44 && text(0, 4) == "RIFF" && text(8, 4) == "WAVE")
            precondition(u32(4) == data.count - 8 && text(12, 4) == "fmt " && u32(16) == 16)
            precondition(u16(20) == 1 && u16(22) == 1 && u32(24) == 44_100, "Must be mono PCM 44.1 kHz")
            precondition(u16(32) == 2 && u16(34) == 16 && u32(28) == 88_200)
            precondition(text(36, 4) == "data" && u32(40) == data.count - 44)
            let samples = stride(from: 44, to: data.count, by: 2).map {
                Double(Int16(bitPattern: UInt16(u16($0)))) / Double(Int16.max)
            }
            let duration = Double(samples.count) / 44_100
            precondition(duration >= 0.020 && duration < 0.030, "Click must finish before the 75 ms repeat interval")
            precondition(samples.first == 0 && samples.last == 0, "No abrupt waveform boundary")
            let peak = samples.map(abs).max()!
            precondition(peak > 0.1 && peak < 0.25, "Conservative level without clipping")
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Double(samples.count))
            precondition(rms > 0.02 && rms < 0.1)
            // The common initial 10 ms must be audibly different in pitch.
            crossings[sound] = (1..<441).filter { samples[$0 - 1] < 0 && samples[$0] >= 0 }.count
            if CommandLine.arguments.count == 2 {
                let regenerated = URL(fileURLWithPath: CommandLine.arguments[1])
                    .appendingPathComponent(sound.rawValue + ".wav")
                let regeneratedData = try Data(contentsOf: regenerated)
                precondition(regeneratedData == data, "Bundled sound must match the original generator")
            }
        }
        precondition(crossings[.character]! > crossings[.operation]!)
        precondition(crossings[.operation]! > crossings[.deletion]!)
        print("Click checks passed: 10 key roles, OFF/full-access/fallback routing, PCM headers, duration, levels, envelope, distinct pitches, optional reproducibility")
    }
}
