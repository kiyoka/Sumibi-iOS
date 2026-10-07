import Foundation

/// Timing-only state. Never receives, stores, or transmits the typed text.
public struct KeyboardGameEnergy: Sendable {
    public static let inactivityDelay: TimeInterval = 0.3
    public static let decayPerSecond: Double = 0.16
    public private(set) var level: Double = 0
    private var lastKeystroke: TimeInterval?
    private var lastUpdate: TimeInterval?

    public init() {}

    /// Genuine character/space taps only; deletion and long-press repeats are excluded.
    @discardableResult
    public mutating func recordKeystroke(at time: TimeInterval) -> Double {
        guard accepts(time) else { return level }
        let interval = lastKeystroke.map { time - $0 }
        update(at: time)
        // 1 tap/sec gives 4%; 12 taps/sec gives 12%. Slow typing loses charge
        // between taps, while a fast rhythm steadily accumulates energy.
        let tapsPerSecond = interval.map { min(12, 1 / max($0, 1.0 / 12)) } ?? 1
        let speed = max(0, (tapsPerSecond - 1) / 11)
        level = min(1, level + 0.04 + 0.08 * speed)
        lastKeystroke = time
        return level
    }

    /// Time-based decay is independent of the display/timer frame rate.
    @discardableResult
    public mutating func update(at time: TimeInterval) -> Double {
        guard accepts(time) else { return level }
        if let lastKeystroke, let lastUpdate {
            let decayStart = max(lastUpdate, lastKeystroke + Self.inactivityDelay)
            level = max(0, level - max(0, time - decayStart) * Self.decayPerSecond)
        }
        lastUpdate = time
        return level
    }

    public mutating func consume(at time: TimeInterval) -> Double {
        guard accepts(time) else { return 0 }
        update(at: time)
        let released = level
        reset()
        return released
    }

    public mutating func reset() {
        level = 0
        lastKeystroke = nil
        lastUpdate = nil
    }

    private func accepts(_ time: TimeInterval) -> Bool {
        time.isFinite && (lastUpdate.map { time >= $0 } ?? true)
    }
}
