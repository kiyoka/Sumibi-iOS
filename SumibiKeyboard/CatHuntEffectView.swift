import Foundation

/// Distinct, hand-drawn poses. Integrating the playhead avoids jumps as energy decays.
struct CatHuntMotion {
    static let frameCount = 9
    static let sequence = [0, 1, 2, 3, 2, 1, 4, 5, 6, 7, 6, 5, 8, 4]
    private var playhead: Double = 0
    var frameIndex: Int { Self.sequence[Int(playhead)] }

    mutating func advance(by elapsed: Double, energy: Double) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return frameIndex }
        let level = energy.isFinite ? min(1, max(0, energy)) : 0
        let rate = 12 + 12 * level
        let count = Double(Self.sequence.count)
        let step = elapsed.truncatingRemainder(dividingBy: count / rate) * rate
        playhead = (playhead + step).truncatingRemainder(dividingBy: count)
        return frameIndex
    }

    mutating func reset() { playhead = 0 }
}

/// Time-based dash geometry is independent of display cadence and contains no input text.
struct CatRunMotion {
    enum Phase { case running, holding, fading, finished }

    struct Pose {
        let progress: Double
        let opacity: Double
        let frameIndex: Int
        let phase: Phase
        var finished: Bool { phase == .finished }
    }

    let energy: Double
    var captureTime: Double { 1.03 - 0.35 * energy }
    let holdDuration: Double = 2
    var fadeStart: Double { captureTime + holdDuration }
    var duration: Double { fadeStart + 0.18 }

    init(energy: Double) {
        self.energy = energy.isFinite ? min(1, max(0, energy)) : 0
    }

    func pose(at elapsed: Double) -> Pose {
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let phase: Phase = time >= duration ? .finished : time >= fadeStart ? .fading
            : time >= captureTime ? .holding : .running
        let strideTime = max(0, min(captureTime, time) - 0.08)
        let progress = phase == .running ? pow(min(1, strideTime / (captureTime - 0.08)), 1.35) : 1
        let frameIndex = phase == .running
            ? Int((strideTime * (10 + 8 * energy)).truncatingRemainder(dividingBy: 4)) : 0
        return Pose(progress: progress, opacity: min(1, max(0, (duration - time) / 0.18)),
                    frameIndex: frameIndex, phase: phase)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

/// Reserve space inside the keyboard, rather than drawing into the host app above it.
enum CatCelebrationLayout {
    static func normalSide(barHeight: CGFloat) -> CGFloat { max(0, min(44, barHeight - 4)) }
    static func extraTopSpace(barHeight: CGFloat) -> CGFloat { normalSide(barHeight: barHeight) }
    static func trailingInset(barHeight: CGFloat) -> CGFloat { normalSide(barHeight: barHeight) * 2 + 16 }
    static func frame(in bar: CGRect) -> CGRect {
        let side = normalSide(barHeight: bar.height) * 2
        return CGRect(x: bar.maxX - 8 - side, y: bar.maxY - 3 - side, width: side, height: side)
    }
}

enum CatHuntSpriteSheet {
    static func frames(from sheet: CGImage) -> [CGImage] {
        guard sheet.width == sheet.height, sheet.width % 3 == 0 else { return [] }
        let side = sheet.width / 3
        let frames = (0..<CatHuntMotion.frameCount).compactMap { index -> CGImage? in
            guard let cell = sheet.cropping(to: CGRect(x: index % 3 * side, y: index / 3 * side,
                                                       width: side, height: side)),
                  let bounds = visibleBounds(of: cell) else { return nil }
            return cell.cropping(to: bounds)
        }
        return frames.count == CatHuntMotion.frameCount ? frames : []
    }

    private static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Keep raw bitmap row order aligned with CGImage.cropping coordinates.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 50 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
#endif

#if canImport(UIKit)
import UIKit
import ImageIO

@MainActor
final class CatHuntEffectView: UIView {
    private let cat = HuntingCatSpriteView()
    private let chargeTrack = CALayer()
    private let chargeFill = CAGradientLayer()
    private var charge: CGFloat = 0
    private var run: CatRunMotion?
    private var runProgress: CGFloat = 0
    private var runOpacity: CGFloat = 1
    private var runStartTime: CFTimeInterval = 0
    private var aimLastTime: CFTimeInterval = 0
    private var aimMotion = CatHuntMotion()
    private var cancelStartTime: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var holdTimer: Timer?
    weak var celebrationHost: UIView? {
        didSet { layoutCat() }
    }
    var onCelebrationChanged: ((Bool) -> Void)?
    private var hasCapturedPrey = false {
        didSet {
            if oldValue != hasCapturedPrey { onCelebrationChanged?(hasCapturedPrey) }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(cat)
        chargeTrack.backgroundColor = UIColor.systemPink.withAlphaComponent(0.15).cgColor
        chargeFill.colors = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor]
        chargeFill.startPoint = CGPoint(x: 0, y: 0.5)
        chargeFill.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(chargeTrack)
        layer.addSublayer(chargeFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCat()
        updateGauge(animated: false)
    }

    func setCharge(_ level: Double, animated: Bool = true) {
        charge = level.isFinite ? CGFloat(min(1, max(0, level))) : 0
        updateGauge(animated: animated && !UIAccessibility.isReduceMotionEnabled)
        if run == nil {
            if charge > 0, !UIAccessibility.isReduceMotionEnabled { startUpdates() }
            else {
                stopUpdates()
                aimMotion.reset()
                cat.showHunting(frameIndex: 0)
            }
        }
        setNeedsDisplay()
    }

    func releaseEnergy(_ level: Double) {
        stop()
        guard level > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        run = CatRunMotion(energy: level)
        runStartTime = CACurrentMediaTime()
        runProgress = 0
        runOpacity = 1
        cat.showRunning(frameIndex: 0)
        startUpdates()
        setNeedsDisplay()
    }

    func fadeRelease() {
        guard run != nil, cancelStartTime == nil else { return }
        cancelStartTime = CACurrentMediaTime()
        holdTimer?.invalidate()
        holdTimer = nil
        startUpdates()
    }

    func stop() {
        holdTimer?.invalidate()
        holdTimer = nil
        stopUpdates()
        run = nil
        cancelStartTime = nil
        charge = 0
        runProgress = 0
        runOpacity = 1
        hasCapturedPrey = false
        cat.layer.removeAllAnimations()
        cat.alpha = 1
        aimMotion.reset()
        cat.showHunting(frameIndex: 0)
        layoutCat()
        updateGauge(animated: false)
        setNeedsDisplay()
    }

    func reduceMotionChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            stopUpdates()
            endRun()
        } else if charge > 0 { startUpdates() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func startUpdates() {
        guard displayLink == nil else { return }
        aimLastTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func endRun() {
        holdTimer?.invalidate()
        holdTimer = nil
        run = nil
        cancelStartTime = nil
        runProgress = 0
        runOpacity = 1
        hasCapturedPrey = false
        cat.alpha = 1
        aimMotion.reset()
        aimLastTime = CACurrentMediaTime()
        cat.showHunting(frameIndex: 0)
        layoutCat()
        if charge == 0 || UIAccessibility.isReduceMotionEnabled { stopUpdates() }
        setNeedsDisplay()
    }

    @objc private func tick(_ link: CADisplayLink) {
        updateFrame()
    }

    @objc private func resumeAfterHold() {
        holdTimer = nil
        guard run != nil, cancelStartTime == nil else { return }
        startUpdates()
        updateFrame()
    }

    private func updateFrame() {
        if UIAccessibility.isReduceMotionEnabled {
            stopUpdates()
            endRun()
            return
        }
        let now = CACurrentMediaTime()
        if let run {
            let elapsed = now - runStartTime
            let pose = run.pose(at: elapsed)
            let cancellation = cancelStartTime.map { max(0, 1 - CGFloat((now - $0) / 0.28)) } ?? 1
            if pose.finished || cancellation == 0 { endRun(); return }
            runProgress = CGFloat(pose.progress)
            runOpacity = CGFloat(pose.opacity) * cancellation
            cat.alpha = runOpacity
            hasCapturedPrey = pose.phase != .running
            if hasCapturedPrey { cat.showCaughtPrey() }
            else { cat.showRunning(frameIndex: pose.frameIndex) }
            layoutCat()
            if pose.phase == .holding, cancelStartTime == nil {
                // The gaze is still: one timer wakes the fade, instead of redrawing during the hold.
                stopUpdates()
                if holdTimer == nil {
                    let timer = Timer(timeInterval: max(0.01, run.fadeStart - elapsed),
                                      target: self, selector: #selector(resumeAfterHold),
                                      userInfo: nil, repeats: false)
                    holdTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        } else {
            let frame = aimMotion.advance(by: now - aimLastTime, energy: Double(charge))
            aimLastTime = now
            cat.showHunting(frameIndex: frame)
        }
        setNeedsDisplay()
    }

    private func layoutCat() {
        if hasCapturedPrey, let celebrationHost {
            // The large sprite is a keyboard-level decoration, not part of the clipped
            // candidate/glass subtree. Keep every candidate's clipping unchanged.
            if cat.superview !== celebrationHost { celebrationHost.addSubview(cat) }
            cat.frame = convert(CatCelebrationLayout.frame(in: bounds), to: celebrationHost)
            return
        }
        if cat.superview !== self { addSubview(cat) }
        if hasCapturedPrey {
            // A standalone preview may not supply an overlay host.
            cat.frame = CatCelebrationLayout.frame(in: bounds)
            return
        }
        let distance = max(0, bounds.width - 54)
        let x = 2 + distance * runProgress
        let pixelScale = max(1, traitCollection.displayScale)
        cat.frame = CGRect(x: round(x * pixelScale) / pixelScale, y: 1,
                           width: 44, height: max(0, bounds.height - 4))
    }

    private func updateGauge(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.12)
        chargeTrack.frame = CGRect(x: 52, y: bounds.height - 5, width: max(0, bounds.width - 58), height: 4)
        chargeFill.frame = CGRect(x: 52, y: bounds.height - 5, width: max(0, bounds.width - 58) * charge, height: 4)
        chargeTrack.cornerRadius = 2
        chargeFill.cornerRadius = 2
        CATransaction.commit()
    }

    override func draw(_ rect: CGRect) {
        guard (charge > 0 || run != nil), let context = UIGraphicsGetCurrentContext() else { return }
        context.setShouldAntialias(false)
        if !hasCapturedPrey {
            // Match the caught sprite: a pink toy ball, never a living animal.
            let x = max(0, bounds.width - 22)
            let y = max(0, floor((bounds.height - 20) / 2) * 2)
            context.setFillColor(UIColor(red: 0.72, green: 0.04, blue: 0.30, alpha: 1).cgColor)
            for (row, width) in [6, 10, 14, 14, 14, 10, 6].enumerated() {
                context.fill(CGRect(x: x + CGFloat(14 - width) / 2, y: y + CGFloat(row) * 2,
                                    width: CGFloat(width), height: 2))
            }
            context.setFillColor(UIColor(red: 1, green: 0.31, blue: 0.60, alpha: 1).cgColor)
            for (row, width) in [6, 10, 10, 10, 6].enumerated() {
                context.fill(CGRect(x: x + CGFloat(14 - width) / 2, y: y + 2 + CGFloat(row) * 2,
                                    width: CGFloat(width), height: 2))
            }
            context.setFillColor(UIColor(red: 1, green: 0.69, blue: 0.83, alpha: 1).cgColor)
            context.fill(CGRect(x: x + 4, y: y + 4, width: 4, height: 2))
        }
        guard let run, runProgress > 0, !hasCapturedPrey else { return }
        context.setFillColor(UIColor.systemOrange.withAlphaComponent(runOpacity * 0.5).cgColor)
        for index in 0..<Int(1 + run.energy * 3) {
            let x = cat.frame.minX - CGFloat(index + 1) * 7
            context.fill(CGRect(x: max(0, x), y: bounds.height - 12 - CGFloat(index % 2) * 3,
                                width: 3, height: 3))
        }
    }
}

/// Both anticipation and running use hand-drawn bitmap frames, without mesh distortion.
@MainActor
final class HuntingCatSpriteView: UIView {
    private let hunting = HuntingCatSpriteView.loadSprite("PersianCatHunt", size: 64)
    private let caught = HuntingCatSpriteView.loadSprite("PersianCatCatch", size: 64)
    private let running = HuntingCatSpriteView.loadRunFrames()
    private let huntingFrames = HuntingCatSpriteView.loadHuntFrames()
    private var huntingFrameIndex = 0
    private var frameIndex: Int?
    private var hasCaughtPrey = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showHunting(frameIndex: Int) {
        let index = max(0, min(CatHuntMotion.frameCount - 1, frameIndex))
        guard hasCaughtPrey || self.frameIndex != nil || huntingFrameIndex != index else { return }
        hasCaughtPrey = false
        self.frameIndex = nil
        huntingFrameIndex = index
        setNeedsDisplay()
    }

    func showRunning(frameIndex: Int) {
        hasCaughtPrey = false
        self.frameIndex = frameIndex
        setNeedsDisplay()
    }

    func showCaughtPrey() {
        guard !hasCaughtPrey else { return }
        hasCaughtPrey = true
        frameIndex = nil
        setNeedsDisplay()
    }

    private static func loadSprite(_ name: String, size: Int) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 3, orientation: .up)
    }

    private static func loadRunFrames() -> [UIImage] {
        guard let sheet = loadSprite("PersianCatRun", size: 128)?.cgImage else { return [] }
        let width = sheet.width / 2, height = sheet.height / 2
        return (0..<4).compactMap { index in
            sheet.cropping(to: CGRect(x: (index % 2) * width, y: (index / 2) * height,
                                      width: width, height: height))
                .map { UIImage(cgImage: $0, scale: 3, orientation: .up) }
        }
    }

    private static func loadHuntFrames() -> [UIImage] {
        // Decode the whole 3x3 sheet at only 192px, then keep nine <=64px poses.
        guard let sheet = loadSprite("PersianCatAim", size: 192)?.cgImage else { return [] }
        return CatHuntSpriteSheet.frames(from: sheet).map {
            UIImage(cgImage: $0, scale: 3, orientation: .up)
        }
    }

    private var imageRect: CGRect {
        let side = min(bounds.width, bounds.height)
        return CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                      width: side, height: side)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        if hasCaughtPrey, let caught {
            caught.draw(in: imageRect)
            return
        }
        if let frameIndex, !running.isEmpty {
            running[frameIndex % running.count].draw(in: imageRect)
            return
        }
        guard !huntingFrames.isEmpty else { hunting?.draw(in: imageRect); return }
        let frame = huntingFrames[huntingFrameIndex]
        // Rigid bottom/right anchoring: no per-frame stretching or warping of the face.
        let side = huntingFrames.map { max($0.size.width, $0.size.height) }.max() ?? 1
        let scale = imageRect.width / side
        let width = frame.size.width * scale, height = frame.size.height * scale
        frame.draw(in: CGRect(x: imageRect.maxX - width, y: imageRect.maxY - height,
                              width: width, height: height))
    }
}
#endif
