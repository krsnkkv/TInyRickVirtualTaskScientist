import Cocoa

// MARK: - Storage (always remembered)

/// The four lists, saved as plain JSON so it's easy to sync elsewhere later.
/// Location: ~/Library/Application Support/MochiPet/matrix.json
struct MatrixData: Codable {
    var urgentImportant = ">> MSc Industry by Thursday"
    var urgentNotImportant = ""
    var notUrgentImportant = ""
    var notUrgentNotImportant = ""
    var updatedAt = Date()
}

enum MatrixStore {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MochiPet")
    }
    static var file: URL { dir.appendingPathComponent("matrix.json") }

    static func load() -> MatrixData {
        guard let data = try? Data(contentsOf: file) else { return MatrixData() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(MatrixData.self, from: data)) ?? MatrixData()
    }

    static func save(_ m: MatrixData) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(m) { try? data.write(to: file, options: .atomic) }
    }
}

// MARK: - One coloured quadrant

final class QuadrantView: NSView, NSTextViewDelegate {
    let textView = NSTextView()
    private let titleLabel: NSTextField
    private let scroll = NSScrollView()
    private let color: NSColor
    var onChange: (() -> Void)?

    init(title: String, color: NSColor) {
        self.color = color
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.borderColor = NSColor(hex: 0x1C2333).cgColor
        layer?.borderWidth = 2.5
        layer?.cornerRadius = 3

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .black
        addSubview(titleLabel)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        addSubview(scroll)

        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14, weight: .semibold)
        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.typingAttributes = [.font: textView.font!, .foregroundColor: NSColor.black]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scroll.documentView = textView
    }
    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: pad, y: bounds.height - pad - titleLabel.frame.height)
        scroll.frame = NSRect(x: pad, y: pad, width: bounds.width - pad * 2,
                              height: titleLabel.frame.minY - pad - 6)
        textView.frame.size.width = scroll.contentSize.width
    }

    // Clicking anywhere in the box starts typing in it.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
        if textView.string.isEmpty { textView.string = ">> " }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    func textDidChange(_ notification: Notification) { onChange?() }

    // Enter starts a new ">> " item; Enter on an empty item clears the bullet.
    func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let s = tv.string as NSString
        let lineRange = s.lineRange(for: NSRange(location: tv.selectedRange().location, length: 0))
        let line = s.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if line.trimmingCharacters(in: .whitespaces) == ">>" {
            tv.insertText("", replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
            return true
        }
        tv.insertText("\n>> ", replacementRange: tv.selectedRange())
        return true
    }

    func textView(_ tv: NSTextView, didChangeTypingAttributes notification: Notification?) {}
}

// MARK: - The window

final class MatrixController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private var data = MatrixStore.load()
    private let quads: [QuadrantView]
    var onVisibility: ((Bool) -> Void)?

    var isOpen: Bool { panel.isVisible }

    override init() {
        quads = [
            QuadrantView(title: "Urgent & Important", color: NSColor(hex: 0xFBF3A3)),
            QuadrantView(title: "Urgent & Not Important", color: NSColor(hex: 0xB5FCA7)),
            QuadrantView(title: "Not Urgent & Important", color: NSColor(hex: 0xFFC9C9)),
            QuadrantView(title: "Not Urgent & Not Important", color: NSColor(hex: 0xB9CBFC)),
        ]
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Mochi's List 🌱"
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .aqua)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 320)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameAutosaveName("MochiMatrix")
        panel.delegate = self

        let grid = MatrixGridView(quads: quads)
        grid.wantsLayer = true
        grid.layer?.backgroundColor = NSColor(hex: 0x1C2333).cgColor
        panel.contentView = grid

        let texts = [data.urgentImportant, data.urgentNotImportant, data.notUrgentImportant, data.notUrgentNotImportant]
        for (q, t) in zip(quads, texts) {
            q.text = t
            q.onChange = { [weak self] in self?.save() }
        }
    }

    private func save() {
        data.urgentImportant = quads[0].text
        data.urgentNotImportant = quads[1].text
        data.notUrgentImportant = quads[2].text
        data.notUrgentNotImportant = quads[3].text
        data.updatedAt = Date()
        MatrixStore.save(data)
    }

    /// Items in the "Urgent & Important" box, for Mochi to nag about.
    var urgentItems: [String] {
        quads[0].text.split(separator: "\n")
            .map { $0.replacingOccurrences(of: ">>", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func toggle(near petFrame: NSRect) {
        if isOpen { panel.orderOut(nil); onVisibility?(false) } else { show(near: petFrame) }
    }

    func show(near petFrame: NSRect) {
        if !panel.isVisible, UserDefaults.standard.string(forKey: "NSWindow Frame MochiMatrix") == nil {
            let vf = (NSScreen.screens.first { $0.frame.intersects(petFrame) } ?? NSScreen.main)?.visibleFrame ?? .zero
            let size = panel.frame.size
            let x = min(max(petFrame.midX - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
            let y = min(max(petFrame.minY + 150, vf.minY + 8), vf.maxY - size.height - 8)
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        onVisibility?(true)
    }

    func windowWillClose(_ notification: Notification) { save(); onVisibility?(false) }
    func flush() { save() }
}

/// Lays the four boxes out in a 2×2 grid with a thin dark gutter, like the original.
final class MatrixGridView: NSView {
    private let quads: [QuadrantView]
    init(quads: [QuadrantView]) {
        self.quads = quads
        super.init(frame: .zero)
        quads.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let gap: CGFloat = 4, top: CGFloat = 28   // leave room for the title bar
        let w = (bounds.width - gap * 3) / 2
        let h = (bounds.height - top - gap * 2) / 2
        let frames = [
            NSRect(x: gap, y: gap + h + gap, width: w, height: h),          // top-left
            NSRect(x: gap * 2 + w, y: gap + h + gap, width: w, height: h),  // top-right
            NSRect(x: gap, y: gap, width: w, height: h),                    // bottom-left
            NSRect(x: gap * 2 + w, y: gap, width: w, height: h),            // bottom-right
        ]
        for (q, f) in zip(quads, frames) { q.frame = f }
    }
}
