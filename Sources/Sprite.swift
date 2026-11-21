import Cocoa

/// Custom pixel-art sprite for Rick, kept at ~/Library/Application Support/MochiPet/sprite.png.
///
/// Works with a single image or a whole sprite sheet:
/// - A solid background (top-left pixel colour, e.g. white) is made transparent.
/// - On a sheet, the frame grid is found automatically from how the pixels repeat, partial
///   pieces (loose hair, effects…) are skipped, and the frames play as an animation.
/// - Sprites should face **right**; Rick flips them when walking left (unless a `walkLeft` row exists).
///
/// Which row is which animation comes from an optional `sprite.json` next to the sprite, e.g.
///     { "idle": 1, "walk": 2, "walkLeft": 3, "wave": 4, "sleep": "6:1-2", "sad": "6:3-8" }
/// Rows are numbered from 1; `"6:1-2"` means frames 1–2 of row 6.
/// Without it: row 1 = standing, row 2 = walking.
/// Known names: idle, walk, walkLeft, wave (hovered/happy), jump (dragged/falling), sleep,
/// sad (overdue reminder), cryin ("You Cryin?" mode), and any others (e.g. music, think) used as random idle moments.
/// A profile's own mode (sprite.json `"modes"`): its own rows for standing, walking and
/// random moves, plus how it behaves.
struct SpriteMode {
    enum Behaviour: String { case normal, still, hyper }
    var name: String
    var behaviour: Behaviour = .normal
    var anims: [String: [CGImage]] = [:]
}

struct SpriteSet {
    var anims: [String: [CGImage]] = [:]
    /// Modes from sprite.json (empty for most sprites). The first one is the default.
    var modes: [SpriteMode] = []
    /// How big the pet is drawn compared with normal (sprite.json `"size": 1.5`).
    var size: CGFloat = 1
    /// Animations before any mode was applied.
    private var base: [String: [CGImage]] = [:]
    static let standardNames = ["idle", "walk", "walkLeft", "wave", "jump", "sleep", "sad", "cryin"]
    var idle: [CGImage] { anims["idle"] ?? [] }
    var walk: [CGImage] { anims["walk"] ?? idle }
    var isEmpty: Bool { idle.isEmpty }
    var frameCount: Int { Set(anims.values.flatMap { $0.map { ObjectIdentifier($0) } }).count }

    /// Extra animations played now and then while standing around.
    var idleExtras: [String] {
        anims.keys.filter { !Self.standardNames.contains($0) }.sorted()
    }

    init() {}
    init(rows: [[CGImage]], mapping: [String: Any]? = nil) {
        let rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return }
        anims["idle"] = rows[0]
        if rows.count > 1, rows[1].count >= 2 { anims["walk"] = rows[1] }
        if let s = mapping?["size"] as? Double, s > 0 { size = CGFloat(min(s, 3)) }
        for (name, value) in mapping ?? [:] where !["modes", "layout", "size"].contains(name) {
            if let frames = Self.select(value, from: rows) { anims[name] = frames }
        }
        base = anims
        // "modes": [{ "name": "Party", "behaviour": "still", "idle": 8, "walk": 9, "extras": [8, 9] }, …]
        for m in mapping?["modes"] as? [[String: Any]] ?? [] {
            guard let name = m["name"] as? String else { continue }
            var mode = SpriteMode(name: name, behaviour: (m["behaviour"] as? String).flatMap(SpriteMode.Behaviour.init) ?? .normal)
            for (key, value) in m where Self.standardNames.contains(key) {
                if let frames = Self.select(value, from: rows) { mode.anims[key] = frames }
            }
            for (i, value) in (m["extras"] as? [Any] ?? []).enumerated() {
                if let frames = Self.select(value, from: rows) { mode.anims["extra\(i + 1)"] = frames }
            }
            modes.append(mode)
        }
    }

    /// This sprite as it looks in a mode: the mode's rows replace the defaults, and its extras
    /// replace the random idle moves.
    func applying(_ mode: SpriteMode) -> SpriteSet {
        var out = self
        out.anims = base.filter { Self.standardNames.contains($0.key) }.merging(mode.anims) { $1 }
        return out
    }

    /// 3 → row 3; "6:1-2" → frames 1–2 of row 6 (all 1-based); [1, "2:1-3"] → those one after another.
    private static func select(_ value: Any, from rows: [[CGImage]]) -> [CGImage]? {
        if let list = value as? [Any] {
            let all = list.compactMap { select($0, from: rows) }.flatMap { $0 }
            return all.isEmpty ? nil : all
        }
        var row: Int?, range: ClosedRange<Int>?
        if let n = value as? Int { row = n }
        else if let s = value as? String {
            let parts = s.split(separator: ":")
            row = Int(parts[0].trimmingCharacters(in: .whitespaces))
            if parts.count > 1 {
                let ends = parts[1].split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if let a = ends.first { range = a...(ends.last ?? a) }
            }
        }
        guard let r = row, rows.indices.contains(r - 1) else { return nil }
        let frames = rows[r - 1]
        guard let range else { return frames }
        let picked = range.compactMap { frames.indices.contains($0 - 1) ? frames[$0 - 1] : nil }
        return picked.isEmpty ? nil : picked
    }
}

enum SpriteStore {
    /// The active profile's sprite files.
    static var file: URL { Profiles.active.spriteFile }
    static var mappingFile: URL { Profiles.active.mappingFile }

    static func load() -> SpriteSet {
        guard let img = NSImage(contentsOf: file) else { return SpriteSet() }
        let map = mapping(at: mappingFile)
        return SpriteSet(rows: frameRows(from: img, layout: map?["layout"] as? String), mapping: map)
    }

    private static func mapping(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Copies the chosen image into place (as PNG), plus a same-named .json row mapping if there is one.
    /// Returns its animations, empty if unreadable.
    static func install(from url: URL) -> SpriteSet {
        guard let img = NSImage(contentsOf: url) else { return SpriteSet() }
        let sidecar = url.deletingPathExtension().appendingPathExtension("json")
        let map = mapping(at: sidecar)
        let set = SpriteSet(rows: frameRows(from: img, layout: map?["layout"] as? String), mapping: map)
        guard !set.isEmpty, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return SpriteSet() }
        let profile = Profiles.writable(Profiles.active)             // built-ins get a personal copy first
        try? png.write(to: profile.spriteFile, options: .atomic)
        try? FileManager.default.removeItem(at: profile.mappingFile)
        if map != nil { try? FileManager.default.copyItem(at: sidecar, to: profile.mappingFile) }
        return set
    }

    /// Back to the built-in drawn look for the active profile.
    static func remove() {
        let profile = Profiles.active
        guard !profile.builtIn else { return }
        try? FileManager.default.removeItem(at: profile.spriteFile)
        try? FileManager.default.removeItem(at: profile.mappingFile)
    }

    // MARK: - Slicing

    /// All frames in reading order (handy for tests).
    static func frames(from image: NSImage) -> [CGImage] { frameRows(from: image).flatMap { $0 } }

    /// Frames grouped by sheet row, top row first. A single image gives one row with one frame.
    /// `layout: "rows"` (in sprite.json) is for sheets whose frames aren't on a grid: each strip of
    /// figures separated by empty space is a row, and each figure in it a frame.
    static func frameRows(from image: NSImage, layout: String? = nil) -> [[CGImage]] {
        guard let px = Pixels(image) else { return [] }
        px.keyOutBackground()
        guard let all = px.makeImage() else { return [] }
        if layout == "rows" { return bandRows(px, all) }

        if let grid = px.detectGrid() {
            // Cut every cell; keep the ones holding a full-height figure.
            var cells: [(rect: CGRect, box: CGRect)] = []
            let bounds = CGRect(x: 0, y: 0, width: px.w, height: px.h)
            // Start one cell before the offset so edge frames aren't lost; clip cells to the image.
            var y = grid.oy > 0 ? grid.oy - grid.ch : 0
            while y < px.h {
                var x = grid.ox > 0 ? grid.ox - grid.cw : 0
                while x < px.w {
                    let r = CGRect(x: x, y: y, width: grid.cw, height: grid.ch)
                    let clipped = r.intersection(bounds)
                    if !clipped.isEmpty, let box = px.opaqueBox(in: clipped) { cells.append((r, box)) }
                    x += grid.cw
                }
                y += grid.ch
            }
            let tallest = cells.map(\.box.height).max() ?? 0
            let full = cells.filter { $0.box.height >= tallest * 0.75 }
            if full.count >= 2 {
                // One crop box (relative to the cell) shared by all frames, so they don't jitter.
                var u = CGRect.null
                for c in full { u = u.union(c.box.offsetBy(dx: -c.rect.minX, dy: -c.rect.minY)) }
                let rowStarts = Array(Set(full.map { Int($0.rect.minY) })).sorted()
                return rowStarts.map { y in
                    full.filter { Int($0.rect.minY) == y }
                        .compactMap { all.cropping(to: u.offsetBy(dx: $0.rect.minX, dy: $0.rect.minY)) }
                }
            }
        }
        // Single image: crop to the visible pixels.
        guard let box = px.opaqueBox(in: CGRect(x: 0, y: 0, width: px.w, height: px.h)) else { return [] }
        return all.cropping(to: box).map { [[$0]] } ?? []
    }
}

extension SpriteStore {
    /// Slices a free-form sheet: horizontal bands of figures → rows, gaps between figures → frames.
    /// Every frame is padded onto the same canvas (bottom of its band at the bottom, centred), so
    /// nothing jitters or changes size between frames.
    fileprivate static func bandRows(_ px: Pixels, _ all: CGImage) -> [[CGImage]] {
        // 1. bands: runs of rows that have pixels; tiny gaps (stray pixels) are bridged
        let rowHas = (0..<px.h).map { y in (0..<px.w).contains { px.opaque($0, y) } }
        var bands = runs(rowHas, bridge: 2)
        guard !bands.isEmpty else { return [] }
        let typical = bands.map(\.count).sorted()[(bands.count - 1) / 2]      // lower median
        bands = bands.filter { $0.count >= max(4, typical / 4) }          // lone specks
        // two rows that touch come out as one extra-tall band: cut it where it's thinnest
        let rowCount = (0..<px.h).map { y in (0..<px.w).reduce(0) { $0 + (px.opaque($1, y) ? 1 : 0) } }
        var split: [Range<Int>] = []
        var todo = bands
        while let band = todo.first {
            todo.removeFirst()
            guard band.count > typical * 3 / 2 else { split.append(band); continue }
            let inner = (band.lowerBound + typical / 2)..<(band.upperBound - typical / 2)
            let cut = inner.min { rowCount[$0] < rowCount[$1] } ?? band.lowerBound + band.count / 2
            todo.insert(contentsOf: [band.lowerBound..<cut, cut..<band.upperBound], at: 0)
        }
        bands = split
        // 2. frames: runs of columns with pixels inside each band; drop small bits (props, sparkles)
        var rows: [[(x: Range<Int>, y: Range<Int>)]] = []
        for band in bands {
            let colHas = (0..<px.w).map { x in band.contains { px.opaque(x, $0) } }
            var pieces = runs(colHas, bridge: 1).map { x -> (x: Range<Int>, y: Range<Int>, n: Int) in
                var n = 0
                for y in band { for xx in x where px.opaque(xx, y) { n += 1 } }
                return (x, band, n)
            }
            let biggest = pieces.map(\.n).max() ?? 0
            pieces = pieces.filter { Double($0.n) >= Double(biggest) * 0.3 }
            if !pieces.isEmpty { rows.append(pieces.map { ($0.x, $0.y) }) }
        }
        // 3. one canvas for everything
        let cw = rows.flatMap { $0 }.map(\.x.count).max() ?? 0
        let ch = rows.flatMap { $0 }.map(\.y.count).max() ?? 0
        guard cw > 0, ch > 0 else { return [] }
        return rows.map { row in
            row.compactMap { f in
                guard let piece = all.cropping(to: CGRect(x: f.x.lowerBound, y: f.y.lowerBound, width: f.x.count, height: f.y.count)),
                      let c = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                c.interpolationQuality = .none
                c.draw(piece, in: CGRect(x: (cw - f.x.count) / 2, y: 0, width: f.x.count, height: f.y.count))
                return c.makeImage()
            }
        }
    }

    /// Ranges where `has` is true, joining ranges separated by at most `bridge` false values.
    private static func runs(_ has: [Bool], bridge: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        while i < has.count {
            guard has[i] else { i += 1; continue }
            var j = i
            while j < has.count && has[j] { j += 1 }
            if let last = out.last, i - last.upperBound <= bridge { out[out.count - 1] = last.lowerBound..<j } else { out.append(i..<j) }
            i = j
        }
        return out
    }
}

/// RGBA pixel buffer (row 0 = top of the image) with the helpers the slicer needs.
fileprivate final class Pixels {
    let w: Int, h: Int
    private let ctx: CGContext
    private let b: UnsafeMutablePointer<UInt8>

    init?(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        w = cg.width; h = cg.height
        guard w > 0, h > 0,
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = c.data else { return nil }
        ctx = c
        b = data.assumingMemoryBound(to: UInt8.self)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func opaque(_ x: Int, _ y: Int) -> Bool { b[(y * w + x) * 4 + 3] > 0 }

    func keyOutBackground() {
        let bg = (b[0], b[1], b[2], b[3])
        guard bg.3 == 255 else { return }       // already transparent
        func close(_ a: UInt8, _ c: UInt8) -> Bool { abs(Int(a) - Int(c)) <= 8 }
        for i in stride(from: 0, to: w * h * 4, by: 4)
        where close(b[i], bg.0) && close(b[i + 1], bg.1) && close(b[i + 2], bg.2) {
            b[i] = 0; b[i + 1] = 0; b[i + 2] = 0; b[i + 3] = 0
        }
    }

    func makeImage() -> CGImage? { ctx.makeImage() }

    func opaqueBox(in r: CGRect) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) where opaque(x, y) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Finds a repeating frame grid; nil if the image doesn't look like a sheet.
    func detectGrid() -> (cw: Int, ch: Int, ox: Int, oy: Int)? {
        let colP = (0..<w).map { x in Double((0..<h).reduce(0) { $0 + (opaque(x, $1) ? 1 : 0) }) }
        let rowP = (0..<h).map { y in Double((0..<w).reduce(0) { $0 + (opaque($1, y) ? 1 : 0) }) }
        guard let cw = Self.period(colP), let ch = Self.period(rowP) else { return nil }
        let (ox, cutX) = Self.bestOffset(colP, period: cw)
        let (oy, cutY) = Self.bestOffset(rowP, period: ch)
        // Real gutters are nearly empty compared with the frames themselves.
        let avgX = colP.reduce(0, +) / Double(w), avgY = rowP.reduce(0, +) / Double(h)
        guard cutX < avgX * 0.35, cutY < avgY * 0.35, w / cw * (h / ch) >= 2 else { return nil }
        return (cw, ch, ox, oy)
    }

    /// Smallest lag whose autocorrelation is a strong local peak (avoids picking 2× the cell size).
    private static func period(_ p: [Double]) -> Int? {
        let minLag = 12, maxLag = p.count / 2
        guard maxLag > minLag + 1 else { return nil }
        let mean = p.reduce(0, +) / Double(p.count)
        let q = p.map { $0 - mean }
        var v = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...(maxLag + 1) where lag < q.count {
            var s = 0.0
            for i in 0..<(q.count - lag) { s += q[i] * q[i + lag] }
            v[lag] = s / Double(q.count - lag)
        }
        let best = v[minLag...maxLag].max() ?? 0
        guard best > 0 else { return nil }
        for lag in (minLag + 1)...maxLag where v[lag] >= v[lag - 1] && v[lag] >= v[lag + 1] && v[lag] >= 0.6 * best {
            return lag
        }
        return nil
    }

    /// Grid offset whose cut lines cross the fewest pixels; returns (offset, average pixels per cut).
    private static func bestOffset(_ p: [Double], period: Int) -> (Int, Double) {
        var best = (0, Double.infinity)
        for o in 0..<period {
            let cuts = stride(from: o, to: p.count, by: period).map { p[$0] }
            let avg = cuts.reduce(0, +) / Double(max(cuts.count, 1))
            if avg < best.1 { best = (o, avg) }
        }
        return best
    }
}
