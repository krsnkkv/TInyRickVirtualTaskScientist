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

    /// The frame to show right now: walk cycle while walking, standing loop otherwise, still while asleep.
    var sprite: CGImage? {
        let idle = spriteSet.idle
        guard !idle.isEmpty else { return nil }
        switch mood {
        case .walking:
            let walk = spriteSet.walk
            return walk[Int(t * 10) % walk.count]
        case .sleeping, .falling:
            return idle[0]
        default:
            return idle[Int(t * 5) % idle.count]
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
        // Whole-number pixel scale on screen keeps pixel art crisp (aim for ~70pt tall).
        let k = max(1, (70 / CGFloat(img.height)).rounded())
        let h: CGFloat = CGFloat(img.height) * k / scale * sy
        let w = h * CGFloat(img.width) / CGFloat(img.height) * sx / sy
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: cx, y: bottom)
        if facing < 0 { ctx.scaleBy(x: -1, y: 1) }      // sprites are drawn facing right
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
    private var thrown = false          // dropped by the user (vs. the first fall onto the screen)
    private var timer: Timer?

    static let size = NSSize(width: 230, height: 210)
    private let walkSpeed: CGFloat = 40

    /// Returns something due soon to remind you about (nil if nothing is).
    var reminder: (() -> String?)?
    /// How often Rick brings up things that are due soon.
    var reminderInterval: ClosedRange<Double> = (15 * 60)...(25 * 60)


    /// Shows a due-soon reminder right away (also used by the menu).
    @discardableResult
    func remindNow() -> Bool {
        guard let text = reminder?() else { return false }
        if activity == .sleep { activity = .idle; activityTime = 3 }
        say(text, for: 9)
        happyTime = 2
        return true
    }

    func setSprite(_ set: SpriteSet) {
        view.spriteSet = set
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
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func say(_ text: String?, for seconds: Double) {
        view.bubbleText = text
        bubbleTime = seconds
    }

    func celebrate() { happyTime = 1.6 }

    // MARK: input

    private func mouseDown(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
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
            activity = .fall; vy = 0; thrown = true
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
        let dt = min(now - lastTick, 0.05)
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
        if bubbleTime > 0 { bubbleTime -= dt; if bubbleTime <= 0 { view.bubbleText = nil } }
        if happyTime > 0 { happyTime -= dt }
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
            origin.x = min(max(origin.x, minX), maxX)
            if origin.y <= floorY {
                origin.y = floorY
                view.squash = min(1, abs(vy) / 900 + 0.3)
                if thrown, abs(vy) > 700 { say(Personality.line(.landed), for: 2.5) }
                thrown = false
                vy = 0
                activity = .idle; activityTime = 1.2
            }
            window.setFrameOrigin(origin)
        case .walk:
            if chatOpen || hovering || chatMood != nil { activity = .idle; activityTime = 1; break }
            let dx = targetX - origin.x
            if abs(dx) < 2 {
                activity = .idle; activityTime = .random(in: 2...6)
            } else {
                view.facing = dx > 0 ? 1 : -1
                origin.x += view.facing * min(abs(dx), walkSpeed * CGFloat(dt))
                origin.y = floorY
                window.setFrameOrigin(origin)
            }
        case .idle, .sleep:
            if abs(origin.y - floorY) > 1 { activity = .fall; break }   // e.g. screen layout changed
            activityTime -= dt
            if activityTime <= 0, !chatOpen, !hovering, chatMood == nil {
                let roll = Double.random(in: 0...1)
                if activity == .idle && roll < 0.18 {
                    activity = .sleep; activityTime = .random(in: 10...20)
                } else {
                    activity = .walk
                    targetX = .random(in: minX...maxX)
                }
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

        // random chatter when wandering
        if !chatOpen, chatMood == nil, activity != .drag, activity != .sleep, bubbleTime <= 0 {
            chatterTimer -= dt
            if chatterTimer <= 0 {
                chatterTimer = .random(in: 45...90)
                say(Personality.line(.idle), for: 5)
            }
        }

        view.mood = currentMood()
        view.needsDisplay = true
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
