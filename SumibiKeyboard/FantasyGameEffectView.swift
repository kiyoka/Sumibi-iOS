import Foundation

/// No input text: the same energy controls travel, size and a time-based fade.
struct FantasyShotMotion {
    let energy: Double
    let anticipation: Double = 0.12
    var travelDuration: Double { 0.85 - 0.2 * energy }
    var duration: Double { anticipation + travelDuration + 0.28 }

    init(energy: Double) {
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

#if canImport(UIKit)
import UIKit
import ImageIO

/// A rotating white magic circle, behind existing candidates.
@MainActor
final class FantasyGameEffectView: UIView {
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
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        sprite = Self.loadSprite("RPGWizard")
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        chargeTrack.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        chargeFill.colors = [accent.cgColor, UIColor.systemCyan.cgColor]
        chargeFill.startPoint = CGPoint(x: 0, y: 0.5)
        chargeFill.endPoint = CGPoint(x: 1, y: 0.5)
        chargeFill.masksToBounds = true
        layer.addSublayer(chargeTrack)
        layer.addSublayer(chargeFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var accent: UIColor { .systemPurple }
    private let gaugeStart: CGFloat = 78
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
        updateGauge(animated: animated && !UIAccessibility.isReduceMotionEnabled)
        refreshUpdates()
        setNeedsDisplay()
    }

    func releaseEnergy(_ level: Double) {
        stop()
        guard level.isFinite, level > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        shot = FantasyShotMotion(energy: level)
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
        updateGauge(animated: false)
        setNeedsDisplay()
    }

    func reduceMotionChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            shot = nil
            cancelTime = nil
            rotation = 0
        }
        refreshUpdates()
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func refreshUpdates() {
        guard !UIAccessibility.isReduceMotionEnabled,
              shot != nil || charge > 0 else { stopUpdates(); return }
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
        // Slow continuous rotation; no flashing full-screen effects.
        rotation = CGFloat((now - idleStartTime).truncatingRemainder(dividingBy: 12)) * .pi / 6
        refreshUpdates()
        setNeedsDisplay()
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
        sprite?.draw(in: characterRect)
        context.restoreGState()
        let cancellation = cancelTime.map { max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28)) } ?? 1
        if let shot {
            context.saveGState()
            context.setAlpha(CGFloat(shot.opacity(at: elapsed)) * cancellation)
            drawMagic(in: context, level: energy, firing: true, progress: CGFloat(shot.progress(at: elapsed)))
            context.restoreGState()
        } else if charge > 0 {
            drawMagic(in: context, level: charge, firing: false, progress: 0)
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
