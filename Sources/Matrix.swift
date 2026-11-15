import Cocoa

// MARK: - Storage (always remembered)

/// The four lists, saved as plain JSON so it's easy to sync elsewhere later.
/// Location: ~/Library/Application Support/MochiPet/matrix.json
struct MatrixData: Codable {
    var urgentImportant = ">> MSc Industry by Thursday"
    var urgentNotImportant = ""
    var notUrgentImportant = ""
    var notUrgentNotImportant = ""
    /// Due date for each item, worked out when the item was first written.
    var dueDates: [String: Date] = [:]
    var updatedAt = Date()

    init() {}

    // Tolerant decoding so files from older versions (or hand edits) never wipe the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MatrixData()
        urgentImportant = try c.decodeIfPresent(String.self, forKey: .urgentImportant) ?? d.urgentImportant
        urgentNotImportant = try c.decodeIfPresent(String.self, forKey: .urgentNotImportant) ?? ""
        notUrgentImportant = try c.decodeIfPresent(String.self, forKey: .notUrgentImportant) ?? ""
        notUrgentNotImportant = try c.decodeIfPresent(String.self, forKey: .notUrgentNotImportant) ?? ""
        dueDates = try c.decodeIfPresent([String: Date].self, forKey: .dueDates) ?? [:]
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    var boxes: [String] { [urgentImportant, urgentNotImportant, notUrgentImportant, notUrgentNotImportant] }

    /// Give new items a due date (resolved against *now*), forget items that were deleted.
    mutating func refreshDueDates(now: Date = Date()) {
        var seen = Set<String>()
        for box in boxes {
            for line in box.split(separator: "\n") {
                let t = itemText(line)
                guard !t.isEmpty else { continue }
                seen.insert(t)
                if dueDates[t] == nil, let d = DueParser.dueDate(in: t, now: now) { dueDates[t] = d }
            }
        }
        dueDates = dueDates.filter { seen.contains($0.key) }
    }

    var dueItems: [DueItem] {
        boxes.enumerated().flatMap { q, box in
            box.split(separator: "\n").compactMap { line -> DueItem? in
                let t = itemText(line)
                guard let d = dueDates[t] else { return nil }
                return DueItem(text: t, due: d, quadrant: q)
            }
        }
    }
}

enum MatrixStore {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MochiPet")
    }
    static var file: URL { dir.appendingPathComponent("matrix.json") }
    /// Optional picture shown behind the four boxes.
    static var backgroundFile: URL { dir.appendingPathComponent("list-background.png") }

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
        layer?.masksToBounds = true
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

    /// Slightly see-through so a list background shows behind the boxes.
    func setTranslucent(_ on: Bool) {
        layer?.backgroundColor = color.withAlphaComponent(on ? 0.86 : 1).cgColor
        layer?.cornerRadius = on ? 10 : 3
    }

    var text: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    private let dueLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.alignment = .right
        return l
    }()

    /// Colour items by how soon they're due and show the next due date in the header.
    func highlight(dueDates: [String: Date]) {
        if dueLabel.superview == nil { addSubview(dueLabel) }
        guard let lm = textView.layoutManager else { return }
        let s = textView.string as NSString
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: s.length))
        var soonest: Date?
        s.enumerateSubstrings(in: NSRange(location: 0, length: s.length), options: .byLines) { line, range, _, _ in
            guard let line, let due = dueDates[itemText(Substring(line))] else { return }
            if soonest == nil || due < soonest! { soonest = due }
            let days = DueParser.daysUntil(due)
            let color: NSColor? = days < 0 ? NSColor(hex: 0xC62828) : days == 0 ? NSColor(hex: 0xD84315)
                : days <= 2 ? NSColor(hex: 0x9A5B00) : nil
            if let color { lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range) }
        }
        if let soonest {
            let days = DueParser.daysUntil(soonest)
            dueLabel.stringValue = "⏰ next: \(DueParser.describe(soonest))"
            dueLabel.textColor = days < 0 ? NSColor(hex: 0xC62828) : days <= 1 ? NSColor(hex: 0xD84315) : NSColor(hex: 0x444444)
        } else {
            dueLabel.stringValue = ""
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: pad, y: bounds.height - pad - titleLabel.frame.height)
        dueLabel.sizeToFit()
        dueLabel.frame.origin = CGPoint(x: bounds.width - pad - dueLabel.frame.width, y: titleLabel.frame.minY + 1)
        dueLabel.isHidden = dueLabel.frame.minX < titleLabel.frame.maxX + 6
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
    private let grid: MatrixGridView
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
        grid = MatrixGridView(quads: quads)
        super.init()
        panel.title = "Rick's List 🧪"
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

        panel.contentView = grid
        applyBackground(NSImage(contentsOf: MatrixStore.backgroundFile))

        for (q, t) in zip(quads, data.boxes) {
            q.text = t
            q.onChange = { [weak self] in self?.save() }
        }
        data.refreshDueDates()
        MatrixStore.save(data)
        refreshHighlights()
    }

    /// Copies the picture into place and shows it; nil removes the background.
    @discardableResult
    func setBackground(from url: URL?) -> Bool {
        guard let url else {
            try? FileManager.default.removeItem(at: MatrixStore.backgroundFile)
            applyBackground(nil)
            return true
        }
        guard let img = NSImage(contentsOf: url), let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: MatrixStore.dir, withIntermediateDirectories: true)
        try? png.write(to: MatrixStore.backgroundFile, options: .atomic)
        applyBackground(img)
        return true
    }

    private func applyBackground(_ img: NSImage?) {
        grid.background = img
        quads.forEach { $0.setTranslucent(img != nil) }
    }

    private func save() {
        data.urgentImportant = quads[0].text
        data.urgentNotImportant = quads[1].text
        data.notUrgentImportant = quads[2].text
        data.notUrgentNotImportant = quads[3].text
        data.refreshDueDates()
        data.updatedAt = Date()
        MatrixStore.save(data)
        refreshHighlights()
    }

    private func refreshHighlights() {
        quads.forEach { $0.highlight(dueDates: data.dueDates) }
    }

    /// Items in the "Urgent & Important" box.
    var urgentItems: [String] {
        quads[0].text.split(separator: "\n").map(itemText).filter { !$0.isEmpty }
    }

    /// Something worth reminding about: overdue or due within 3 days, most pressing first
    /// (ties go to the more important box). Rotates through them on each call.
    private var reminderCursor = 0
    func nextReminder() -> (text: String, overdue: Bool)? {
        let soon = data.dueItems
            .filter { $0.daysLeft <= 3 }
            .sorted { ($0.daysLeft, $0.quadrant) < ($1.daysLeft, $1.quadrant) }
        guard !soon.isEmpty else { return nil }
        defer { reminderCursor += 1 }
        // Mostly the most urgent one; every few times, one of the others.
        let item = reminderCursor % 3 == 0 ? soon[0] : soon[reminderCursor % soon.count]
        return (item.reminder, item.daysLeft < 0)
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
        refreshHighlights()   // "tomorrow" becomes "today" overnight
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
    var background: NSImage? { didSet { needsLayout = true; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0x1C2333).setFill()
        bounds.fill()
        guard let img = background, img.size.width > 0, img.size.height > 0 else { return }
        // aspect-fill: cover the whole window, cropping the overflow
        let s = max(bounds.width / img.size.width, bounds.height / img.size.height)
        let size = NSSize(width: img.size.width * s, height: img.size.height * s)
        img.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                            width: size.width, height: size.height))
    }
    init(quads: [QuadrantView]) {
        self.quads = quads
        super.init(frame: .zero)
        quads.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let gap: CGFloat = background == nil ? 4 : 14, top: CGFloat = 28   // wider gutters let the picture show
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
