import Foundation

@main
private struct CatRunMotionTests {
    static func main() {
        #if canImport(CoreGraphics)
        for height: CGFloat in [32, 40] {
            for width: CGFloat in [280, 358, 812] {
                let bar = CGRect(x: 6, y: 8, width: width, height: height)
                let keyboard = CGRect(x: 0, y: 0, width: width + 12, height: height == 32 ? 216 : 352)
                let pose = CatCelebrationLayout.frame(in: bar)
                precondition(pose.width == CatCelebrationLayout.normalSide(barHeight: height) * 2)
                precondition(pose.height == pose.width, "Uniform 2x enlargement")
                precondition(pose.minY == bar.minY + 1 && pose.minX >= bar.minX)
                precondition(pose.maxY > bar.maxY, "The pose must grow down over keys, not above the bar")
                precondition(keyboard.contains(pose), "No extra keyboard height is needed")
                precondition(pose.maxX <= bar.maxX - 8)
                precondition(pose.minX >= bar.maxX - CatCelebrationLayout.trailingInset(barHeight: height),
                             "The celebration must not overlap the candidate strip")
            }
        }
        #endif
        precondition(CatHuntMotion.frameCount == 9)
        precondition(Set(CatHuntMotion.sequence) == Set(0..<9), "All nine distinct poses must be used")
        var aim = CatHuntMotion()
        precondition(aim.frameIndex == 0)
        precondition(aim.advance(by: 1.1 / 24, energy: 1) == 1)
        precondition(aim.advance(by: 2 / 24, energy: 1) == 3)
        precondition(aim.advance(by: 1 / 24, energy: 1) == 2, "Return through intermediate poses")
        aim.reset()
        precondition(aim.frameIndex == 0)
        var low = CatHuntMotion(), high = CatHuntMotion()
        precondition(low.advance(by: 0.13, energy: 0) == 1)
        precondition(high.advance(by: 0.13, energy: 1) == 3)
        var coarse = CatHuntMotion(), fine = CatHuntMotion()
        _ = coarse.advance(by: 0.713, energy: 0.4)
        for _ in 0..<100 { _ = fine.advance(by: 0.00713, energy: 0.4) }
        precondition(coarse.frameIndex == fine.frameIndex, "Cadence must not change the pose")
        aim.reset()
        _ = aim.advance(by: 0.06, energy: 1)
        precondition(aim.advance(by: 0.06, energy: 0) == 2, "Decaying energy preserves animation phase")
        let previousFrame = aim.frameIndex
        for delta in [Double.nan, .infinity, -.infinity, -1, 0] {
            precondition(aim.advance(by: delta, energy: 1) == previousFrame)
        }
        for energy in [Double.nan, .infinity, -.infinity, -1, 2] {
            precondition((0..<9).contains(aim.advance(by: .greatestFiniteMagnitude, energy: energy)))
        }
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
        print("Cat motion checks passed: nine drawn anticipation poses, cadence, phase continuity, reset, energy, travel, capture, two-second still gaze, fade, completion, invalid values")
    }
}
