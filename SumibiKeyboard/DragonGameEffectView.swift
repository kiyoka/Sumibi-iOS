import UIKit
import ImageIO

/// An opaque, small backing keeps status text readable over the optional fire effect.
@MainActor
final class CandidateStatusLabel: UILabel {
    var hasGameBackground = false {
        didSet {
            backgroundColor = hasGameBackground ? .secondarySystemBackground : .clear
            textColor = hasGameBackground ? .label : .secondaryLabel
            layer.cornerRadius = hasGameBackground ? 5 : 0
            clipsToBounds = hasGameBackground
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    private var insets: UIEdgeInsets {
        hasGameBackground ? UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6) : .zero
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}

/// A decorative background inside the existing candidate bar. It never receives touches.
@MainActor
final class DragonGameEffectView: UIView {
    private let dragon = UIImageView(image: DragonGameEffectView.loadDragonSprite())
    private let fire = DragonFireTrailView()
    private let chargeTrack = CALayer()
    private let chargeFill = CAGradientLayer()
    private var charge: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        dragon.contentMode = .scaleAspectFit
        dragon.layer.magnificationFilter = .nearest
        dragon.layer.minificationFilter = .nearest
        addSubview(fire)
        addSubview(dragon)
        chargeTrack.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.2).cgColor
        chargeFill.colors = [UIColor.systemOrange.cgColor, UIColor.systemYellow.cgColor]
        chargeFill.startPoint = CGPoint(x: 0, y: 0.5)
        chargeFill.endPoint = CGPoint(x: 1, y: 0.5)
        chargeFill.masksToBounds = true
        layer.addSublayer(chargeTrack)
        layer.addSublayer(chargeFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func loadDragonSprite() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "RPGDragon", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 132,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        // Decode only the display-sized image, not the large generated source.
        return UIImage(cgImage: thumbnail, scale: 3, orientation: .up)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dragon.frame = CGRect(x: 2, y: 1, width: 44, height: max(0, bounds.height - 4))
        fire.frame = bounds
        updateGauge(animated: false)
    }

    func setCharge(_ level: Double, animated: Bool = true, pulsesDragon: Bool = true) {
        charge = CGFloat(level)
        updateGauge(animated: animated && !UIAccessibility.isReduceMotionEnabled)
        guard animated, pulsesDragon, !UIAccessibility.isReduceMotionEnabled else { return }
        // A brief anticipation on each tap, not an endless idle animation.
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.06 + charge * 0.08, 1]
        pulse.keyTimes = [0, 0.3, 1]
        pulse.duration = 0.22
        dragon.layer.add(pulse, forKey: "charge")
    }

    func breatheFire(energy: Double) {
        setCharge(0, animated: false)
        guard energy > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        fire.start(energy: CGFloat(energy))
        let recoil = CAKeyframeAnimation(keyPath: "transform.translation.x")
        recoil.values = [0, -3, 1, 0]
        recoil.keyTimes = [0, 0.12, 0.4, 1]
        recoil.duration = 0.45
        dragon.layer.removeAnimation(forKey: "charge")
        dragon.layer.add(recoil, forKey: "fire")
    }

    func stop() {
        fire.stop()
        dragon.layer.removeAllAnimations()
        charge = 0
        updateGauge(animated: false)
    }

    /// Editing/cancelling fades any remaining flame; the meter keeps its natural decay.
    func fadeFire() { fire.fadeOut() }

    func reduceMotionChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            fire.stop()
            dragon.layer.removeAllAnimations()
        }
    }

    private func updateGauge(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.12)
        let width = max(0, bounds.width - 58)
        chargeTrack.frame = CGRect(x: 52, y: bounds.height - 5, width: width, height: 4)
        chargeFill.frame = CGRect(x: 52, y: bounds.height - 5, width: width * charge, height: 4)
        chargeTrack.cornerRadius = 2
        chargeFill.cornerRadius = 2
        CATransaction.commit()
    }
}

/// A short, deterministic pixel-flame burst. No particles or timers remain after it ends.
@MainActor
private final class DragonFireTrailView: UIView {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var fadeStartTime: CFTimeInterval?
    private var elapsed: Double = 0
    private var energy: CGFloat = 0
    private var duration: Double { 0.95 + Double(energy) * 0.55 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start(energy: CGFloat) {
        stop()
        self.energy = energy
        startTime = CACurrentMediaTime()
        elapsed = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink = link
        link.add(to: .main, forMode: .common)
        setNeedsDisplay()
    }

    func fadeOut() {
        guard displayLink != nil, fadeStartTime == nil else { return }
        fadeStartTime = CACurrentMediaTime()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        fadeStartTime = nil
        energy = 0
        elapsed = 0
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if UIAccessibility.isReduceMotionEnabled { stop(); return }
        elapsed = CACurrentMediaTime() - startTime
        if elapsed >= duration || (fadeStartTime.map { CACurrentMediaTime() - $0 >= 0.28 } ?? false) {
            stop()
            return
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard energy > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let progress = CGFloat(elapsed / duration)
        // Eases outward from the mouth. The final 40% smoothly fades, not an abrupt cut.
        let reach = min(1, progress / 0.42)
        let easedReach = 1 - pow(1 - reach, 3)
        let tailFade = max(0, min(1, (1 - progress) / 0.4))
        let cancelFade = fadeStartTime.map {
            max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28))
        } ?? 1
        let opacity = tailFade * cancelFade
        let origin: CGFloat = 39
        let length = max(0, bounds.width - origin - 8) * (0.4 + 0.6 * energy) * easedReach
        let center = bounds.height * 0.43
        let thickness = bounds.height * (0.16 + 0.19 * energy)
        let cell: CGFloat = 3
        guard length > 0 else { return }
        // Layered jagged tongues read as RPG fire while leaving labels in the foreground.
        for (scale, color) in [(CGFloat(1), UIColor.systemRed), (0.72, .systemOrange), (0.38, .systemYellow)] {
            context.setFillColor(color.withAlphaComponent(opacity * 0.68).cgColor)
            var x: CGFloat = 0
            while x < length {
                let fraction = x / max(length, 1)
                let wave = CGFloat(sin(Double(x) * 0.14 - elapsed * 16))
                let taper = max(0.15, 1 - pow(fraction, 3))
                let halfHeight = max(cell, (thickness * taper + wave * 2) * scale)
                let offset = CGFloat(sin(Double(x) * 0.05 - elapsed * 11)) * 2
                let top = floor((center + offset - halfHeight) / cell) * cell
                let height = ceil(halfHeight * 2 / cell) * cell
                context.fill(CGRect(x: origin + x, y: top, width: cell + 0.5, height: height))
                x += cell
            }
        }
    }
}
