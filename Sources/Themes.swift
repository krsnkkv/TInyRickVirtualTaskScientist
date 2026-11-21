import Cocoa

/// Backgrounds for the list window, painted in code (no image files), so they stay crisp at any size.
/// A picture chosen with "Choose Picture…" still wins over the theme.
enum ListTheme: String, CaseIterable {
    case space, garden, plain

    var title: String {
        switch self {
        case .space: return "Space"
        case .garden: return "Garden"
        case .plain: return "Plain"
        }
    }

    /// Text drawn straight on the background (the Today strip).
    var ink: NSColor {
        self == .garden ? NSColor(hex: 0x3B4A3F) : .white
    }

    /// Boxes go slightly see-through with rounded corners on a themed background.
    var translucentBoxes: Bool { self != .plain }

    /// The theme a profile gets until you pick one: Mochi → Garden, everyone else → Space.
    static func defaultFor(profileID: String) -> ListTheme {
        profileID == "mochi" ? .garden : .space
    }

    /// The active profile's theme (each profile remembers its own).
    static var current: ListTheme {
        get { UserDefaults.standard.string(forKey: Profiles.key("listTheme")).flatMap(ListTheme.init) ?? defaultFor(profileID: Profiles.activeID) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Profiles.key("listTheme")) }
    }

    // MARK: painting

    func draw(in rect: NSRect) {
        switch self {
        case .plain:
            NSColor(hex: 0x1C2333).setFill(); rect.fill()
        case .space:
            drawSpace(rect)
        case .garden:
            drawGarden(rect)
        }
    }

    private func drawSpace(_ r: NSRect) {
        NSGradient(colors: [NSColor(hex: 0x070B1F), NSColor(hex: 0x16123A), NSColor(hex: 0x2B1648)],
                   atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: r, angle: -70)
        // soft nebula glows
        glow(at: CGPoint(x: r.width * 0.18, y: r.height * 0.78), radius: r.width * 0.42, color: NSColor(hex: 0x7B3FE4, alpha: 0.28))
        glow(at: CGPoint(x: r.width * 0.86, y: r.height * 0.22), radius: r.width * 0.38, color: NSColor(hex: 0x1FB5C9, alpha: 0.20))
        glow(at: CGPoint(x: r.width * 0.62, y: r.height * 0.95), radius: r.width * 0.25, color: NSColor(hex: 0xE0529C, alpha: 0.16))
        // stars: same sky every time (seeded), density scales with the window
        var rng = SeededRandom(seed: 42)
        let count = Int(r.width * r.height / 1800)
        for _ in 0..<count {
            let p = CGPoint(x: rng.next() * r.width, y: rng.next() * r.height)
            let size = 0.6 + pow(rng.next(), 3) * 2.2
            let alpha = 0.25 + rng.next() * 0.7
            NSColor(white: 1, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: size, height: size)).fill()
            if size > 2.3 { sparkle(at: CGPoint(x: p.x + size / 2, y: p.y + size / 2), length: size * 3, alpha: alpha * 0.6) }
        }
    }

    private func drawGarden(_ r: NSRect) {
        NSGradient(colors: [NSColor(hex: 0xFFF4E6), NSColor(hex: 0xF3F7E8), NSColor(hex: 0xDDF2E3)],
                   atLocations: [0, 0.5, 1], colorSpace: .sRGB)?.draw(in: r, angle: -80)
        glow(at: CGPoint(x: r.width * 0.15, y: r.height * 0.85), radius: r.width * 0.35, color: NSColor(hex: 0xFFC9D6, alpha: 0.45))
        glow(at: CGPoint(x: r.width * 0.88, y: r.height * 0.75), radius: r.width * 0.30, color: NSColor(hex: 0xFFE3A8, alpha: 0.40))
        glow(at: CGPoint(x: r.width * 0.70, y: r.height * 0.10), radius: r.width * 0.40, color: NSColor(hex: 0xB9E8C8, alpha: 0.55))
        // little floating leaves and dots
        var rng = SeededRandom(seed: 7)
        let leafColors = [NSColor(hex: 0x86D39C), NSColor(hex: 0xA8DDB5), NSColor(hex: 0xF6B8C8), NSColor(hex: 0xFFD58A)]
        for i in 0..<Int(r.width * r.height / 9000) {
            let p = CGPoint(x: rng.next() * r.width, y: rng.next() * r.height)
            let color = leafColors[i % leafColors.count].withAlphaComponent(0.35 + rng.next() * 0.35)
            if i % 3 == 0 {
                color.setFill()
                let d = 3 + rng.next() * 4
                NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: d, height: d)).fill()
            } else {
                let leaf = NSBezierPath(ovalIn: NSRect(x: -7, y: -3, width: 14, height: 6))
                var t = AffineTransform(translationByX: p.x, byY: p.y)
                t.rotate(byRadians: rng.next() * .pi)
                leaf.transform(using: t)
                color.setFill(); leaf.fill()
            }
        }
    }

    private func glow(at c: CGPoint, radius: CGFloat, color: NSColor) {
        NSGradient(colors: [color, color.withAlphaComponent(0)])?
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: radius, options: [])
    }

    private func sparkle(at c: CGPoint, length: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: c.x - length, y: c.y)); p.line(to: CGPoint(x: c.x + length, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - length)); p.line(to: CGPoint(x: c.x, y: c.y + length))
        p.lineWidth = 0.6
        NSColor(white: 1, alpha: alpha).setStroke(); p.stroke()
    }
}

/// Tiny deterministic random numbers so the sky looks the same every time it's drawn.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    /// 0..<1
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 1_000_000) / 1_000_000
    }
}
