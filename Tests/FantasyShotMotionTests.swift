import Foundation

@main
private struct FantasyShotMotionTests {
    static func main() {
        var sweat = ArcherSweatCycle()
        sweat.update(level: 0.79, at: 10, enabled: true)
        precondition(!sweat.isActive, "Sweat begins only near full draw")
        sweat.update(level: 0.8, at: 11, enabled: true)
        precondition(sweat.progress(at: 11) == 0, "Sweat begins before full draw")
        precondition(abs(sweat.progress(at: 11.15)! - 1.0 / 3) < 0.001)
        precondition(sweat.progress(at: 11.5) == nil, "Brief gap separates bursts")
        precondition(sweat.progress(at: 11.75) == 0)
        precondition(sweat.progress(at: 12.5) == 0, "Sweat must repeat without another keystroke")
        sweat.update(level: 0.76, at: 12.6, enabled: true)
        precondition(sweat.isActive, "Small threshold fluctuations must not restart cadence")
        sweat.update(level: 0.73, at: 12.7, enabled: true)
        precondition(!sweat.isActive && sweat.progress(at: 12.7) == nil)
        sweat.update(level: 1, at: 13, enabled: true)
        precondition(sweat.isActive)
        sweat.update(level: 1, at: 13.1, enabled: false)
        precondition(!sweat.isActive, "Release, disable and Reduce Motion stop sweat")
        sweat.update(level: .nan, at: 13.2, enabled: true)
        precondition(!sweat.isActive && sweat.progress(at: .infinity) == nil)
        sweat.update(level: 1, at: 14, enabled: true)
        sweat.reset()
        precondition(!sweat.isActive, "Theme switching must clear the cycle")
        let relaxed = ArcherDrawPose(level: 0)
        let drawn = ArcherDrawPose(level: 1)
        precondition(drawn.bowHeightRatio >= 0.9, "Bow must be about character height")
        precondition(drawn.pullRatio > relaxed.pullRatio * 5, "Full draw must be conspicuous")
        precondition(drawn.leanRatio > 0 && drawn.armPullRatio > 0)
        precondition(ArcherDrawPose.releasing(energy: 1, elapsed: 0.06).level == 1)
        precondition(abs(ArcherDrawPose.releasing(energy: 1, elapsed: 0.14).level - 0.5) < 0.001)
        precondition(ArcherDrawPose.releasing(energy: 1, elapsed: 0.22).level < 0.001)
        precondition(ArcherDrawPose(level: .nan).level == 0)
        precondition(ArcherDrawPose.releasing(energy: 1, elapsed: .greatestFiniteMagnitude).level == 0)
        for kind in [FantasyShotMotion.Kind.archer, .wizard] {
            let slow = FantasyShotMotion(kind: kind, energy: 0.1)
            let fast = FantasyShotMotion(kind: kind, energy: 1)
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
            precondition(FantasyShotMotion(kind: kind, energy: .nan).energy == 0)
            precondition(FantasyShotMotion(kind: kind, energy: 2).energy == 1)
            precondition(FantasyShotMotion(kind: kind, energy: -1).energy == 0)
        }
        print("Fantasy motion checks passed: repeated sweat near full draw, hysteresis, stop, two themes, speed, anticipation, monotonic travel, fade, finish, invalid values")
    }
}
