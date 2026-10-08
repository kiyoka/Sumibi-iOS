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
    private let dragon = DragonBreathingSpriteView(image: DragonGameEffectView.loadDragonSprite())
    private let fire = DragonFireTrailView()
    private let chargeTrack = CALayer()
    private let chargeFill = CAGradientLayer()
    private var charge: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        fire.onAnimationFrame = { [weak self] elapsed, strength in
            guard let self else { return nil }
            let mouth = self.dragon.updateBreathing(elapsed: elapsed, strength: strength)
            return self.dragon.convert(mouth, to: self.fire)
        }
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
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        // Keep a coarse 8-bit sprite; nearest filtering preserves its large visible dots.
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
        dragon.layer.removeAnimation(forKey: "charge")
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

/// A small textured mesh animates the existing sprite without extra assets or idle timers.
/// Shared mesh vertices keep the wing/neck attached rather than sliding cut-out pieces.
@MainActor
private final class DragonBreathingSpriteView: UIView {
    private let image: UIImage?
    private var elapsed: Double = 0
    private var strength: CGFloat = 0

    init(image: UIImage?) {
        self.image = image
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func updateBreathing(elapsed: Double, strength: CGFloat) -> CGPoint {
        self.elapsed = elapsed
        self.strength = strength
        setNeedsDisplay()
        return posedPoint(CGPoint(x: 0.94, y: 0.48))
    }

    private var imageRect: CGRect {
        let side = min(bounds.width, bounds.height)
        return CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                      width: side, height: side)
    }

    private func posedPoint(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        var x = point.x
        var y = point.y
        // The upper-left wing has the largest excursion; its shoulder/feet stay anchored.
        let wing = exp(-pow((x - 0.32) / 0.25, 2) - pow((y - 0.32) / 0.24, 2))
        let flap = CGFloat(sin(elapsed * .pi * 2 * 4.5)) * strength
        x += wing * flap * 0.055
        y += wing * flap * 0.16
        // Head and neck bob together, fading to zero at the torso and feet.
        let neck = max(0, min(1, (point.x - 0.55) / 0.22))
            * max(0, min(1, (0.82 - point.y) / 0.25))
        y += neck * CGFloat(sin(elapsed * .pi * 2 * 2.5)) * strength * 0.045
        // A single lean-back at release, then continuous wing/neck motion during fire.
        let recoil = elapsed < 0.34 ? CGFloat(sin(elapsed / 0.34 * .pi)) * strength : 0
        let angle = -0.18 * recoil
        let dx = x - 0.58
        let dy = y - 0.85
        x = 0.58 + dx * cos(angle) - dy * sin(angle) - recoil * 0.055
        y = 0.85 + dx * sin(angle) + dy * cos(angle)
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    override func draw(_ rect: CGRect) {
        guard let image, let context = UIGraphicsGetCurrentContext() else { return }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        guard strength > 0 else { image.draw(in: imageRect); return }
        // 8x8 connected quads, two triangles each; at most 128 tiny texture draws/frame.
        let divisions = 8
        for row in 0..<divisions {
            for column in 0..<divisions {
                let x = CGFloat(column) / CGFloat(divisions)
                let y = CGFloat(row) / CGFloat(divisions)
                let step = 1 / CGFloat(divisions)
                let a = CGPoint(x: x, y: y)
                let b = CGPoint(x: x + step, y: y)
                let c = CGPoint(x: x, y: y + step)
                let d = CGPoint(x: x + step, y: y + step)
                drawTriangle(a, b, c, image: image, context: context)
                drawTriangle(d, c, b, image: image, context: context)
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

/// A short, deterministic pixel-flame burst. No particles or timers remain after it ends.
@MainActor
private final class DragonFireTrailView: UIView {
    var onAnimationFrame: ((Double, CGFloat) -> CGPoint?)?
    private var mouth: CGPoint?
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
        mouth = onAnimationFrame?(0, 0)
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
        mouth = onAnimationFrame?(0, 0)
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
        let recovery = min(1, CGFloat((duration - elapsed) / 0.25))
        let cancellation = fadeStartTime.map {
            max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28))
        } ?? 1
        let attack = min(1, CGFloat(elapsed / 0.06))
        mouth = onAnimationFrame?(elapsed, attack * recovery * cancellation)
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
        // Eight chunky rows fit both portrait (5pt dots) and landscape (4pt dots).
        let cell = max(4, floor(bounds.height / 8))
        let origin = floor((mouth?.x ?? 40) / cell) * cell
        let rawLength = max(0, bounds.width - origin - 8) * (0.4 + 0.6 * energy) * easedReach
        let length = floor(rawLength / cell) * cell
        let center = floor((mouth?.y ?? bounds.height * 0.43) / cell) * cell
        let thickness = bounds.height * (0.16 + 0.19 * energy)
        guard length > 0 else { return }
        context.setShouldAntialias(false)
        // Fixed three-color clusters and a 12fps shape evoke an early console sprite.
        // Fade still updates at 30fps so ending/cancelling remains gentle.
        let spriteTime = floor(elapsed * 12) / 12
        let palette: [(CGFloat, UIColor)] = [
            (1, UIColor(red: 0.86, green: 0.13, blue: 0.10, alpha: 1)),
            (0.65, UIColor(red: 1, green: 0.39, blue: 0.05, alpha: 1)),
            (0.3, UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)),
        ]
        context.setAlpha(opacity * 0.9)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for (scale, color) in palette {
            context.setFillColor(color.cgColor)
            var x: CGFloat = 0
            while x < length {
                let fraction = x / max(length, 1)
                let wave = CGFloat(sin(Double(x) * 0.14 - spriteTime * 16))
                let taper = max(0.15, 1 - pow(fraction, 3))
                let halfHeight = max(cell, (thickness * taper + wave * 2) * scale)
                let offset = CGFloat(sin(Double(x) * 0.05 - spriteTime * 11)) * cell
                let top = floor((center + offset - halfHeight) / cell) * cell
                let height = ceil(halfHeight * 2 / cell) * cell
                context.fill(CGRect(x: origin + x, y: top, width: cell, height: height))
                x += cell
            }
        }
        context.endTransparencyLayer()
    }
}
