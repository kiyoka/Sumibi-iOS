import Foundation

/// No input text: the same energy controls travel, size and a time-based fade.
struct FantasyShotMotion {
    enum Kind { case archer, wizard }
    let kind: Kind
    let energy: Double
    var anticipation: Double { kind == .archer ? 0.06 : 0.12 }
    var travelDuration: Double { kind == .archer ? 0.9 - 0.3 * energy : 0.85 - 0.2 * energy }
    var duration: Double { anticipation + travelDuration + 0.28 }

    init(kind: Kind, energy: Double) {
        self.kind = kind
        self.energy = energy.isFinite ? min(1, max(0, energy)) : 0
    }

    func progress(at elapsed: Double) -> Double {
        min(1, max(0, (safeTime(elapsed) - anticipation) / travelDuration))
    }

    func opacity(at elapsed: Double) -> Double {
        min(1, max(0, (duration - safeTime(elapsed)) / 0.28))
    }

    func finished(at elapsed: Double) -> Bool { safeTime(elapsed) >= duration }
    private func safeTime(_ elapsed: Double) -> Double { elapsed.isFinite ? max(0, elapsed) : 0 }
}

/// Normalized pose keeps the large bow and draw action consistent at 32/40pt heights.
struct ArcherDrawPose {
    let level: Double
    let bowHeightRatio: Double = 0.94
    var pullRatio: Double { 0.10 + level * 0.58 }
    var leanRatio: Double { level * 0.12 }
    var armPullRatio: Double { level * 0.18 }

    init(level: Double) { self.level = level.isFinite ? min(1, max(0, level)) : 0 }

    static func releasing(energy: Double, elapsed: Double) -> ArcherDrawPose {
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let progress = min(1, max(0, (time - 0.06) / 0.16))
        let eased = progress * progress * (3 - 2 * progress)
        return ArcherDrawPose(level: ArcherDrawPose(level: energy).level * (1 - eased))
    }
}

/// Repeated bursts while the bow is strongly drawn; hysteresis avoids threshold chatter.
struct ArcherSweatCycle {
    static let period: Double = 0.75
    static let burstDuration: Double = 0.45
    private var startTime: Double?
    var isActive: Bool { startTime != nil }

    mutating func update(level: Double, at time: Double, enabled: Bool) {
        guard enabled, level.isFinite, time.isFinite else { reset(); return }
        if level < 0.74 { reset() }
        else if level >= 0.8, startTime == nil { startTime = time }
    }

    func progress(at time: Double) -> Double? {
        guard let startTime, time.isFinite, time >= startTime else { return nil }
        let elapsed = time - startTime
        guard elapsed.isFinite else { return nil }
        let phase = elapsed.truncatingRemainder(dividingBy: Self.period)
        return phase < Self.burstDuration ? phase / Self.burstDuration : nil
    }

    mutating func reset() { startTime = nil }
}

#if canImport(UIKit)
import UIKit
import ImageIO

/// An animated string/arrow or a rotating white magic circle, behind existing candidates.
@MainActor
final class FantasyGameEffectView: UIView {
    private let kind: FantasyShotMotion.Kind
    private let sprite: UIImage?
    private let chargeTrack = CALayer()
    private let chargeFill = CAGradientLayer()
    private var charge: CGFloat = 0
    private var shot: FantasyShotMotion?
    private var elapsed: Double = 0
    private var startTime: CFTimeInterval = 0
    private var cancelTime: CFTimeInterval?
    private var idleStartTime: CFTimeInterval = 0
    private var rotation: CGFloat = 0
    private var sweat = ArcherSweatCycle()
    private var displayLink: CADisplayLink?

    init(kind: FantasyShotMotion.Kind) {
        self.kind = kind
        sprite = Self.loadSprite(kind == .archer ? "RPGArcher" : "RPGWizard")
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        chargeTrack.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        chargeFill.colors = [accent.cgColor, (kind == .archer ? UIColor.systemYellow : UIColor.systemCyan).cgColor]
        chargeFill.startPoint = CGPoint(x: 0, y: 0.5)
        chargeFill.endPoint = CGPoint(x: 1, y: 0.5)
        chargeFill.masksToBounds = true
        layer.addSublayer(chargeTrack)
        layer.addSublayer(chargeFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var accent: UIColor { kind == .archer ? .systemTeal : .systemPurple }
    private var gaugeStart: CGFloat { kind == .wizard ? 78 : 52 }
    private var characterRect: CGRect {
        let side = max(0, min(44, bounds.height - 4))
        return CGRect(x: 2 + (44 - side) / 2, y: 1, width: side, height: side)
    }

    private static func loadSprite(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 3, orientation: .up)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGauge(animated: false)
        setNeedsDisplay()
    }

    func setCharge(_ level: Double, animated: Bool = true) {
        charge = CGFloat(level.isFinite ? min(1, max(0, level)) : 0)
        refreshSweat(at: CACurrentMediaTime())
        updateGauge(animated: animated && !UIAccessibility.isReduceMotionEnabled)
        refreshUpdates()
        setNeedsDisplay()
    }

    func releaseEnergy(_ level: Double) {
        stop()
        guard level.isFinite, level > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        shot = FantasyShotMotion(kind: kind, energy: level)
        startTime = CACurrentMediaTime()
        refreshUpdates()
        setNeedsDisplay()
    }

    func fadeRelease() {
        guard shot != nil, cancelTime == nil else { return }
        cancelTime = CACurrentMediaTime()
    }

    func stop() {
        stopUpdates()
        shot = nil
        cancelTime = nil
        charge = 0
        elapsed = 0
        rotation = 0
        sweat.reset()
        updateGauge(animated: false)
        setNeedsDisplay()
    }

    func reduceMotionChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            shot = nil
            cancelTime = nil
            rotation = 0
            sweat.reset()
        }
        refreshSweat(at: CACurrentMediaTime())
        refreshUpdates()
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func refreshUpdates() {
        guard !UIAccessibility.isReduceMotionEnabled,
              shot != nil || sweat.isActive || (kind == .wizard && charge > 0) else { stopUpdates(); return }
        guard displayLink == nil else { return }
        idleStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        elapsed = shot == nil ? 0 : now - startTime
        if shot?.finished(at: elapsed) == true || cancelTime.map({ now - $0 >= 0.28 }) == true {
            shot = nil
            cancelTime = nil
            elapsed = 0
        }
        refreshSweat(at: now)
        // Slow continuous rotation; no flashing full-screen effects.
        rotation = CGFloat((now - idleStartTime).truncatingRemainder(dividingBy: 12)) * .pi / 6
        refreshUpdates()
        setNeedsDisplay()
    }

    private func refreshSweat(at time: Double) {
        sweat.update(level: Double(charge), at: time,
                     enabled: kind == .archer && shot == nil && !UIAccessibility.isReduceMotionEnabled)
    }

    private func updateGauge(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.12)
        let width = max(0, bounds.width - gaugeStart - 6)
        chargeTrack.frame = CGRect(x: gaugeStart, y: bounds.height - 5, width: width, height: 4)
        chargeFill.frame = CGRect(x: gaugeStart, y: bounds.height - 5, width: width * charge, height: 4)
        chargeTrack.cornerRadius = 2
        chargeFill.cornerRadius = 2
        CATransaction.commit()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !bounds.isEmpty else { return }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        let energy = CGFloat(shot?.energy ?? 0)
        let recoil = shot == nil ? 0 : -sin(min(1, elapsed / 0.3) * .pi) * Double(2 + energy * 3)
        context.saveGState()
        context.translateBy(x: CGFloat(recoil), y: 0)
        if kind == .archer {
            let pose = shot.map { ArcherDrawPose.releasing(energy: $0.energy, elapsed: elapsed) }
                ?? ArcherDrawPose(level: Double(charge))
            drawArcher(in: context, pose: pose)
            drawBow(in: context, pose: pose)
            drawSweat(in: context, pose: pose)
        } else { sprite?.draw(in: characterRect) }
        context.restoreGState()
        let cancellation = cancelTime.map { max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28)) } ?? 1
        if let shot {
            context.saveGState()
            context.setAlpha(CGFloat(shot.opacity(at: elapsed)) * cancellation)
            if kind == .archer { drawFlyingArrows(in: context, shot: shot) }
            else { drawMagic(in: context, level: energy, firing: true, progress: CGFloat(shot.progress(at: elapsed))) }
            context.restoreGState()
        } else if kind == .wizard, charge > 0 {
            drawMagic(in: context, level: charge, firing: false, progress: 0)
        }
    }

    private func drawSweat(in context: CGContext, pose: ArcherDrawPose) {
        guard let phase = sweat.progress(at: CACurrentMediaTime()) else { return }
        let progress = CGFloat(phase)
        let rect = characterRect
        let headX = rect.minX + rect.width * (0.48 - CGFloat(pose.leanRatio) * 0.7)
        let headY = rect.minY + rect.height * 0.22
        context.saveGState()
        context.setAlpha(min(1, (1 - progress) / 0.35))
        for side: CGFloat in [-1, 1] {
            let x = floor(headX + side * (rect.width * 0.23 + progress * 5))
            let y = floor(max(2, headY - progress * 5))
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fill(CGRect(x: x, y: y, width: 3, height: 4))
            context.fill(CGRect(x: x + 1, y: y - 1, width: 1, height: 1))
            context.setFillColor(UIColor.systemCyan.cgColor)
            context.fill(CGRect(x: x + 1, y: y, width: 1, height: 3))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: x + 1, y: y, width: 1, height: 1))
        }
        context.restoreGState()
    }

    private func drawArcher(in context: CGContext, pose: ArcherDrawPose) {
        guard let sprite else { return }
        guard pose.level > 0 else { sprite.draw(in: characterRect); return }
        func posed(_ point: CGPoint) -> CGPoint {
            let arm = exp(-pow((Double(point.x) - 0.36) / 0.20, 2)
                          - pow((Double(point.y) - 0.52) / 0.075, 2))
            let lean = pose.leanRatio * max(0, Double(0.92 - point.y))
            let x = Double(point.x) - lean - arm * pose.armPullRatio
            return CGPoint(x: characterRect.minX + CGFloat(x) * characterRect.width,
                           y: characterRect.minY + point.y * characterRect.height)
        }
        // Connected triangles pull the rear forearm while keeping the feet planted.
        for row in 0..<8 {
            for column in 0..<8 {
                let x = CGFloat(column) / 8, y = CGFloat(row) / 8, step: CGFloat = 1 / 8
                let a = CGPoint(x: x, y: y), b = CGPoint(x: x + step, y: y)
                let c = CGPoint(x: x, y: y + step), d = CGPoint(x: x + step, y: y + step)
                for (a, b, c) in [(a, b, c), (d, c, b)] {
                    let p = posed(a), q = posed(b), r = posed(c)
                    let det = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
                    let xx = ((q.x - p.x) * (c.y - a.y) - (r.x - p.x) * (b.y - a.y)) / det
                    let xy = ((r.x - p.x) * (b.x - a.x) - (q.x - p.x) * (c.x - a.x)) / det
                    let yx = ((q.y - p.y) * (c.y - a.y) - (r.y - p.y) * (b.y - a.y)) / det
                    let yy = ((r.y - p.y) * (b.x - a.x) - (q.y - p.y) * (c.x - a.x)) / det
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
                    sprite.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    context.restoreGState()
                }
            }
        }
    }

    private func drawBow(in context: CGContext, pose: ArcherDrawPose) {
        let rect = characterRect
        let level = CGFloat(pose.level)
        let x = rect.minX + rect.width * 0.88
        let y = rect.minY + rect.height * 0.51
        let pull = rect.width * CGFloat(pose.pullRatio)
        let top = CGPoint(x: x - rect.width * (0.08 + level * 0.08), y: rect.minY + rect.height * 0.02)
        let bottom = CGPoint(x: top.x, y: top.y + rect.height * CGFloat(pose.bowHeightRatio))
        let limb = CGMutablePath()
        limb.move(to: top)
        limb.addQuadCurve(to: CGPoint(x: x, y: y),
                          control: CGPoint(x: x + rect.width * 0.12, y: rect.minY + rect.height * 0.28))
        limb.addQuadCurve(to: bottom,
                          control: CGPoint(x: x + rect.width * 0.12, y: rect.minY + rect.height * 0.76))
        context.addPath(limb)
        context.setStrokeColor(UIColor(red: 0.33, green: 0.18, blue: 0.08, alpha: 1).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.addPath(limb)
        context.setStrokeColor(UIColor(red: 0.9, green: 0.58, blue: 0.22, alpha: 1).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()
        let string = CGMutablePath()
        string.move(to: top)
        string.addLine(to: CGPoint(x: x - pull, y: y))
        string.addLine(to: bottom)
        context.addPath(string)
        context.setStrokeColor(UIColor.systemBrown.cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.addPath(string)
        context.setStrokeColor(UIColor(red: 1, green: 0.88, blue: 0.6, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        if level > 0 {
            drawArrow(in: context, tip: CGPoint(x: x + 5, y: y), length: pull + 5, energy: level)
        }
    }

    private func drawArrow(in context: CGContext, tip: CGPoint, length: CGFloat, energy: CGFloat) {
        context.setFillColor(UIColor.systemBrown.cgColor)
        context.fill(CGRect(x: tip.x - length, y: tip.y - 1, width: length - 2, height: 2))
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fill(CGRect(x: tip.x - length, y: tip.y - 0.5, width: length - 2, height: 1))
        context.setFillColor(UIColor.systemTeal.cgColor)
        for dy in [-2.0, 1.0] {
            context.fill(CGRect(x: tip.x - length, y: tip.y + dy, width: 4, height: 1))
        }
        let head = CGMutablePath()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - 5, y: tip.y - 2 - energy))
        head.addLine(to: CGPoint(x: tip.x - 5, y: tip.y + 2 + energy))
        head.closeSubpath()
        context.addPath(head)
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fillPath()
    }

    private func drawFlyingArrows(in context: CGContext, shot: FantasyShotMotion) {
        guard elapsed >= shot.anticipation else { return }
        let energy = CGFloat(shot.energy)
        let travel = CGFloat(shot.progress(at: elapsed))
        let start: CGFloat = characterRect.maxX - 3
        let x = start + max(0, bounds.width - start - 6) * travel
        let y = characterRect.midY
        let count = energy >= 0.75 ? 3 : 1
        for index in 0..<count {
            let dy: CGFloat = index == 0 ? 0 : index == 1 ? -5 : 5
            let tip = CGPoint(x: x - CGFloat(index) * 5, y: y + dy)
            context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.15 + energy * 0.2).cgColor)
            context.fill(CGRect(x: tip.x - 18 - energy * 24, y: tip.y - 1,
                                width: 20 + energy * 24, height: 2))
            drawArrow(in: context, tip: tip, length: 16 + energy * 10, energy: energy)
        }
    }

    private func drawMagic(in context: CGContext, level: CGFloat, firing: Bool, progress: CGFloat) {
        let center = CGPoint(x: 55, y: characterRect.midY)
        let radius = min(max(0, (bounds.height - 8) / 2), 8 + level * 9)
        guard radius > 0 else { return }
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: rotation)
        let circle = CGMutablePath()
        for ratio in [1.0, 0.74] {
            let r = radius * ratio
            circle.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        }
        // Two triangles and six geometric rune ticks; no borrowed symbols or artwork.
        for offset in [CGFloat.zero, CGFloat.pi] {
            for index in 0..<3 {
                let angle = offset + CGFloat(index) * .pi * 2 / 3
                let point = CGPoint(x: cos(angle) * radius * 0.69, y: sin(angle) * radius * 0.69)
                if index == 0 { circle.move(to: point) } else { circle.addLine(to: point) }
            }
            circle.closeSubpath()
        }
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3
            circle.move(to: CGPoint(x: cos(angle) * radius * 0.82, y: sin(angle) * radius * 0.82))
            circle.addLine(to: CGPoint(x: cos(angle) * radius * 0.95, y: sin(angle) * radius * 0.95))
        }
        context.setShouldAntialias(true)
        context.addPath(circle)
        context.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(2.8)
        context.strokePath()
        context.addPath(circle)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.1)
        context.strokePath()
        context.restoreGState()
        context.setShouldAntialias(false)
        if !firing {
            let core = 2 + level * 3
            context.setFillColor(UIColor.systemPurple.cgColor)
            context.fill(CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: center.x - core + 1, y: center.y - 1, width: core * 2 - 2, height: 2))
            return
        }
        guard elapsed >= (shot?.anticipation ?? 0) else { return }
        let end = center.x + max(0, bounds.width - center.x - 6) * progress
        let thickness = 3 + level * 9
        context.setFillColor(UIColor.systemPurple.withAlphaComponent(0.45).cgColor)
        context.fill(CGRect(x: center.x, y: center.y - thickness / 2 - 2,
                            width: max(0, end - center.x), height: thickness + 4))
        context.setFillColor(UIColor.systemCyan.withAlphaComponent(0.8).cgColor)
        context.fill(CGRect(x: center.x, y: center.y - thickness / 2,
                            width: max(0, end - center.x), height: thickness))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: center.x, y: center.y - max(1, thickness / 5),
                            width: max(0, end - center.x), height: max(2, thickness * 0.4)))
        for index in 0..<Int(3 + level * 5) {
            let fraction = CGFloat(index + 1) / 9
            let x = center.x + max(0, end - center.x) * fraction
            let offset = CGFloat(sin(elapsed * 5 + Double(index) * 1.5)) * (4 + level * 7)
            context.fill(CGRect(x: floor(x), y: floor(center.y + offset), width: 2, height: 2))
        }
    }
}
#endif
