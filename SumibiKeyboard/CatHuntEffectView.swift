import Foundation

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
    private var aimStartTime: CFTimeInterval = 0
    private var cancelStartTime: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var holdTimer: Timer?
    private var hasCapturedPrey = false

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
                cat.showHunting(wiggle: 0)
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
        cat.showHunting(wiggle: 0)
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
        aimStartTime = CACurrentMediaTime()
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
        cat.showHunting(wiggle: 0)
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
            let wiggle = sin((now - aimStartTime) * .pi * 2 * (1.7 + Double(charge) * 1.8))
            cat.showHunting(wiggle: CGFloat(wiggle) * (0.035 + charge * 0.045))
        }
        setNeedsDisplay()
    }

    private func layoutCat() {
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
            // Match the caught sprite: colorful sewn fabric, never a living animal.
            let x = max(0, bounds.width - 23)
            let y = floor(bounds.height * 0.62 / 2) * 2
            context.setFillColor(UIColor.systemCyan.cgColor)
            context.fill(CGRect(x: x, y: y, width: 14, height: 8))
            context.setFillColor(UIColor.systemPink.cgColor)
            context.fill(CGRect(x: x + 2, y: y, width: 2, height: 8))
            context.fill(CGRect(x: x + 10, y: y, width: 2, height: 8))
            context.setFillColor(UIColor.systemBlue.cgColor)
            for offset in stride(from: 4, through: 8, by: 2) {
                context.fill(CGRect(x: x + CGFloat(offset), y: y + 4, width: 1, height: 1))
            }
            context.setFillColor(UIColor.systemYellow.cgColor)
            context.fill(CGRect(x: x + 14, y: y + 3, width: 4, height: 1))
            context.fill(CGRect(x: x + 17, y: y + 3, width: 1, height: 5))
            context.fill(CGRect(x: x + 14, y: y + 7, width: 4, height: 1))
            context.fill(CGRect(x: x + 14, y: y + 5, width: 1, height: 2))
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

/// Raised-tail running poses are bitmap frames; a connected mesh wiggles only the rear.
@MainActor
private final class HuntingCatSpriteView: UIView {
    private let hunting = HuntingCatSpriteView.loadSprite("PersianCatHunt", size: 64)
    private let caught = HuntingCatSpriteView.loadSprite("PersianCatCatch", size: 64)
    private let running = HuntingCatSpriteView.loadRunFrames()
    private var wiggle: CGFloat = 0
    private var frameIndex: Int?
    private var hasCaughtPrey = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showHunting(wiggle: CGFloat) {
        hasCaughtPrey = false
        frameIndex = nil
        self.wiggle = wiggle
        setNeedsDisplay()
    }

    func showRunning(frameIndex: Int) {
        hasCaughtPrey = false
        self.frameIndex = frameIndex
        wiggle = 0
        setNeedsDisplay()
    }

    func showCaughtPrey() {
        guard !hasCaughtPrey else { return }
        hasCaughtPrey = true
        frameIndex = nil
        wiggle = 0
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

    private var imageRect: CGRect {
        let side = min(bounds.width, bounds.height)
        return CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                      width: side, height: side)
    }

    private func posedPoint(_ point: CGPoint) -> CGPoint {
        // The enlarged face occupies the right half; keep its features out of the rump mesh.
        let rear = max(0, min(1, (0.42 - point.x) / 0.22))
            * max(0, min(1, (0.96 - point.y) / 0.18))
        return CGPoint(x: imageRect.minX + (point.x + rear * wiggle) * imageRect.width,
                       y: imageRect.minY + (point.y - rear * abs(wiggle) * 0.18) * imageRect.height)
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
        guard let hunting else { return }
        guard wiggle != 0 else { hunting.draw(in: imageRect); return }
        for row in 0..<8 {
            for column in 0..<8 {
                let x = CGFloat(column) / 8, y = CGFloat(row) / 8, step: CGFloat = 1 / 8
                let a = CGPoint(x: x, y: y), b = CGPoint(x: x + step, y: y)
                let c = CGPoint(x: x, y: y + step), d = CGPoint(x: x + step, y: y + step)
                drawTriangle(a, b, c, image: hunting, context: context)
                drawTriangle(d, c, b, image: hunting, context: context)
            }
        }
    }

    private func drawTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint,
                              image: UIImage, context: CGContext) {
        let p = posedPoint(a), q = posedPoint(b), r = posedPoint(c)
        let determinant = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        let xx = ((q.x - p.x) * (c.y - a.y) - (r.x - p.x) * (b.y - a.y)) / determinant
        let xy = ((r.x - p.x) * (b.x - a.x) - (q.x - p.x) * (c.x - a.x)) / determinant
        let yx = ((q.y - p.y) * (c.y - a.y) - (r.y - p.y) * (b.y - a.y)) / determinant
        let yy = ((r.y - p.y) * (b.x - a.x) - (q.y - p.y) * (c.x - a.x)) / determinant
        context.saveGState()
        context.beginPath()
        context.move(to: p)
        context.addLine(to: q)
        context.addLine(to: r)
        context.closePath()
        context.clip()
        context.concatenate(CGAffineTransform(a: xx, b: yx, c: xy, d: yy,
                                              tx: p.x - xx * a.x - xy * a.y,
                                              ty: p.y - yx * a.x - yy * a.y))
        image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        context.restoreGState()
    }
}
#endif
