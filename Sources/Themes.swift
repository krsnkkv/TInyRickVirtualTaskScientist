import Cocoa

/// Looks for the list window: a background painted in code (no image files, crisp at any size)
/// plus matching cards for the four boxes. Each profile has one, and a profile's modes can bring
/// their own (sprite.json: `{ "name": "Party Cannon", "theme": "party", … }`).
/// A picture chosen with "Choose Picture…" still wins over the background.
enum ListTheme: String, CaseIterable {
    case space, garden, infinity, candy, neon, party, storm, rain, bubblegum, calm, plain

    var title: String {
        switch self {
        case .space: return "Space"
        case .garden: return "Garden"
        case .infinity: return "Infinity"
        case .candy: return "Candy"
        case .neon: return "Neon"
        case .party: return "Party"
        case .storm: return "Storm"
        case .rain: return "Rain"
        case .bubblegum: return "Bubblegum"
        case .calm: return "Calm"
        case .plain: return "Plain"
        }
    }

    /// Light background → dark text and controls drawn on it.
    var isLight: Bool { [.garden, .candy, .party, .bubblegum, .calm].contains(self) }

    /// Text drawn straight on the background (the Today strip).
    var ink: NSColor { isLight ? NSColor(hex: 0x3B3046) : .white }

    /// How the four boxes look on this background.
    struct Card {
        var fills: [NSColor]        // one per box: U&I, U&NI, NU&I, NU&NI
        var text: NSColor
        var border: NSColor
        var borderWidth: CGFloat = 0
        var glow: NSColor? = nil    // coloured shadow instead of a soft dark one
    }

    var card: Card {
        switch self {
        case .space:
            return Card(fills: [0xFFF3B0, 0xC8F7C5, 0xFFD3DC, 0xCFDBFF].map { NSColor(hex: $0, alpha: 0.92) },
                        text: NSColor(hex: 0x1E1B2E), border: NSColor(white: 1, alpha: 0.5), borderWidth: 1)
        case .garden:
            return Card(fills: [0xFFF6C9, 0xDDF5E1, 0xFFE0E6, 0xE3EBFF].map { NSColor(hex: $0, alpha: 0.9) },
                        text: NSColor(hex: 0x33403A), border: NSColor(white: 1, alpha: 0.8), borderWidth: 1)
        case .infinity:
            return Card(fills: [0xF4F8FF, 0xE8F1FF, 0xEEF0FF, 0xE6F6FF].map { NSColor(hex: $0, alpha: 0.9) },
                        text: NSColor(hex: 0x10162B), border: NSColor(hex: 0x9CC8FF, alpha: 0.9), borderWidth: 1.5,
                        glow: NSColor(hex: 0x6FB6FF, alpha: 0.7))
        case .candy:
            return Card(fills: [0xFFC9E1, 0xFFDCEC, 0xFFD1E8, 0xFFE6F2].map { NSColor(hex: $0, alpha: 0.95) },
                        text: NSColor(hex: 0x4A1A3A), border: .white, borderWidth: 2)
        case .neon:
            return Card(fills: [0x26081C, 0x1E0A1A, 0x2A0A22, 0x1C0818].map { NSColor(hex: $0, alpha: 0.92) },
                        text: NSColor(hex: 0xFFE8F5), border: NSColor(hex: 0xFF3DB4), borderWidth: 2,
                        glow: NSColor(hex: 0xFF3DB4, alpha: 0.9))
        case .party:
            return Card(fills: [0xFFD0E6, 0xFFE2EF, 0xFFC4DE, 0xFFDAEB].map { NSColor(hex: $0, alpha: 0.95) },
                        text: NSColor(hex: 0x4A1638), border: .white, borderWidth: 2.5)
        case .storm:
            return Card(fills: [0x2C0D22, 0x24101E, 0x300E26, 0x220C1C].map { NSColor(hex: $0, alpha: 0.9) },
                        text: NSColor(hex: 0xFFE6F2), border: NSColor(hex: 0xE0287A, alpha: 0.85), borderWidth: 1.5,
                        glow: NSColor(hex: 0xE0287A, alpha: 0.6))
        case .rain:
            return Card(fills: [0xF1DDE6, 0xEDD6E0, 0xF4E1E9, 0xEAD3DE].map { NSColor(hex: $0, alpha: 0.9) },
                        text: NSColor(hex: 0x3F2433), border: NSColor(white: 1, alpha: 0.6), borderWidth: 1)
        case .bubblegum:
            return Card(fills: [0xFFE0EE, 0xFFEAF3, 0xFFD6EA, 0xFFE4F1].map { NSColor(hex: $0, alpha: 0.95) },
                        text: NSColor(hex: 0x5A2347), border: NSColor(hex: 0xFF8CC6), borderWidth: 2)
        case .calm:
            return Card(fills: [0xFDF3F6, 0xFAEDF2, 0xFCF1F4, 0xF8EAF0].map { NSColor(hex: $0, alpha: 0.95) },
                        text: NSColor(hex: 0x4A3540), border: NSColor(hex: 0xF0D3DF), borderWidth: 1)
        case .plain:
            return Card(fills: [0xFBF3A3, 0xB5FCA7, 0xFFC9C9, 0xB9CBFC].map { NSColor(hex: $0) },
                        text: .black, border: .clear)
        }
    }

    /// The theme a profile gets until you pick one.
    static func defaultFor(profileID: String) -> ListTheme {
        switch profileID {
        case "mochi": return .garden
        case "gojo": return .infinity
        case "pinkie": return .candy
        default: return .space
        }
    }

    /// Set while the pet is in a mode that brings its own look; wins over the profile's pick.
    static var modeOverride: ListTheme?

    /// What the list shows right now: the mode's look, else the active profile's pick.
    static var current: ListTheme { modeOverride ?? chosen }

    /// The active profile's own pick (each profile remembers its own).
    static var chosen: ListTheme {
        get { UserDefaults.standard.string(forKey: Profiles.key("listTheme")).flatMap(ListTheme.init) ?? defaultFor(profileID: Profiles.activeID) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Profiles.key("listTheme")) }
    }

    // MARK: painting

    func draw(in r: NSRect) {
        var rng = SeededRandom(seed: UInt64(rawValue.count * 31 + 7))
        switch self {
        case .plain:
            NSColor(hex: 0x1C2333).setFill(); r.fill()

        case .space:
            gradient([0x070B1F, 0x16123A, 0x2B1648], r, angle: -70)
            glow(r, 0.18, 0.78, 0.42, NSColor(hex: 0x7B3FE4, alpha: 0.28))
            glow(r, 0.86, 0.22, 0.38, NSColor(hex: 0x1FB5C9, alpha: 0.20))
            glow(r, 0.62, 0.95, 0.25, NSColor(hex: 0xE0529C, alpha: 0.16))
            for _ in 0..<Int(r.width * r.height / 1800) {
                let p = point(&rng, r), size = 0.6 + pow(rng.next(), 3) * 2.2, a = 0.25 + rng.next() * 0.7
                dot(p, size, NSColor(white: 1, alpha: a))
                if size > 2.3 { sparkle(CGPoint(x: p.x + size / 2, y: p.y + size / 2), size * 3, NSColor(white: 1, alpha: a * 0.6)) }
            }

        case .garden:
            gradient([0xFFF4E6, 0xF3F7E8, 0xDDF2E3], r, angle: -80)
            glow(r, 0.15, 0.85, 0.35, NSColor(hex: 0xFFC9D6, alpha: 0.45))
            glow(r, 0.88, 0.75, 0.30, NSColor(hex: 0xFFE3A8, alpha: 0.40))
            glow(r, 0.70, 0.10, 0.40, NSColor(hex: 0xB9E8C8, alpha: 0.55))
            let colors = [0x86D39C, 0xA8DDB5, 0xF6B8C8, 0xFFD58A]
            for i in 0..<Int(r.width * r.height / 9000) {
                let p = point(&rng, r), c = NSColor(hex: UInt32(colors[i % 4]), alpha: 0.35 + rng.next() * 0.35)
                if i % 3 == 0 { dot(p, 3 + rng.next() * 4, c) } else { leaf(p, 14, 6, rng.next() * .pi, c) }
            }

        case .infinity:
            gradient([0x02030A, 0x0A1030, 0x101A4A], r, angle: -90)
            glow(r, 0.5, 0.5, 0.75, NSColor(hex: 0x3D7BFF, alpha: 0.25))
            // rings of light spreading from the middle
            let c = CGPoint(x: r.midX, y: r.midY)
            for i in 1...7 {
                let rad = CGFloat(i) * max(r.width, r.height) / 9
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                ring.lineWidth = 1.2
                NSColor(hex: 0x9CD1FF, alpha: 0.22 - CGFloat(i) * 0.025).setStroke(); ring.stroke()
            }
            for _ in 0..<Int(r.width * r.height / 2600) {
                dot(point(&rng, r), 0.6 + rng.next() * 1.6, NSColor(hex: 0xCFE6FF, alpha: 0.2 + rng.next() * 0.6))
            }

        case .candy:
            gradient([0xFFB3D6, 0xFFD6EA, 0xFFC2E0], r, angle: -60)
            glow(r, 0.2, 0.8, 0.4, NSColor(hex: 0xFF9ACB, alpha: 0.35))
            glow(r, 0.85, 0.2, 0.4, NSColor(hex: 0xFFE3F1, alpha: 0.45))
            let sprinkles = [0xFF4FA0, 0xFFFFFF, 0xE0307F, 0xFF8CC4, 0xC2185B]
            for i in 0..<Int(r.width * r.height / 2200) {
                let p = point(&rng, r)
                let c = NSColor(hex: UInt32(sprinkles[i % sprinkles.count]), alpha: 0.75)
                stroke(p, length: 9, angle: rng.next() * .pi, width: 3, c)
            }

        case .neon:
            NSColor(hex: 0x07040F).setFill(); r.fill()
            glow(r, 0.15, 0.85, 0.45, NSColor(hex: 0xFF3DB4, alpha: 0.28))
            glow(r, 0.85, 0.15, 0.45, NSColor(hex: 0xFF7AD1, alpha: 0.22))
            // perspective grid on the floor
            let grid = NSBezierPath(); grid.lineWidth = 1
            let horizon = r.height * 0.42
            for i in 0...14 {
                let x = r.width * CGFloat(i) / 14
                grid.move(to: CGPoint(x: r.midX + (x - r.midX) * 0.15, y: horizon)); grid.line(to: CGPoint(x: x * 3 - r.width, y: 0))
            }
            for i in 1...8 { let y = horizon * pow(CGFloat(i) / 8, 2); grid.move(to: CGPoint(x: 0, y: y)); grid.line(to: CGPoint(x: r.width, y: y)) }
            NSColor(hex: 0xFF5CC4, alpha: 0.4).setStroke(); grid.stroke()
            let zig = [0xFF3DB4, 0xFF8AD8, 0xFFFFFF, 0xE0287A]
            for i in 0..<Int(r.width * r.height / 14000) {
                zigzag(point(&rng, r), NSColor(hex: UInt32(zig[i % zig.count]), alpha: 0.85))
            }

        case .party:
            gradient([0xFF9FCB, 0xFFC4E0, 0xFFE3F0], r, angle: -45)
            // streamers
            for i in 0..<5 {
                let s = NSBezierPath(); s.lineWidth = 5
                let x0 = r.width * (0.1 + CGFloat(i) * 0.2)
                s.move(to: CGPoint(x: x0, y: r.height))
                s.curve(to: CGPoint(x: x0 + 30, y: r.height * 0.55),
                        controlPoint1: CGPoint(x: x0 - 50, y: r.height * 0.85), controlPoint2: CGPoint(x: x0 + 70, y: r.height * 0.75))
                NSColor(hex: UInt32([0xFF2E8B, 0xFFFFFF, 0xC2185B, 0xFF7AB8, 0xE91E63][i]), alpha: 0.55).setStroke(); s.stroke()
            }
            let confetti = [0xFF2E8B, 0xFFFFFF, 0xC2185B, 0xFF7AB8, 0xE91E63, 0xFFB3D6]
            for i in 0..<Int(r.width * r.height / 1500) {
                let c = NSColor(hex: UInt32(confetti[i % confetti.count]), alpha: 0.8)
                if i % 4 == 0 { dot(point(&rng, r), 5, c) } else { stroke(point(&rng, r), length: 8, angle: rng.next() * .pi, width: 4, c) }
            }

        case .storm:
            gradient([0x0C070B, 0x2A0B1E, 0x4D1035], r, angle: -95)
            glow(r, 0.5, 1.0, 0.6, NSColor(hex: 0xFF2E8B, alpha: 0.2))
            for i in 0..<Int(r.width * r.height / 5000) {           // drifting embers
                dot(point(&rng, r), 1 + rng.next() * 2.5, NSColor(hex: i % 3 == 0 ? 0xFFB3D6 : 0xFF3D9A, alpha: 0.25 + rng.next() * 0.5))
            }
            for i in 0..<3 { bolt(CGPoint(x: r.width * (0.18 + CGFloat(i) * 0.33), y: r.height), r.height * 0.45, &rng) }

        case .rain:
            gradient([0x7A4E66, 0x9C6E86, 0xC293AA], r, angle: -90)
            glow(r, 0.3, 1.0, 0.5, NSColor(white: 1, alpha: 0.15))
            let drops = NSBezierPath(); drops.lineWidth = 1.2; drops.lineCapStyle = .round
            for _ in 0..<Int(r.width * r.height / 900) {
                let p = point(&rng, r), len = 6 + rng.next() * 10
                drops.move(to: p); drops.line(to: CGPoint(x: p.x - len * 0.25, y: p.y - len))
            }
            NSColor(white: 1, alpha: 0.35).setStroke(); drops.stroke()

        case .bubblegum:
            gradient([0xFF9FCF, 0xFFC1DF, 0xFFDDEB], r, angle: -70)
            for i in 0..<Int(max(6, r.width * r.height / 22000)) {       // big floaty bubbles
                let p = point(&rng, r), d = 30 + rng.next() * 90
                let b = NSRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
                NSColor(white: 1, alpha: 0.16).setFill(); NSBezierPath(ovalIn: b).fill()
                let o = NSBezierPath(ovalIn: b); o.lineWidth = 2
                NSColor(white: 1, alpha: 0.45).setStroke(); o.stroke()
                dot(CGPoint(x: b.minX + d * 0.25, y: b.maxY - d * 0.35), d * 0.14, NSColor(white: 1, alpha: i % 2 == 0 ? 0.7 : 0.5))
            }

        case .calm:
            gradient([0xFCF3F5, 0xF8E6EC, 0xF2D9E3], r, angle: -90)
            for i in 0..<5 {                                              // soft rolling hills
                let y = r.height * (0.06 + CGFloat(i) * 0.08)
                let hill = NSBezierPath()
                hill.move(to: CGPoint(x: 0, y: 0)); hill.line(to: CGPoint(x: 0, y: y))
                hill.curve(to: CGPoint(x: r.width, y: y * 0.8),
                           controlPoint1: CGPoint(x: r.width * 0.3, y: y + 40), controlPoint2: CGPoint(x: r.width * 0.7, y: y - 30))
                hill.line(to: CGPoint(x: r.width, y: 0)); hill.close()
                NSColor(hex: 0xE59AB8, alpha: 0.12).setFill(); hill.fill()
            }
            glow(r, 0.8, 0.85, 0.25, NSColor(hex: 0xFFE0EC, alpha: 0.7))
        }
    }

    // MARK: brushes

    private func gradient(_ hexes: [UInt32], _ r: NSRect, angle: CGFloat) {
        NSGradient(colors: hexes.map { NSColor(hex: $0) }, atLocations: [0, 0.5, 1], colorSpace: .sRGB)?.draw(in: r, angle: angle)
    }
    private func point(_ rng: inout SeededRandom, _ r: NSRect) -> CGPoint { CGPoint(x: rng.next() * r.width, y: rng.next() * r.height) }
    private func glow(_ r: NSRect, _ fx: CGFloat, _ fy: CGFloat, _ fr: CGFloat, _ color: NSColor) {
        let c = CGPoint(x: r.width * fx, y: r.height * fy)
        NSGradient(colors: [color, color.withAlphaComponent(0)])?.draw(fromCenter: c, radius: 0, toCenter: c, radius: r.width * fr, options: [])
    }
    private func dot(_ p: CGPoint, _ d: CGFloat, _ c: NSColor) {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: d, height: d)).fill()
    }
    private func leaf(_ p: CGPoint, _ w: CGFloat, _ h: CGFloat, _ angle: CGFloat, _ c: NSColor) {
        let l = NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
        var t = AffineTransform(translationByX: p.x, byY: p.y); t.rotate(byRadians: angle)
        l.transform(using: t); c.setFill(); l.fill()
    }
    private func stroke(_ p: CGPoint, length: CGFloat, angle: CGFloat, width: CGFloat, _ c: NSColor) {
        let s = NSBezierPath(); s.lineWidth = width; s.lineCapStyle = .round
        s.move(to: p); s.line(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
        c.setStroke(); s.stroke()
    }
    private func sparkle(_ c: CGPoint, _ length: CGFloat, _ color: NSColor) {
        let p = NSBezierPath(); p.lineWidth = 0.6
        p.move(to: CGPoint(x: c.x - length, y: c.y)); p.line(to: CGPoint(x: c.x + length, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - length)); p.line(to: CGPoint(x: c.x, y: c.y + length))
        color.setStroke(); p.stroke()
    }
    private func zigzag(_ p: CGPoint, _ c: NSColor) {
        let z = NSBezierPath(); z.lineWidth = 2.5; z.lineJoinStyle = .round
        z.move(to: p)
        for i in 1...4 { z.line(to: CGPoint(x: p.x + CGFloat(i) * 7, y: p.y + (i % 2 == 0 ? 0 : 7))) }
        c.setStroke(); z.stroke()
    }
    private func bolt(_ top: CGPoint, _ length: CGFloat, _ rng: inout SeededRandom) {
        let b = NSBezierPath(); b.lineWidth = 2.5; b.lineJoinStyle = .miter
        var p = top; b.move(to: p)
        for _ in 0..<6 {
            p = CGPoint(x: p.x + (rng.next() - 0.5) * 40, y: p.y - length / 6)
            b.line(to: p)
        }
        NSColor(hex: 0xFF3D9A, alpha: 0.28).setStroke(); b.lineWidth = 8; b.stroke()
        NSColor(hex: 0xFFD6EA, alpha: 0.8).setStroke(); b.lineWidth = 2; b.stroke()
    }
}

/// Tiny deterministic random numbers so a background looks the same every time it's drawn.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    /// 0..<1
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 1_000_000) / 1_000_000
    }
}
