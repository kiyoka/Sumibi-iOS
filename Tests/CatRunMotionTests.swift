import Foundation

@main
private struct CatRunMotionTests {
    static func main() {
        let slow = CatRunMotion(energy: 0.1)
        let fast = CatRunMotion(energy: 1)
        precondition(fast.duration < slow.duration)
        precondition(fast.pose(at: 0).progress == 0)
        precondition(fast.pose(at: 0.04).progress == 0, "Brief anticipation precedes the run")
        precondition(fast.pose(at: 0.4).progress > slow.pose(at: 0.4).progress)
        var previous = 0.0
        for frame in 0...Int(ceil(fast.duration * 60) + 1) {
            let pose = fast.pose(at: Double(frame) / 60)
            precondition(pose.progress >= previous && pose.progress <= 1)
            precondition((0...1).contains(pose.opacity))
            precondition((0..<4).contains(pose.frameIndex))
            previous = pose.progress
        }
        precondition(fast.pose(at: fast.duration - 0.2).progress == 1)
        precondition(fast.pose(at: fast.duration).finished)
        precondition(fast.pose(at: fast.duration).opacity == 0)
        precondition(fast.pose(at: fast.captureTime - 0.001).phase == .running)
        precondition(fast.pose(at: fast.captureTime).phase == .holding)
        precondition(fast.holdDuration == 2 && slow.holdDuration == 2)
        for motion in [slow, fast] {
            for offset in [0.0, 0.5, 1.5, 1.999] {
                let pose = motion.pose(at: motion.captureTime + offset)
                precondition(pose.phase == .holding && pose.progress == 1)
                precondition(pose.opacity == 1 && pose.frameIndex == 0, "Gaze must remain still and visible")
                precondition(!pose.finished)
            }
            precondition(motion.pose(at: motion.fadeStart).phase == .fading)
            let fading = motion.pose(at: motion.fadeStart + 0.09)
            precondition(fading.opacity > 0.45 && fading.opacity < 0.55)
            precondition(fading.progress == 1 && !fading.finished)
        }
        precondition(fast.pose(at: -.infinity).progress == 0)
        precondition(fast.pose(at: .nan).progress == 0)
        precondition(fast.pose(at: .greatestFiniteMagnitude).finished)
        precondition((0..<4).contains(fast.pose(at: .greatestFiniteMagnitude).frameIndex))
        precondition(CatRunMotion(energy: .nan).energy == 0)
        precondition(CatRunMotion(energy: 2).energy == 1)
        precondition(CatRunMotion(energy: -1).energy == 0)
        print("Cat motion checks passed: energy, anticipation, travel, capture, two-second still gaze, fade, completion, invalid values")
    }
}
