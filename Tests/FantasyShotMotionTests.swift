import Foundation

@main
private struct FantasyShotMotionTests {
    static func main() {
        let slow = FantasyShotMotion(energy: 0.1)
        let fast = FantasyShotMotion(energy: 1)
        // Keep the existing wizard timing unchanged when removing the archer.
        precondition(fast.anticipation == 0.12)
        precondition(abs(fast.travelDuration - 0.65) < 0.001)
        precondition(abs(FantasyShotMotion(energy: 0).travelDuration - 0.85) < 0.001)
        precondition(fast.travelDuration < slow.travelDuration)
        precondition(fast.progress(at: 0) == 0)
        precondition(fast.progress(at: fast.anticipation / 2) == 0)
        precondition(fast.progress(at: 0.4) > slow.progress(at: 0.4))
        for motion in [slow, fast] {
            var previous = 0.0
            for frame in 0...Int(ceil(motion.duration * 60) + 1) {
                let time = Double(frame) / 60
                let progress = motion.progress(at: time)
                precondition(progress >= previous && (0...1).contains(progress))
                precondition((0...1).contains(motion.opacity(at: time)))
                previous = progress
            }
            precondition(motion.progress(at: motion.duration) == 1)
            precondition(motion.opacity(at: motion.duration) == 0)
            precondition(motion.finished(at: motion.duration))
            precondition(!motion.finished(at: motion.duration - 0.001))
            precondition(abs(motion.opacity(at: motion.duration - 0.14) - 0.5) < 0.001)
            precondition(motion.progress(at: .nan) == 0)
            precondition(motion.progress(at: -.infinity) == 0)
            precondition(motion.finished(at: .greatestFiniteMagnitude))
            precondition(motion.opacity(at: .greatestFiniteMagnitude) == 0)
        }
        precondition(FantasyShotMotion(energy: .nan).energy == 0)
        precondition(FantasyShotMotion(energy: 2).energy == 1)
        precondition(FantasyShotMotion(energy: -1).energy == 0)
        print("Wizard motion checks passed: unchanged timing, speed, anticipation, monotonic travel, fade, finish, invalid values")
    }
}
