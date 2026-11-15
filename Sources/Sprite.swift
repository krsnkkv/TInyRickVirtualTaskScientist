import Cocoa

/// Custom pixel-art sprite for Mochi, kept at ~/Library/Application Support/MochiPet/sprite.png.
///
/// Any PNG/JPG works: if the image has a solid background (no transparency), the colour of the
/// top-left pixel is treated as background and made transparent. Empty margins are trimmed.
/// Draw the sprite facing **right**; Mochi flips it when walking left.
enum SpriteStore {
    static var file: URL { MatrixStore.dir.appendingPathComponent("sprite.png") }

    static func load() -> CGImage? {
        guard let img = NSImage(contentsOf: file) else { return nil }
        return prepare(img)
    }

    /// Copies the chosen image into place. Returns the prepared sprite, or nil if it can't be read.
    static func install(from url: URL) -> CGImage? {
        guard let img = NSImage(contentsOf: url), let sprite = prepare(img),
              let png = NSBitmapImageRep(cgImage: sprite).representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: MatrixStore.dir, withIntermediateDirectories: true)
        try? png.write(to: file, options: .atomic)
        return sprite
    }

    static func remove() { try? FileManager.default.removeItem(at: file) }

    /// Keys out a solid background and crops to the visible pixels.
    static func prepare(_ image: NSImage) -> CGImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Memory row 0 is the top of the image.
        let bg = (buf[0], buf[1], buf[2], buf[3])
        let keyOut = bg.3 == 255
        func close(_ a: UInt8, _ b: UInt8) -> Bool { abs(Int(a) - Int(b)) <= 6 }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if keyOut, close(buf[i], bg.0), close(buf[i + 1], bg.1), close(buf[i + 2], bg.2) {
                    buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
                }
                if buf[i + 3] > 0 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY, let full = ctx.makeImage() else { return nil }
        return full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
