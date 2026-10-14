// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kiyoka Nishiyama
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// Deterministic original sound design, not a recording/copy of Apple's sounds.
/// Build with SumibiKeyboard/KeyClickSound.swift; pass an output directory.
@main
private struct GenerateKeyClickSounds {
    static let sampleRate = 44_100

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: generate-key-click-sounds OUTPUT_DIRECTORY")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for sound in KeyClickSound.allCases {
            let (frequency, duration): (Double, Double) = switch sound {
            case .character: (450, 0.022)
            case .deletion: (260, 0.028)
            case .operation: (350, 0.025)
            }
            let count = Int(Double(sampleRate) * duration)
            var randomState: UInt32 = 0x53554D49
            var filteredNoise = 0.0
            let noiseFilter = 1 - exp(-2 * Double.pi * 1200 / Double(sampleRate))
            var samples = [Int16]()
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                // A short attack/tail prevents hard discontinuities and loud pops.
                let attack = min(1, time / 0.0012)
                let tail = min(1, Double(count - 1 - index) / (Double(sampleRate) * 0.003))
                let envelope = attack * tail * exp(-time / 0.0032)
                randomState = 1664525 &* randomState &+ 1013904223
                let noise = Double(randomState) / Double(UInt32.max) * 2 - 1
                // Remove the bright overtone; filter noise and damp quickly so
                // repeated taps feel like soft knocks rather than ringing beeps.
                filteredNoise += noiseFilter * (noise - filteredNoise)
                let wave = 0.82 * sin(2 * .pi * frequency * time) + 0.18 * filteredNoise
                // +6 dB relative to the first muted version, with ample headroom.
                samples.append(Int16((wave * envelope * 0.40 * Double(Int16.max)).rounded()))
            }
            var data = Data()
            func text(_ value: String) { data.append(contentsOf: value.utf8) }
            func uint16(_ value: UInt16) {
                data.append(UInt8(value & 255)); data.append(UInt8(value >> 8))
            }
            func uint32(_ value: UInt32) {
                uint16(UInt16(value & 65535)); uint16(UInt16(value >> 16))
            }
            let byteCount = UInt32(samples.count * 2)
            text("RIFF"); uint32(36 + byteCount); text("WAVE")
            text("fmt "); uint32(16); uint16(1); uint16(1)
            uint32(UInt32(sampleRate)); uint32(UInt32(sampleRate * 2)); uint16(2); uint16(16)
            text("data"); uint32(byteCount)
            for sample in samples { uint16(UInt16(bitPattern: sample)) }
            try data.write(to: directory.appendingPathComponent(sound.rawValue + ".wav"), options: .atomic)
            print("\(sound.rawValue).wav: \(data.count) bytes, \(frequency) Hz, \(duration * 1000) ms")
        }
    }
}
