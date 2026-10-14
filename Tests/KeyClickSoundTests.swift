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
                    precondition(sound.playback(enabled: false, hasFullAccess: access,
                                                available: available, interrupted: true) == .silent)
                    precondition(sound.playback(enabled: true, hasFullAccess: access,
                                                available: available, interrupted: true) == (access ? .silent : .standard),
                                 "Custom clicks must be suppressed during an interruption, not queued or replaced with a standard sound")
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
            precondition(peak > 0.12 && peak < 0.40, "Boosted click must retain headroom without clipping")
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Double(samples.count))
            precondition(rms > 0.02 && rms < 0.12)
            // Check the actual WAV spectrum, not just the generator's settings.
            // Keep the useful knock energy below 1.5 kHz; reject shrill tones.
            func power(at frequency: Double) -> Double {
                var real = 0.0
                var imaginary = 0.0
                for (index, sample) in samples.enumerated() {
                    let phase = 2 * Double.pi * frequency * Double(index) / 44_100
                    real += sample * cos(phase)
                    imaginary += sample * sin(phase)
                }
                return real * real + imaginary * imaginary
            }
            let lowBand = stride(from: 200.0, through: 1500.0, by: 50).map { power(at: $0) }.reduce(0, +)
            let highBand = stride(from: 2000.0, through: 8000.0, by: 50).map { power(at: $0) }.reduce(0, +)
            precondition(highBand / lowBand < 0.02, "High-frequency ringing must stay suppressed")
            // Check distinct pitches in the common initial 10 ms.
            crossings[sound] = (1..<441).filter { samples[$0 - 1] < 0 && samples[$0] >= 0 }.count
            if CommandLine.arguments.count >= 2 {
                let regenerated = URL(fileURLWithPath: CommandLine.arguments[1])
                    .appendingPathComponent(sound.rawValue + ".wav")
                let regeneratedData = try Data(contentsOf: regenerated)
                precondition(regeneratedData == data, "Bundled sound must match the original generator")
            }
            if CommandLine.arguments.count == 3 {
                let previousURL = URL(fileURLWithPath: CommandLine.arguments[2])
                    .appendingPathComponent(sound.rawValue + ".wav")
                let previous = try Data(contentsOf: previousURL)
                precondition(previous.count == data.count && previous.prefix(44) == data.prefix(44))
                for offset in stride(from: 44, to: data.count, by: 2) {
                    let oldBits = UInt16(previous[offset]) | (UInt16(previous[offset + 1]) << 8)
                    let oldSample = Int(Int16(bitPattern: oldBits))
                    let newSample = Int(Int16(bitPattern: UInt16(u16(offset))))
                    precondition(abs(newSample - oldSample * 2) <= 1,
                                 "Only double amplitude (+6 dB), preserve pitch/duration/envelope within PCM rounding")
                }
            }
        }
        precondition(crossings[.character]! > crossings[.operation]!)
        precondition(crossings[.operation]! > crossings[.deletion]!)
        print("Click checks passed: 10 key roles, OFF/full-access/fallback/interruption routing, PCM headers, duration, levels, envelope, high-frequency suppression, distinct pitches, optional reproducibility")
    }
}
