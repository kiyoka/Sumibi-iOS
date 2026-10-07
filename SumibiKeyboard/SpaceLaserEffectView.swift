import UIKit
import ImageIO

/// Shared interface keeps the energy model and keyboard actions independent of the artwork.
@MainActor
final class KeyboardGameEffectView: UIView {
    enum Theme { case dragon, spaceship, cat }
    private let dragon = DragonGameEffectView()
    private let spaceship = SpaceLaserEffectView()
    private let cat = CatHuntEffectView()
    private var theme = Theme.dragon

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(dragon)
        addSubview(spaceship)
        addSubview(cat)
        spaceship.isHidden = true
        cat.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dragon.frame = bounds
        spaceship.frame = bounds
        cat.frame = bounds
    }

    func setTheme(_ theme: Theme) {
        guard self.theme != theme else { return }
        stop()
        self.theme = theme
        spaceship.isHidden = theme != .spaceship
        dragon.isHidden = theme != .dragon
        cat.isHidden = theme != .cat
    }

    func setCharge(_ level: Double, animated: Bool = true, pulsesCharacter: Bool = true) {
        switch theme {
        case .spaceship:
            spaceship.setCharge(level, animated: animated, pulsesCharacter: pulsesCharacter)
        case .dragon:
            dragon.setCharge(level, animated: animated, pulsesDragon: pulsesCharacter)
        case .cat:
            cat.setCharge(level, animated: animated)
        }
    }

    func releaseEnergy(_ energy: Double) {
        switch theme {
        case .spaceship: spaceship.releaseEnergy(energy)
        case .dragon: dragon.breatheFire(energy: energy)
        case .cat: cat.releaseEnergy(energy)
        }
    }

    func fadeRelease() {
        switch theme {
        case .spaceship: spaceship.fadeRelease()
        case .dragon: dragon.fadeFire()
        case .cat: cat.fadeRelease()
        }
    }

    func stop() {
        dragon.stop()
        spaceship.stop()
        cat.stop()
    }

    func reduceMotionChanged() {
        dragon.reduceMotionChanged()
        spaceship.reduceMotionChanged()
        cat.reduceMotionChanged()
    }
}

/// Blue sci-fi counterpart to the dragon. Draws only during charge changes or a short shot.
@MainActor
final class SpaceLaserEffectView: UIView {
    private let ship = UIImageView(image: SpaceLaserEffectView.loadSprite())
    private let hullTint = CALayer()
    private let hullMask = CALayer()
    private let energyLines = CAShapeLayer()
    private let energyCore = CAShapeLayer()
    private let chargeTrack = CALayer()
    private let chargeFill = CAGradientLayer()
    private var charge: CGFloat = 0
    private var energy: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var fadeStartTime: CFTimeInterval?
    private var elapsed: Double = 0
    private var displayLink: CADisplayLink?
    private var duration: Double { 0.85 + Double(energy) * 0.55 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        ship.contentMode = .scaleAspectFit
        ship.layer.magnificationFilter = .nearest
        ship.layer.minificationFilter = .nearest
        addSubview(ship)
        // Tint only opaque sprite pixels, never the transparent square around the ship.
        hullTint.backgroundColor = UIColor(red: 0.05, green: 0.7, blue: 1, alpha: 1).cgColor
        hullMask.contents = ship.image?.cgImage
        hullMask.magnificationFilter = .nearest
        hullMask.minificationFilter = .nearest
        hullTint.mask = hullMask
        hullTint.opacity = 0
        ship.layer.addSublayer(hullTint)
        for light in [energyLines, energyCore] {
            light.fillColor = UIColor.systemCyan.cgColor
            light.shadowColor = UIColor.systemCyan.cgColor
            light.shadowOffset = .zero
            light.opacity = 0
            ship.layer.addSublayer(light)
        }
        energyCore.fillColor = UIColor(red: 0.8, green: 1, blue: 1, alpha: 1).cgColor
        chargeTrack.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.2).cgColor
        chargeFill.colors = [UIColor.systemBlue.cgColor, UIColor.systemCyan.cgColor]
        chargeFill.startPoint = CGPoint(x: 0, y: 0.5)
        chargeFill.endPoint = CGPoint(x: 1, y: 0.5)
        chargeFill.masksToBounds = true
        layer.addSublayer(chargeTrack)
        layer.addSublayer(chargeFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func loadSprite() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "SpaceLaserShip", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail, scale: 3, orientation: .up)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ship.frame = CGRect(x: 2, y: 1, width: 44, height: max(0, bounds.height - 4))
        layoutEnergyLights()
        updateGauge(animated: false)
    }

    func setCharge(_ level: Double, animated: Bool = true, pulsesCharacter: Bool = true) {
        charge = CGFloat(level)
        updateGauge(animated: animated && !UIAccessibility.isReduceMotionEnabled)
        updateEnergyLights()
        setNeedsDisplay()
        guard animated, pulsesCharacter, !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.05 + charge * 0.07, 1]
        pulse.keyTimes = [0, 0.3, 1]
        pulse.duration = 0.2
        ship.layer.add(pulse, forKey: "charge")
        // Briefly energize the slits on real taps, not on every meter-decay update.
        if energy == 0 {
            for light in [energyLines, energyCore] {
                let flash = CAKeyframeAnimation(keyPath: "opacity")
                flash.values = [light.opacity, min(1, light.opacity + 0.22), light.opacity]
                flash.keyTimes = [0, 0.25, 1]
                flash.duration = 0.2
                light.add(flash, forKey: "charge")
            }
        }
    }

    func releaseEnergy(_ level: Double) {
        stopShot()
        setCharge(0, animated: false)
        guard level > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        energy = CGFloat(min(1, level))
        energyLines.removeAllAnimations()
        energyCore.removeAllAnimations()
        hullTint.removeAllAnimations()
        updateEnergyLights()
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink = link
        link.add(to: .main, forMode: .common)
        ship.layer.removeAnimation(forKey: "charge")
        let recoil = CAKeyframeAnimation(keyPath: "transform.translation.x")
        recoil.values = [0, -2 - 3 * energy, -1, 0]
        recoil.keyTimes = [0, 0.15, 0.55, 1]
        recoil.duration = 0.35
        ship.layer.add(recoil, forKey: "shot")
        setNeedsDisplay()
    }

    func fadeRelease() {
        guard displayLink != nil, fadeStartTime == nil else { return }
        fadeStartTime = CACurrentMediaTime()
    }

    func stop() {
        stopShot()
        charge = 0
        updateEnergyLights()
        updateGauge(animated: false)
        setNeedsDisplay()
    }

    func reduceMotionChanged() {
        if UIAccessibility.isReduceMotionEnabled { stopShot() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    private func stopShot() {
        displayLink?.invalidate()
        displayLink = nil
        fadeStartTime = nil
        elapsed = 0
        energy = 0
        ship.layer.removeAllAnimations()
        energyLines.removeAllAnimations()
        energyCore.removeAllAnimations()
        hullTint.removeAllAnimations()
        updateEnergyLights()
        setNeedsDisplay()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if UIAccessibility.isReduceMotionEnabled { stopShot(); return }
        elapsed = CACurrentMediaTime() - startTime
        if elapsed >= duration || (fadeStartTime.map { CACurrentMediaTime() - $0 >= 0.28 } ?? false) {
            stopShot()
            return
        }
        updateEnergyLights()
        setNeedsDisplay()
    }

    private func layoutEnergyLights() {
        // Coordinates follow the original sprite's three rear slits, side conduit and core.
        // Attaching lights to the ship layer keeps them aligned through recoil and scaling.
        let side = min(ship.bounds.width, ship.bounds.height)
        let origin = CGPoint(x: (ship.bounds.width - side) / 2, y: (ship.bounds.height - side) / 2)
        func spriteRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * side, y: origin.y + y * side,
                   width: width * side, height: height * side)
        }
        let lines = CGMutablePath()
        for y in [CGFloat(0.46), 0.50, 0.54] {
            lines.addRect(spriteRect(0.22, y, 0.13, 0.02))
        }
        lines.addRect(spriteRect(0.40, 0.54, 0.34, 0.02))
        let core = CGPath(rect: spriteRect(0.51, 0.62, 0.06, 0.05), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hullTint.frame = CGRect(origin: origin, size: CGSize(width: side, height: side))
        hullMask.frame = hullTint.bounds
        energyLines.frame = ship.bounds
        energyCore.frame = ship.bounds
        energyLines.path = lines
        energyLines.shadowPath = lines
        energyCore.path = core
        energyCore.shadowPath = core
        CATransaction.commit()
    }

    private func updateEnergyLights() {
        var intensity = charge * 0.9
        if energy > 0 {
            let remaining = max(0, min(1, CGFloat((duration - elapsed) / duration) / 0.35))
            let cancelled = fadeStartTime.map {
                max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28))
            } ?? 1
            // Small continuous pulses, never on/off flashes of the whole keyboard.
            let pulse = 0.76 + 0.24 * CGFloat(cos(elapsed * .pi * 2 * 2.5))
            intensity = max(intensity, (0.75 + 0.5 * energy) * pulse * remaining * cancelled)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hullTint.opacity = Float(min(0.7, intensity * (energy > 0 ? 0.56 : 0.3)))
        energyLines.opacity = Float(min(1, intensity))
        energyCore.opacity = Float(min(1, intensity * 1.15))
        energyLines.shadowOpacity = Float(min(1, intensity))
        energyCore.shadowOpacity = Float(min(1, intensity))
        energyLines.shadowRadius = 2 + 3.5 * intensity
        energyCore.shadowRadius = 2.5 + 4 * intensity
        CATransaction.commit()
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
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setShouldAntialias(false)
        let cell: CGFloat = 3
        let shipFrame = ship.layer.presentation()?.frame ?? ship.frame
        let side = min(shipFrame.width, shipFrame.height)
        let center = floor((shipFrame.midY + side * 0.07) / cell) * cell
        let origin = floor((shipFrame.midX + side * 0.46) / cell) * cell
        let cyan = UIColor(red: 0.1, green: 0.85, blue: 1, alpha: 1)
        // A static cannon glow shows the current charge without an idle animation/timer.
        if charge > 0 {
            context.setFillColor(cyan.withAlphaComponent(0.2 + 0.6 * charge).cgColor)
            let size = cell * (1 + floor(charge * 2))
            context.fill(CGRect(x: origin - size / 2, y: center - size / 2, width: size, height: size))
        }
        guard energy > 0 else { return }
        let progress = CGFloat(elapsed / duration)
        let opacity = max(0, min(1, (1 - progress) / 0.35)) * (fadeStartTime.map {
            max(0, 1 - CGFloat((CACurrentMediaTime() - $0) / 0.28))
        } ?? 1)
        let available = max(0, bounds.width - origin - 8)
        let reach = min(1, progress / 0.3)
        let length = floor(available * (1 - pow(1 - reach, 3)) / cell) * cell
        let halfHeight = cell * (1 + floor(energy * 3))
        // Low charge is a moving short bolt, high charge a connected cannon beam.
        let tail = energy < 0.35 ? max(0, length - cell * (5 + floor(energy * 12))) : 0
        guard length > tail else { return }
        context.setAlpha(opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for (inset, color) in [(CGFloat(0), UIColor.systemBlue), (cell, cyan), (cell * 2, UIColor.white)] {
            context.setFillColor(color.cgColor)
            let height = max(cell, halfHeight * 2 - inset * 2)
            context.fill(CGRect(x: origin + tail, y: center - height / 2, width: length - tail, height: height))
        }
        context.setFillColor(cyan.cgColor)
        context.fill(CGRect(x: origin + length - cell, y: center - halfHeight - cell,
                            width: cell * 2, height: halfHeight * 2 + cell * 2))
        // Discrete rear thruster pixels and a muzzle cross; no rapid flashing of the bar.
        let exhaust = cell * (1 + CGFloat(Int(elapsed * 12) % 3))
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fill(CGRect(x: 3, y: center - cell, width: exhaust, height: cell * 2))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: origin - cell, y: center - cell, width: cell * 2, height: cell * 2))
        context.endTransparencyLayer()
    }
}
