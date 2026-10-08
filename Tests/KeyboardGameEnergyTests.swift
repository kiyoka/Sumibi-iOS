import Foundation

@main
private struct KeyboardGameEnergyTests {
    static func main() {
        var slow = KeyboardGameEnergy()
        var medium = KeyboardGameEnergy()
        var fast = KeyboardGameEnergy()
        precondition(KeyboardGameEnergy.decayPerSecond == 0.16, "Idle drain must be half the original speed")
        precondition(fast.level == 0)
        for index in 0..<8 {
            slow.recordKeystroke(at: Double(index))
            medium.recordKeystroke(at: Double(index) * 0.25)
            fast.recordKeystroke(at: Double(index) * 0.1)
        }
        precondition(fast.level > medium.level && medium.level > slow.level,
                     "Faster typing must charge more across multiple rhythms")
        precondition(abs(slow.level - 0.04) < 0.00001, "Slow taps should lose charge between taps")
        let retained = fast.level
        fast.update(at: 0.9)
        precondition(abs(fast.level - retained) < 0.00001, "A short pause must not drain charge")
        var fading = fast
        fading.update(at: 1.1)
        precondition(abs(fading.level - (retained - 0.016)) < 0.00001, "Drain should start after the grace period")
        fading.update(at: 1.2)
        precondition(abs(fading.level - (retained - 0.032)) < 0.00001, "Drain must continue smoothly")
        fading.update(at: 100)
        precondition(fading.level == 0, "An idle meter must eventually empty, not become negative")
        let released = fast.consume(at: 0.9)
        precondition(released == retained && fast.level == 0, "Conversion must consume all charge")
        precondition(fast.consume(at: 1) == 0, "Additional candidates/retry must not create energy")
        fast.recordKeystroke(at: 10)
        precondition(abs(fast.level - 0.04) < 0.00001, "Consumption must reset rhythm")
        fast.recordKeystroke(at: 10.1)
        let beforeInvalid = fast.level
        fast.recordKeystroke(at: .nan)
        fast.recordKeystroke(at: .infinity)
        fast.recordKeystroke(at: 9)
        fast.update(at: .nan)
        fast.update(at: .infinity)
        fast.update(at: 9)
        precondition(fast.consume(at: .nan) == 0)
        precondition(fast.consume(at: 9) == 0)
        precondition(fast.level == beforeInvalid, "Invalid times must not affect energy")
        for index in 0..<1000 { fast.recordKeystroke(at: 11 + Double(index) * 0.1) }
        precondition(fast.level == 1, "Charge must be capped")
        let lastTap = 11 + Double(999) * 0.1
        var coarse = fast
        var fine = fast
        coarse.update(at: lastTap + 2)
        for frame in 1...60 { fine.update(at: lastTap + Double(frame) / 30) }
        precondition(abs(coarse.level - fine.level) < 0.00001,
                     "Decay must not depend on the timer frame rate")
        precondition(abs(coarse.level - 0.728) < 0.00001)
        var halfSpeed = fast
        halfSpeed.update(at: lastTap + 3.425)
        precondition(abs(halfSpeed.level - 0.5) < 0.00001, "Half a full meter drains in 3.125 seconds after grace")
        halfSpeed.update(at: lastTap + 6.56)
        precondition(halfSpeed.level == 0, "A full meter should empty after about 6.55 seconds including grace")
        var lateConversion = fast
        let lateRelease = lateConversion.consume(at: lastTap + 1.3)
        precondition(abs(lateRelease - 0.84) < 0.00001,
                     "Conversion must use the energy at tap time, even without a recent timer tick")
        precondition(lateConversion.level == 0)
        fast.reset()
        precondition(fast.level == 0, "Keyboard dismissal/disable must reset charge")
        fast.recordKeystroke(at: 5000)
        precondition(abs(fast.level - 0.04) < 0.00001)
        print("Game energy checks passed: speed, idle grace, continuous decay, frame-rate independence, cap, timed consumption, reset, invalid clocks")
    }
}
