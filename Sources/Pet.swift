import Cocoa
import QuartzCore

// MARK: - Look & feel

enum PetMood { case idle, walking, sleeping, happy, dragged, falling, thinking, talking }

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

private enum Palette {
    static let bodyTop = NSColor(hex: 0xFFEDE1)
    static let bodyBottom = NSColor(hex: 0xFFC6D2)
    static let outline = NSColor(hex: 0xE59AAE)
    static let stripe = NSColor(hex: 0xFF9EB5, alpha: 0.55)
    static let feet = NSColor(hex: 0xF7B3A8)
    static let earInner = NSColor(hex: 0xFF9FB4)
    static let ink = NSColor(hex: 0x3A2E39)
    static let blush = NSColor(hex: 0xFF7F9B, alpha: 0.45)
    static let mouth = NSColor(hex: 0x8A3B4F)
    static let leaf = NSColor(hex: 0x86D39C)
    static let leafDark = NSColor(hex: 0x5BAF76)
    static let bubbleText = NSColor(hex: 0x5A4050)
}

private func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

// MARK: - The drawn character

final class PetView: NSView {
    var mood: PetMood = .idle
    var facing: CGFloat = 1          // 1 = right, -1 = left
    var t: CGFloat = 0               // animation clock (seconds)
    var blink: CGFloat = 0           // 0 open … 1 closed
    var squash: CGFloat = 0          // landing squash, decays to 0
    var bubbleText: String?

    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// Region that counts as "the pet" for hover.
    var petRect: NSRect { NSRect(x: bounds.midX - 52 * scale, y: 0, width: 104 * scale, height: 128 * scale) }

    /// Overall size of the character (1 = original big Rick).
    var scale: CGFloat = 0.6 { didSet { updateTrackingAreas() } }

    /// Optional custom sprite (pixel art PNG). When set it replaces the drawn Rick.
    /// Animations of a custom sprite (empty = draw the built-in character).
    var spriteSet = SpriteSet()

    /// A one-off sprite animation (e.g. "sad", "music") playing right now, and when it started.
    var special: String?
    var specialStart: CGFloat = 0
    /// Play the special animation once, then stay on its last frame (e.g. sulking).
    var holdSpecial = false
    /// "You Cryin?" mode: loop the sprite's `cryin` animation instead of idling.
    var cryin = false

    var sprite: CGImage? { spriteFrame?.image }

    /// The frame to show right now, and whether to mirror it (sprites face right).
    var spriteFrame: (image: CGImage, flip: Bool)? {
        let a = spriteSet.anims
        guard let idle = a["idle"], !idle.isEmpty else { return nil }
        func loop(_ frames: [CGImage], fps: CGFloat, from start: CGFloat = 0) -> CGImage {
            frames[Int(max(0, t - start) * fps) % frames.count]
        }
        let flip = facing < 0
        switch mood {
        case .dragged, .falling:
            if let jump = a["jump"] { return (loop(jump, fps: 8), flip) }
            return (idle[0], flip)
        case .walking:
            if flip, let left = a["walkLeft"] { return (loop(left, fps: 10), false) }
            return (loop(spriteSet.walk, fps: 10), flip)
        case .sleeping:
            if let sleep = a["sleep"] { return (loop(sleep, fps: 0.7), flip) }
            return (idle[0], flip)
        default:
            if cryin, let frames = a["cryin"] { return (loop(frames, fps: 3), flip) }
            if let s = special, let frames = a[s] {
                if holdSpecial {
                    let i = min(Int(max(0, t - specialStart) * 5), frames.count - 1)
                    return (frames[i], flip)
                }
                return (loop(frames, fps: 6, from: specialStart), flip)
            }
            if mood == .happy, let wave = a["wave"] { return (loop(wave, fps: 6), flip) }
            return (loop(idle, fps: 4), flip)
        }
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: petRect,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    /// Size of one "pixel" of the pixel-art character, in points. 1 = smooth vector look.
    var pixelSize: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        // Draw the character into a tiny bitmap, then blow it up with nearest-neighbour
        // scaling so it comes out as chunky pixel art. Speech bubbles stay crisp.
        // (A custom sprite already is pixel art, so it's drawn directly.)
        let pw = Int(ceil(bounds.width / pixelSize)), ph = Int(ceil(bounds.height / pixelSize))
        var bubbleBottom: CGFloat = 0
        if pixelSize > 1, sprite == nil,
           let low = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            low.setShouldAntialias(false)
            low.scaleBy(x: 1 / pixelSize, y: 1 / pixelSize)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: low, flipped: false)
            bubbleBottom = drawCharacter(low)
            NSGraphicsContext.restoreGraphicsState()
            if let img = low.makeImage() {
                ctx.saveGState()
                ctx.interpolationQuality = .none
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(pw) * pixelSize, height: CGFloat(ph) * pixelSize))
                ctx.restoreGState()
            }
        } else {
            bubbleBottom = drawCharacter(ctx)
        }

        let cx = bounds.midX
        if mood == .thinking {
            drawBubble(text: nil, anchorX: cx, bottom: bubbleBottom)
        } else if let text = bubbleText {
            drawBubble(text: text, anchorX: cx, bottom: bubbleBottom)
        }
    }

    /// Draws the creature; returns the y where a speech bubble should start.
    private func drawCharacter(_ ctx: CGContext) -> CGFloat {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Everything below is laid out at full size; shrink it around the feet.
        ctx.translateBy(x: bounds.midX, y: 0)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.midX, y: 0)
        return drawCharacterFullSize(ctx) * scale + 10
    }

    private func drawCharacterFullSize(_ ctx: CGContext) -> CGFloat {
        let cx = bounds.midX
        let ground: CGFloat = 12
        var bob: CGFloat = 0
        var sx: CGFloat = 1, sy: CGFloat = 1
        var tilt: CGFloat = 0

        switch mood {
        case .walking:
            bob = abs(sin(t * 9)) * 6
            sy = 1 + 0.035 * sin(t * 18); sx = 1 - 0.025 * sin(t * 18)
            tilt = 0.05 * sin(t * 9) * facing
        case .idle, .thinking:
            sy = 1 + 0.025 * sin(t * 2.2); sx = 1 - 0.015 * sin(t * 2.2)
        case .happy:
            bob = abs(sin(t * 5)) * 4
            sy = 1 + 0.03 * sin(t * 10); sx = 1 - 0.02 * sin(t * 10)
        case .talking:
            bob = abs(sin(t * 7)) * 2.5
            sy = 1 + 0.02 * sin(t * 14)
        case .sleeping:
            sy = 1 - 0.05 + 0.04 * sin(t * 1.3); sx = 1 + 0.04 - 0.02 * sin(t * 1.3)
        case .dragged:
            sy = 1.08; sx = 0.94
            tilt = 0.14 * sin(t * 5)
        case .falling:
            sy = 1.06; sx = 0.95
        }
        // landing squash
        sy *= 1 - 0.22 * squash
        sx *= 1 + 0.18 * squash

        let bodyW = 86 * sx, bodyH = 74 * sy
        let bodyBottom = ground + 7 + bob
        let bodyCY = bodyBottom + bodyH / 2
        let bodyTop = bodyBottom + bodyH
        let airborne = (mood == .dragged || mood == .falling)

        // Shadow
        if !airborne {
            let sw = 70 * (1 - bob / 30)
            Palette.ink.withAlphaComponent(0.13).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - sw / 2, y: ground - 5, width: sw, height: 10)).fill()
        }

        ctx.saveGState()
        // Rotate around the top of the head when dangling, around the feet otherwise
        let pivot = CGPoint(x: cx, y: mood == .dragged ? bodyTop : ground)
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: -tilt)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)

        if let sprite {
            let top = drawSprite(sprite, ctx: ctx, cx: cx, bottom: ground + bob, sx: sx, sy: sy)
            ctx.restoreGState()
            if mood == .sleeping { drawZzz(cx: cx, bodyTop: top - 10) }
            return top + 14
        }

        drawFeet(cx: cx, ground: ground, bob: bob, airborne: airborne)
        drawEars(cx: cx, bodyTop: bodyTop, bodyW: bodyW)
        drawSprout(cx: cx, bodyTop: bodyTop)
        if mood == .happy { drawWavingArm(cx: cx, bodyCY: bodyCY, bodyW: bodyW) }
        drawBody(cx: cx, cy: bodyCY, w: bodyW, h: bodyH)
        drawFace(cx: cx, bodyCY: bodyCY, sy: sy)
        ctx.restoreGState()

        if mood == .sleeping { drawZzz(cx: cx, bodyTop: bodyTop) }
        return bodyTop + 26
    }

    /// Draws a custom sprite standing at `bottom`, facing the walking direction; returns its top y.
    private func drawSprite(_ img: CGImage, ctx: CGContext, cx: CGFloat, bottom: CGFloat, sx: CGFloat, sy: CGFloat) -> CGFloat {
        // Small pixel art: whole-number scale keeps it crisp (aim for ~70pt tall).
        // Big art (hi-res sheets): shrink smoothly to ~80pt tall.
        let target: CGFloat = 80
        let big = CGFloat(img.height) > target * 1.4
        let onScreen = (big ? target : CGFloat(img.height) * max(1, (70 / CGFloat(img.height)).rounded())) * spriteSet.size
        let h: CGFloat = onScreen / scale * sy
        let w = h * CGFloat(img.width) / CGFloat(img.height) * sx / sy
        ctx.saveGState()
        ctx.interpolationQuality = big ? .high : .none
        ctx.translateBy(x: cx, y: bottom)
        if spriteFrame?.flip ?? (facing < 0) { ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(img, in: CGRect(x: -w / 2, y: 0, width: w, height: h))
        ctx.restoreGState()
        return bottom + h
    }

    // MARK: parts

    private func drawFeet(cx: CGFloat, ground: CGFloat, bob: CGFloat, airborne: Bool) {
        Palette.feet.setFill()
        Palette.outline.setStroke()
        for side in [-1.0, 1.0] as [CGFloat] {
            var dx: CGFloat = 0, lift: CGFloat = 0
            switch mood {
            case .walking:
                let p = sin(t * 9 + (side > 0 ? .pi : 0))
                dx = p * 5 * facing; lift = max(0, p) * 4
            case .dragged:
                lift = -8 + 3 * sin(t * 11 + side)
                dx = 2 * sin(t * 7 + side)
            case .falling:
                lift = -4
            default: break
            }
            let r = NSRect(x: cx + side * 19 - 11 + dx, y: ground + lift + (airborne ? 2 : bob * 0.4), width: 22, height: 13)
            let p = NSBezierPath(ovalIn: r); p.lineWidth = 1.5
            p.fill(); p.stroke()
        }
    }

    private func drawEars(cx: CGFloat, bodyTop: CGFloat, bodyW: CGFloat) {
        let wiggle = mood == .happy ? 2 * sin(t * 10) : 0
        for side in [-1.0, 1.0] as [CGFloat] {
            let c = CGPoint(x: cx + side * bodyW * 0.32, y: bodyTop - 9 + (side > 0 ? wiggle : -wiggle))
            let outer = NSBezierPath(ovalIn: NSRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26))
            outer.lineWidth = 2
            Palette.bodyTop.setFill(); outer.fill()
            Palette.outline.setStroke(); outer.stroke()
            Palette.earInner.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 7, y: c.y - 5, width: 14, height: 14)).fill()
        }
    }

    private func drawSprout(cx: CGFloat, bodyTop: CGFloat) {
        let sway = sin(t * 2.6) * 4 + (mood == .walking ? -facing * 3 : 0)
        let base = CGPoint(x: cx, y: bodyTop - 3)
        let tip = CGPoint(x: cx + sway, y: bodyTop + 13)
        let stem = NSBezierPath()
        stem.move(to: base)
        stem.curve(to: tip, controlPoint1: CGPoint(x: cx, y: bodyTop + 6), controlPoint2: CGPoint(x: cx + sway * 0.5, y: bodyTop + 10))
        stem.lineWidth = 2.5; stem.lineCapStyle = .round
        Palette.leafDark.setStroke(); stem.stroke()
        for side in [-1.0, 1.0] as [CGFloat] {
            let leaf = NSBezierPath(ovalIn: NSRect(x: -9, y: -4.5, width: 18, height: 9))
            var tr = AffineTransform(translationByX: tip.x + side * 7, byY: tip.y + 1)
            tr.rotate(byRadians: side * 0.5 + sway * 0.03)
            leaf.transform(using: tr)
            Palette.leaf.setFill(); leaf.fill()
            leaf.lineWidth = 1.2; Palette.leafDark.setStroke(); leaf.stroke()
        }
    }

    private func drawWavingArm(cx: CGFloat, bodyCY: CGFloat, bodyW: CGFloat) {
        let side = facing
        let arm = NSBezierPath(ovalIn: NSRect(x: -7, y: 0, width: 14, height: 24))
        var tr = AffineTransform(translationByX: cx + side * (bodyW / 2 - 6), byY: bodyCY + 4)
        tr.rotate(byRadians: -side * (0.9 + 0.45 * sin(t * 12)))
        arm.transform(using: tr)
        arm.lineWidth = 2
        Palette.bodyTop.setFill(); arm.fill()
        Palette.outline.setStroke(); arm.stroke()
    }

    private func drawBody(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let rect = NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let body = NSBezierPath(roundedRect: rect, xRadius: w * 0.46, yRadius: h * 0.5)
        NSGradient(starting: Palette.bodyTop, ending: Palette.bodyBottom)?.draw(in: body, angle: -90)
        // tabby stripes
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        Palette.stripe.setFill()
        let band = pixelSize * 2, gap = pixelSize * 3          // snap to the pixel grid
        var y = (rect.minY / pixelSize).rounded() * pixelSize + pixelSize
        while y < rect.maxY {
            NSBezierPath(rect: NSRect(x: rect.minX, y: y, width: w, height: band)).fill()
            y += band + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        body.lineWidth = 2.2
        Palette.outline.setStroke(); body.stroke()
        // soft sheen
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - w * 0.30, y: cy + h * 0.18, width: w * 0.22, height: h * 0.14)).fill()
    }

    private func drawFace(cx: CGFloat, bodyCY: CGFloat, sy: CGFloat) {
        var lookX: CGFloat = 0, lookY: CGFloat = 0
        switch mood {
        case .walking: lookX = facing * 5
        case .thinking: lookX = 4; lookY = 4
        case .talking: lookX = facing * 2
        default: break
        }
        let eyeY = bodyCY + 6 * sy + lookY
        let eyeDX: CGFloat = 16

        // blush
        Palette.blush.setFill()
        for side in [-1.0, 1.0] as [CGFloat] {
            NSBezierPath(ovalIn: NSRect(x: cx + lookX * 0.6 + side * (eyeDX + 9) - 7, y: eyeY - 14, width: 14, height: 8)).fill()
        }

        Palette.ink.setStroke(); Palette.ink.setFill()
        for side in [-1.0, 1.0] as [CGFloat] {
            let ex = cx + lookX + side * eyeDX
            switch mood {
            case .sleeping:
                let p = NSBezierPath()
                p.move(to: CGPoint(x: ex - 6, y: eyeY))
                p.curve(to: CGPoint(x: ex + 6, y: eyeY), controlPoint1: CGPoint(x: ex - 3, y: eyeY - 5), controlPoint2: CGPoint(x: ex + 3, y: eyeY - 5))
                p.lineWidth = 2.4; p.lineCapStyle = .round; p.stroke()
            case .happy:
                let p = NSBezierPath()
                p.move(to: CGPoint(x: ex - 6, y: eyeY - 2))
                p.curve(to: CGPoint(x: ex + 6, y: eyeY - 2), controlPoint1: CGPoint(x: ex - 3, y: eyeY + 5), controlPoint2: CGPoint(x: ex + 3, y: eyeY + 5))
                p.lineWidth = 2.6; p.lineCapStyle = .round; p.stroke()
            case .dragged:
                // > <
                let p = NSBezierPath()
                p.move(to: CGPoint(x: ex - side * 5, y: eyeY + 5))
                p.line(to: CGPoint(x: ex + side * 4, y: eyeY))
                p.line(to: CGPoint(x: ex - side * 5, y: eyeY - 5))
                p.lineWidth = 2.6; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
            default:
                let h = max(1.6, 13 * (1 - blink))
                NSBezierPath(ovalIn: NSRect(x: ex - 5, y: eyeY - h / 2, width: 10, height: h)).fill()
                if blink < 0.5 {
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: NSRect(x: ex - 0.5, y: eyeY + 1, width: 4.6, height: 4.6)).fill()
                    NSBezierPath(ovalIn: NSRect(x: ex - 3.5, y: eyeY - 4, width: 2.2, height: 2.2)).fill()
                    Palette.ink.setFill()
                }
            }
        }

        // mouth
        let mx = cx + lookX * 0.7, my = eyeY - 12
        switch mood {
        case .talking:
            let open = 2 + 6 * abs(sin(t * 13))
            Palette.mouth.setFill()
            NSBezierPath(ovalIn: NSRect(x: mx - 4.5, y: my - open / 2, width: 9, height: open)).fill()
        case .happy:
            let p = NSBezierPath()
            p.move(to: CGPoint(x: mx - 6, y: my + 1))
            p.curve(to: CGPoint(x: mx + 6, y: my + 1), controlPoint1: CGPoint(x: mx - 5, y: my - 8), controlPoint2: CGPoint(x: mx + 5, y: my - 8))
            p.close()
            Palette.mouth.setFill(); p.fill()
        case .dragged, .falling:
            Palette.mouth.setFill()
            NSBezierPath(ovalIn: NSRect(x: mx - 3.5, y: my - 4, width: 7, height: 8)).fill()
        case .sleeping:
            Palette.mouth.setFill()
            NSBezierPath(ovalIn: NSRect(x: mx - 2, y: my - 1, width: 4, height: 4)).fill()
        case .thinking:
            let p = NSBezierPath()
            p.move(to: CGPoint(x: mx - 4, y: my)); p.line(to: CGPoint(x: mx + 4, y: my + 1.5))
            p.lineWidth = 2; p.lineCapStyle = .round; Palette.ink.setStroke(); p.stroke()
        default:
            // little "w" mouth
            let p = NSBezierPath()
            p.move(to: CGPoint(x: mx - 6, y: my + 1))
            p.curve(to: CGPoint(x: mx, y: my + 1), controlPoint1: CGPoint(x: mx - 5, y: my - 3), controlPoint2: CGPoint(x: mx - 1, y: my - 3))
            p.curve(to: CGPoint(x: mx + 6, y: my + 1), controlPoint1: CGPoint(x: mx + 1, y: my - 3), controlPoint2: CGPoint(x: mx + 5, y: my - 3))
            p.lineWidth = 1.8; p.lineCapStyle = .round; Palette.ink.setStroke(); p.stroke()
        }
    }

    private func drawZzz(cx: CGFloat, bodyTop: CGFloat) {
        for i in 0..<3 {
            let phase = (t * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(9 + phase * 9, .heavy),
                .foregroundColor: NSColor(hex: 0x9B8FD6, alpha: 1 - phase)
            ]
            ("z" as NSString).draw(at: CGPoint(x: cx + 30 + phase * 22 + sin(phase * 6) * 3, y: bodyTop - 10 + phase * 34), withAttributes: attrs)
        }
    }

    private func drawBubble(text: String?, anchorX: CGFloat, bottom: CGFloat) {
        let font = roundedFont(12, .semibold)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.bubbleText, .paragraphStyle: para]
        let maxW = bounds.width - 24
        var size = CGSize(width: 46, height: 18)
        if let text {
            let r = (text as NSString).boundingRect(with: CGSize(width: maxW - 20, height: 200),
                                                    options: [.usesLineFragmentOrigin], attributes: attrs)
            size = CGSize(width: ceil(r.width), height: ceil(r.height))
        }
        let w = size.width + 20, h = size.height + 12
        let x = min(max(anchorX - w / 2, 4), bounds.width - w - 4)
        let bottom = min(bottom, bounds.height - h - 2)      // big pets: keep the bubble in the window
        let rect = NSRect(x: x, y: bottom, width: w, height: h)

        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: anchorX - 7, y: bottom + 1))
        tail.line(to: CGPoint(x: anchorX - 2, y: bottom - 8))
        tail.line(to: CGPoint(x: anchorX + 6, y: bottom + 1))
        tail.close()
        path.append(tail)
        NSColor.white.withAlphaComponent(0.97).setFill(); path.fill()
        path.lineWidth = 1.6; Palette.outline.setStroke(); path.stroke()
        // cover the seam between tail and bubble
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: anchorX - 6, y: bottom - 0.5, width: 11, height: 2.5)).fill()

        if let text {
            (text as NSString).draw(with: NSRect(x: rect.minX + 10, y: rect.minY + 6, width: size.width, height: size.height),
                                    options: [.usesLineFragmentOrigin], attributes: attrs)
        } else {
            for i in 0..<3 {
                let jump = max(0, sin(t * 6 - CGFloat(i) * 0.9)) * 4
                Palette.outline.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.midX - 13 + CGFloat(i) * 10, y: rect.midY - 3 + jump, width: 6, height: 6)).fill()
            }
        }
    }
}

// MARK: - Behaviour: walking around, getting dragged, falling, napping

final class PetController {
    enum Activity { case idle, walk, sleep, drag, fall }

    let window: NSWindow
    let view: PetView
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// Set by the chat: while non-nil, the pet shows this mood instead of wandering.
    var chatMood: PetMood?
    var chatOpen = false { didSet { if chatOpen { activity = .idle; activityTime = 3 } } }

    private var activity: Activity = .fall
    private var activityTime: Double = 2
    private var targetX: CGFloat = 0
    private var vy: CGFloat = 0
    private var hovering = false
    private var happyTime: Double = 0
    private var blinkTimer: Double = 3
    private var blinkPhase: Double = 0
    private var bubbleTime: Double = 0
    private var chatterTimer = Double.random(in: 45...90)
    private var reminderTimer: Double = 8          // first reminder shortly after launch
    private var lastTick = CACurrentMediaTime()
    private var dragOffset = CGPoint.zero
    private var dragStart = CGPoint.zero
    private var didDrag = false
    private var specialTime: Double = 0
    private var thrown = false          // dropped by the user (vs. the first fall onto the screen)
    private var timer: Timer?

    static let size = NSSize(width: 230, height: 210)
    private var walkSpeed: CGFloat { hyper ? 120 : 40 }

    // MARK: options (remembered between launches)
    private static let defaults = UserDefaults.standard
    /// No speech bubbles at all.
    var muted = defaults.bool(forKey: Profiles.key("muted")) { didSet { Self.defaults.set(muted, forKey: Profiles.key("muted")); if muted { say(nil, for: 0) } } }
    /// Never walks off; still animates (guitar, naps, waves).
    var stayStill = defaults.bool(forKey: Profiles.key("stayStill")) { didSet { Self.defaults.set(stayStill, forKey: Profiles.key("stayStill")) } }
    /// Stays wherever you drop it instead of falling to the floor.
    var antiGravity = defaults.bool(forKey: Profiles.key("antiGravity")) { didSet { Self.defaults.set(antiGravity, forKey: Profiles.key("antiGravity")) } }
    /// Hyperactive: hops and zooms around, never naps.
    var adhd = defaults.bool(forKey: Profiles.key("adhd")) { didSet { Self.defaults.set(adhd, forKey: Profiles.key("adhd")); activityTime = 0 } }
    /// "You Cryin?": stands in place doing the sprite's `cryin` animation over and over.
    var cryin = defaults.bool(forKey: Profiles.key("cryin")) {
        didSet {
            Self.defaults.set(cryin, forKey: Profiles.key("cryin"))
            view.cryin = cryin
            if cryin, activity == .walk || activity == .sleep { activity = .idle; activityTime = 1 }
        }
    }
    /// Whether this profile's sprite has a `cryin` animation (the menu only offers the mode then).
    var canCry: Bool { view.spriteSet.anims["cryin"] != nil }

    // MARK: profile modes (e.g. Pinkie's), from the sprite's sprite.json

    /// The sprite with all its modes; `view.spriteSet` is it with the current mode applied.
    private var fullSet = SpriteSet()
    private(set) var mode: SpriteMode?
    var modes: [SpriteMode] { fullSet.modes }
    var hasModes: Bool { !fullSet.modes.isEmpty }

    /// Behaviour actually in effect: the Stay Still / ADHD toggles, or the current mode's own.
    private var still: Bool { stayStill || mode?.behaviour == .still }
    private var hyper: Bool { adhd || mode?.behaviour == .hyper }

    private func applyMode(named name: String?) {
        mode = fullSet.modes.first { $0.name == name } ?? fullSet.modes.first
        view.spriteSet = mode.map { fullSet.applying($0) } ?? fullSet
    }

    /// Switches mode (remembered per profile) and announces it.
    func setMode(_ name: String) {
        Self.defaults.set(name, forKey: Profiles.key("mode"))
        applyMode(named: name)
        view.special = nil; view.holdSpecial = false; specialTime = 0
        if sulking { sulking = false }
        touched()
        if still, activity == .walk { activity = .idle }
        if activity == .sleep { activity = .idle }
        activityTime = 0.5
        say(Personality.line(.modeChanged, item: name), for: 3)
    }

    /// Re-reads the settings after switching profile (each profile keeps its own).
    func reloadSettings() {
        muted = Self.defaults.bool(forKey: Profiles.key("muted"))
        stayStill = Self.defaults.bool(forKey: Profiles.key("stayStill"))
        antiGravity = Self.defaults.bool(forKey: Profiles.key("antiGravity"))
        adhd = Self.defaults.bool(forKey: Profiles.key("adhd"))
        cryin = Self.defaults.bool(forKey: Profiles.key("cryin"))
    }

    /// After this long without being hovered, clicked or dragged, Rick gets sad about your list.
    var lonelyAfter: Double = 10 * 60
    private var lastTouched = CACurrentMediaTime()
    private var vx: CGFloat = 0

    /// Sad and sulking after being ignored; stays that way until you interact.
    private(set) var sulking = false

    /// Call when the user interacts with Rick (hover, click, opening the list…).
    func touched() {
        lastTouched = CACurrentMediaTime()
        if sulking {
            sulking = false
            view.special = nil; view.holdSpecial = false; specialTime = 0
            activityTime = 1
        }
    }

    /// Returns something due soon to remind you about (nil if nothing is).
    var reminder: (() -> (text: String, overdue: Bool)?)?
    /// How often Rick brings up things that are due soon.
    var reminderInterval: ClosedRange<Double> = (15 * 60)...(25 * 60)


    /// Shows a due-soon reminder right away (also used by the menu).
    @discardableResult
    func remindNow() -> Bool {
        guard let r = reminder?() else { return false }
        if activity == .sleep { activity = .idle; activityTime = 3 }
        say(r.text, for: 9)
        if sulking { return true }                                      // keep the sad pose
        if r.overdue { play("sad", for: 6) } else { happyTime = 2 }   // overdue = disappointed, otherwise wave
        return true
    }

    /// Plays a named sprite animation (if the sprite has it) for a few seconds.
    func play(_ name: String, for seconds: Double) {
        guard view.spriteSet.anims[name] != nil, !sulking else { return }
        view.holdSpecial = false
        view.special = name
        view.specialStart = view.t
        specialTime = seconds
    }

    func setSprite(_ set: SpriteSet) {
        fullSet = set
        applyMode(named: Self.defaults.string(forKey: Profiles.key("mode")))
    }

    init() {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        view = PetView(frame: NSRect(origin: .zero, size: Self.size))
        window.contentView = view

        let vf = Self.screenFrame(for: nil)
        window.setFrameOrigin(CGPoint(x: vf.midX - Self.size.width / 2, y: vf.maxY - Self.size.height)) // drop in from the top
        vy = 0

        view.onHover = { [weak self] inside in
            guard let self else { return }
            self.hovering = inside
            guard inside else { return }
            self.touched()
            if self.activity == .sleep {
                self.activity = .idle; self.activityTime = 2
                self.say(Personality.line(.wokeUp), for: 3)
            } else if self.chatMood == nil, !self.chatOpen, self.bubbleTime <= 0 {
                self.say(Personality.line(.hover), for: 3)
            }
        }
        view.onMouseDown = { [weak self] e in self?.mouseDown(e) }
        view.onMouseDragged = { [weak self] e in self?.mouseDragged(e) }
        view.onMouseUp = { [weak self] e in self?.mouseUp(e) }
        view.onRightClick = { [weak self] e in self?.onRightClick?(e) }
    }

    func start() {
        window.orderFrontRegardless()
        say(Personality.line(.greeting), for: 6)
        schedule(1.0 / 60.0)
    }

    // MARK: hide / show

    /// Hidden Rick does no work at all: the timer stops, nothing animates or checks reminders.
    func hide() {
        window.orderOut(nil)
        timer?.invalidate(); timer = nil; interval = 0
    }

    func show() {
        guard !window.isVisible || timer == nil else { return }
        window.orderFrontRegardless()
        lastTick = CACurrentMediaTime()
        touched()
        schedule(1.0 / 30.0)
    }

    var isShown: Bool { window.isVisible }

    // MARK: frame rate (keeps CPU low)

    private var interval: TimeInterval = 0
    private var lastDrawn: [AnyHashable] = []

    private func schedule(_ seconds: TimeInterval) {
        guard seconds != interval || timer == nil else { return }
        interval = seconds
        timer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = seconds * 0.2              // let macOS batch wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Smooth only when something is actually moving; slow ticks otherwise.
    /// Lowest of all when muted and staying still.
    private var desiredInterval: TimeInterval {
        switch activity {
        case .drag, .fall: return 1.0 / 60.0
        case .walk: return 1.0 / 30.0
        default: break
        }
        if view.squash > 0 { return 1.0 / 30.0 }                 // landing squish
        if muted && still { return 1.0 / 4.0 }               // lowest-power mode
        if activity == .sleep { return 1.0 / 6.0 }
        if view.spriteSet.isEmpty { return 1.0 / 15.0 }           // drawn pet breathes and blinks
        return 1.0 / 10.0                                          // sprite frames run at 4–6 fps
    }

    /// What's visible right now; if it hasn't changed since the last frame, skip redrawing.
    private var visibleState: [AnyHashable] {
        guard let f = view.spriteFrame else { return [] }            // drawn pet: always redraw
        return [ObjectIdentifier(f.image), f.flip, view.bubbleText ?? "", view.mood == .thinking,
                (view.squash * 20).rounded(), view.mood == .walking ? (view.t * 9).rounded() : 0]
    }

    /// Lines waiting to be said one after another (e.g. reading out the list).
    private var queue: [(text: String, seconds: Double)] = []

    /// Says each line in turn. Explicitly asked for, so it shows even when muted.
    func sayInOrder(_ lines: [String], each seconds: Double = 3.5) {
        queue = lines.map { ($0, seconds) }
        bubbleTime = 0
        if activity == .walk || activity == .sleep { activity = .idle }
        activityTime = Double(lines.count) * seconds + 1     // stand still while talking
        nextInQueue()
    }

    private func nextInQueue() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        view.bubbleText = next.text
        bubbleTime = next.seconds
    }

    var isReadingList: Bool { !queue.isEmpty }

    func say(_ text: String?, for seconds: Double) {
        if muted, text != nil { return }
        if !queue.isEmpty, text != nil { return }           // don't interrupt a rundown
        view.bubbleText = text
        bubbleTime = seconds
    }

    func celebrate() { happyTime = 1.6 }

    // MARK: input

    private func mouseDown(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        touched()
        dragStart = m
        dragOffset = CGPoint(x: m.x - window.frame.minX, y: m.y - window.frame.minY)
        didDrag = false
    }

    private func mouseDragged(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        if !didDrag, hypot(m.x - dragStart.x, m.y - dragStart.y) < 4 { return }
        if !didDrag { didDrag = true; say(Personality.line(.dragged), for: 2.5) }
        activity = .drag
        window.setFrameOrigin(CGPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y))
    }

    private func mouseUp(_ e: NSEvent) {
        if didDrag {
            if antiGravity {
                activity = .idle; activityTime = 2          // just hang there
            } else {
                activity = .fall; vy = 0; vx = 0; thrown = true
            }
        } else {
            onClick?()
        }
        didDrag = false
    }

    // MARK: loop

    private static func screenFrame(for window: NSWindow?) -> NSRect {
        if let s = window?.screen { return s.visibleFrame }
        return (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.5)
        lastTick = now
        view.t += CGFloat(dt)

        // blinking
        blinkTimer -= dt
        if blinkTimer <= 0 { blinkPhase = 0.0001; blinkTimer = .random(in: 2.5...5.5) }
        if blinkPhase > 0 {
            blinkPhase += dt
            view.blink = CGFloat(sin(min(blinkPhase / 0.18, 1) * .pi))
            if blinkPhase > 0.18 { blinkPhase = 0; view.blink = 0 }
        }
        // bubble + happy timers
        if bubbleTime > 0 {
            bubbleTime -= dt
            if bubbleTime <= 0 { view.bubbleText = nil; nextInQueue() }
        }
        if happyTime > 0 { happyTime -= dt }
        if specialTime > 0 { specialTime -= dt; if specialTime <= 0 { view.special = nil } }
        if activity == .walk || activity == .drag { view.special = nil; specialTime = 0 }
        if view.squash > 0 { view.squash = max(0, view.squash - CGFloat(dt) * 4) }

        let vf = Self.screenFrame(for: window)
        let floorY = vf.minY - 2
        let minX = vf.minX - 20, maxX = vf.maxX - Self.size.width + 20
        var origin = window.frame.origin

        switch activity {
        case .drag:
            break
        case .fall:
            vy -= 2400 * CGFloat(dt)
            origin.y += vy * CGFloat(dt)
            origin.x += vx * CGFloat(dt)
            if origin.x < minX || origin.x > maxX { vx = -vx }           // bounce off screen edges
            origin.x = min(max(origin.x, minX), maxX)
            if origin.y <= floorY {
                origin.y = floorY
                view.squash = min(1, abs(vy) / 900 + 0.3)
                if thrown, abs(vy) > 700 { say(Personality.line(.landed), for: 2.5) }
                thrown = false
                vy = 0; vx = 0
                activity = .idle; activityTime = hyper ? .random(in: 0.2...0.8) : 1.2
            }
            window.setFrameOrigin(origin)
        case .walk:
            if chatOpen || hovering || chatMood != nil || still { activity = .idle; activityTime = 1; break }
            let dx = targetX - origin.x
            if abs(dx) < 2 {
                activity = .idle; activityTime = hyper ? .random(in: 0.3...1.2) : .random(in: 2...6)
            } else {
                view.facing = dx > 0 ? 1 : -1
                origin.x += view.facing * min(abs(dx), walkSpeed * CGFloat(dt))
                if !antiGravity { origin.y = floorY }
                window.setFrameOrigin(origin)
            }
        case .idle, .sleep:
            if !antiGravity, origin.y > floorY + 1 { activity = .fall; vy = 0; break }   // gravity back on
            if antiGravity, origin.y < floorY { origin.y = floorY; window.setFrameOrigin(origin) }
            activityTime -= dt
            if activityTime <= 0, !chatOpen, !hovering, chatMood == nil, !sulking {
                decideNext(minX: minX, maxX: maxX)
            }
        }

        // every so often: remind about things due soon (wakes Rick up if needed)
        if activity != .drag && activity != .fall {
            reminderTimer -= dt
            if reminderTimer <= 0 {
                if chatOpen || hovering {
                    reminderTimer = 60                       // list is open, try again later
                } else {
                    remindNow()
                    reminderTimer = .random(in: reminderInterval)
                }
            }
        }

        // ignored for a while → sad, nudges you about the list
        if now - lastTouched > lonelyAfter, !chatOpen, !sulking, activity != .drag, activity != .fall {
            sulk()
        }

        // random chatter when wandering
        if !chatOpen, chatMood == nil, !sulking, activity != .drag, activity != .sleep, bubbleTime <= 0 {
            chatterTimer -= dt
            if chatterTimer <= 0 {
                chatterTimer = .random(in: 45...90)
                say(Personality.line(.idle), for: 5)
                if let extra = view.spriteSet.idleExtras.randomElement(), Bool.random() {
                    play(extra, for: .random(in: 4...7))   // e.g. strum the guitar, have a think
                }
            }
        }

        view.mood = currentMood()
        let state = visibleState
        if state.isEmpty || state != lastDrawn || view.mood == .dragged || view.mood == .falling {
            view.needsDisplay = true
            lastDrawn = state
        }
        schedule(desiredInterval)
    }

    /// Gets sad about being ignored: nags about the list, then holds the slumped pose
    /// (no wandering, no chatter) until you hover, click or drag him.
    func sulk() {
        lastTouched = CACurrentMediaTime()
        if activity == .walk || activity == .sleep { activity = .idle }
        say(Personality.line(.lonely), for: 8)
        if view.spriteSet.anims["sad"] != nil {
            view.special = "sad"; view.specialStart = view.t; view.holdSpecial = true
            specialTime = .infinity
            sulking = true
        }
    }

    /// Picks what to do next after standing around.
    private func decideNext(minX: CGFloat, maxX: CGFloat) {
        let roll = Double.random(in: 0...1)
        if cryin, canCry { activity = .idle; activityTime = .random(in: 4...8); return }   // busy cryin'
        if hyper {
            if !antiGravity, roll < 0.45 {                       // boing
                activity = .fall
                vy = .random(in: 650...950)
                vx = .random(in: 80...220) * (Bool.random() ? 1 : -1)
                view.facing = vx > 0 ? 1 : -1
            } else if !still {
                activity = .walk
                targetX = .random(in: minX...maxX)
            } else {
                activityTime = .random(in: 0.3...1)
                play((["wave", "jump", "think"] + view.spriteSet.idleExtras).randomElement()!, for: 1.5)   // fidget in place
            }
            return
        }
        if activity == .idle, roll < 0.12 {
            activity = .sleep; activityTime = .random(in: 10...20)
        } else if still || roll < 0.45 {
            // hang around: usually strum the guitar if the sprite has one (or do a random move)
            activity = .idle; activityTime = .random(in: 6...12)
            if Double.random(in: 0...1) < 0.7,
               let move = view.spriteSet.anims["music"] != nil ? "music" : view.spriteSet.idleExtras.randomElement() {
                play(move, for: activityTime)
            }
        } else {
            activity = .walk
            targetX = .random(in: minX...maxX)
        }
    }

    private func currentMood() -> PetMood {
        switch activity {
        case .drag: return .dragged
        case .fall: return .falling
        default: break
        }
        if let m = chatMood { return m }
        if hovering || happyTime > 0 { return .happy }
        switch activity {
        case .walk: return .walking
        case .sleep: return .sleeping
        default: return .idle
        }
    }
}
