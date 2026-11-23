import Cocoa

// MARK: - Storage (always remembered)

enum MatrixStore {
    static var dir: URL {
        if let custom = ProcessInfo.processInfo.environment["RICK_DATA_DIR"] { return URL(fileURLWithPath: custom) }   // tests
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MochiPet")
    }
    static var file: URL { dir.appendingPathComponent("matrix.json") }
    /// Optional picture shown behind the four boxes.
    static var backgroundFile: URL { dir.appendingPathComponent("list-background.png") }

    /// Loads the list. Never loses data: an older format is backed up before it's upgraded,
    /// and a file that can't be read is set aside (matrix.unreadable-<date>.json) rather than overwritten.
    static func load() -> MatrixData {
        guard let data = try? Data(contentsOf: file) else { return MatrixData() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do {
            let m = try dec.decode(MatrixData.self, from: data)
            if let old = m.migratedFrom {
                let backup = dir.appendingPathComponent("matrix.v\(old).backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
            }
            return m
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? data.write(to: dir.appendingPathComponent("matrix.unreadable-\(stamp).json"))
            NSLog("Rick: couldn't read matrix.json (\(error)); kept a copy and started fresh")
            return MatrixData()
        }
    }

    static func save(_ m: MatrixData) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(m) { try? data.write(to: file, options: .atomic) }
    }
}

// MARK: - One coloured quadrant

/// The text area of a box; ⌘⇧X (Edit ▸ Mark Done) toggles strikethrough on the selected items.
final class ListTextView: NSTextView {
    var onToggleDone: ((NSRange) -> Void)?
    var onAddToCalendar: ((NSRange) -> Void)?
    @objc func toggleDone(_ sender: Any?) { onToggleDone?(selectedRange()) }
    /// ⌘⇧E (Edit ▸ Add to Calendar): put the selected task in your calendar.
    @objc func addToCalendar(_ sender: Any?) { onAddToCalendar?(selectedRange()) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event) ?? NSMenu()
        m.insertItem(.separator(), at: 0)
        m.insertItem(withTitle: "Add to Calendar", action: #selector(addToCalendar(_:)), keyEquivalent: "", at: 0)
        m.insertItem(withTitle: "Mark Done / Not Done", action: #selector(toggleDone(_:)), keyEquivalent: "", at: 0)
        return m
    }
}

final class QuadrantView: NSView, NSTextViewDelegate {
    let textView = ListTextView()
    private let titleLabel: NSTextField
    private let scroll = NSScrollView()
    /// Capsule behind the title, so each box reads as a labelled card.
    private let pill = NSView()
    /// Text colour on this card (set by the theme).
    private var ink: NSColor = .black
    var onChange: (() -> Void)?

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false                  // let the shadow / glow show; the scroll view clips the text
        layer?.cornerRadius = 18

        pill.wantsLayer = true
        addSubview(pill)
        titleLabel.font = .systemFont(ofSize: 13, weight: .heavy)
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

    /// Dresses the box as a card in the theme's colours (a bit see-through on a picture).
    func apply(card: ListTheme.Card, index: Int, picture: Bool) {
        ink = card.text
        let fill = card.fills[index % card.fills.count]
        layer?.backgroundColor = (picture ? fill.withAlphaComponent(min(fill.alphaComponent, 0.85)) : fill).cgColor
        layer?.borderColor = card.border.cgColor
        layer?.borderWidth = card.borderWidth
        layer?.cornerRadius = 18
        let shadow = card.glow ?? NSColor(white: 0, alpha: 0.28)
        layer?.shadowColor = shadow.cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = card.glow == nil ? 10 : 14
        layer?.shadowOffset = card.glow == nil ? CGSize(width: 0, height: -3) : .zero
        pill.layer?.backgroundColor = ink.withAlphaComponent(0.1).cgColor
        pill.layer?.borderColor = ink.withAlphaComponent(0.18).cgColor
        pill.layer?.borderWidth = 1
        titleLabel.textColor = ink
        textView.textColor = ink
        textView.insertionPointColor = ink
        textView.typingAttributes = [.font: textView.font!, .foregroundColor: ink]
        needsLayout = true
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
    func highlight(dueDates: [String: Date], completed: Set<String> = []) {
        if dueLabel.superview == nil { addSubview(dueLabel) }
        guard let lm = textView.layoutManager else { return }
        let s = textView.string as NSString
        let all = NSRange(location: 0, length: s.length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        lm.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: all)
        var soonest: Date?
        s.enumerateSubstrings(in: all, options: .byLines) { line, range, _, _ in
            guard let line else { return }
            let item = itemText(Substring(line))
            if completed.contains(item) {                       // done: grey + struck through
                lm.addTemporaryAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .foregroundColor: self.ink.withAlphaComponent(0.4)], forCharacterRange: range)
                return
            }
            guard let due = dueDates[item] else { return }
            if soonest == nil || due < soonest! { soonest = due }
            let days = DueParser.daysUntil(due)
            let color: NSColor? = days < 0 ? NSColor(hex: 0xC62828) : days == 0 ? NSColor(hex: 0xD84315)
                : days <= 2 ? NSColor(hex: 0x9A5B00) : nil
            if let color { lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range) }
        }
        if let soonest {
            let days = DueParser.daysUntil(soonest)
            dueLabel.stringValue = "⏰ next: \(DueParser.describe(soonest))"
            dueLabel.textColor = days < 0 ? NSColor(hex: 0xC62828) : days <= 1 ? NSColor(hex: 0xD84315) : ink.withAlphaComponent(0.7)
        } else {
            dueLabel.stringValue = ""
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: pad + 10, y: bounds.height - pad - 3 - titleLabel.frame.height)
        pill.frame = titleLabel.frame.insetBy(dx: -10, dy: -3)
        pill.layer?.cornerRadius = pill.frame.height / 2
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 18, cornerHeight: 18, transform: nil)
        dueLabel.sizeToFit()
        dueLabel.frame.origin = CGPoint(x: bounds.width - pad - dueLabel.frame.width, y: titleLabel.frame.minY + 1)
        dueLabel.isHidden = dueLabel.frame.minX < pill.frame.maxX + 6
        scroll.frame = NSRect(x: pad + 2, y: pad, width: bounds.width - pad * 2 - 2,
                              height: pill.frame.minY - pad - 6)
        textView.frame.size.width = scroll.contentSize.width
    }

    // Clicking anywhere in the box starts typing in it.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
        if textView.string.isEmpty { textView.string = ">> " }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    func textDidChange(_ notification: Notification) { onChange?() }

    /// Called when the cursor moves in this box (remembers which box you're working in).
    var onFocus: (() -> Void)?
    func textViewDidChangeSelection(_ notification: Notification) { onFocus?() }

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
            QuadrantView(title: "Urgent & Important"),
            QuadrantView(title: "Urgent & Not Important"),
            QuadrantView(title: "Not Urgent & Important"),
            QuadrantView(title: "Not Urgent & Not Important"),
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
        panel.titleVisibility = .hidden            // the Tasks | Calendar switch sits where the title was
        grid.pane.tasks = { [weak self] in self?.data.tasks ?? [] }
        grid.pane.onToggleDone = { [weak self] id in
            guard let self else { return }
            self.save()
            let done = !(self.data.tasks.first { $0.id == id }?.done ?? false)
            self.data.setDone(id, done)
            MatrixStore.save(self.data)
            self.refreshHighlights()
        }
        applyBackground(NSImage(contentsOf: MatrixStore.backgroundFile))

        _ = data.rollRelativeWords()
        for (q, t) in zip(quads, data.boxes) {
            q.text = t
            q.onChange = { [weak self] in self?.save() }
            q.textView.onToggleDone = { [weak self, weak q] range in
                guard let self, let q else { return }
                self.toggleDone(in: q, range: range)
            }
            q.textView.onAddToCalendar = { [weak self, weak q] range in
                guard let self, let q else { return }
                self.lastBox = self.quads.firstIndex { $0 === q } ?? self.lastBox
                if let t = self.task(in: q, range: range) { self.onAddToCalendar?(t) } else { self.onAddToCalendar?(nil) }
            }
            q.onFocus = { [weak self, weak q] in
                guard let self, let q, let i = self.quads.firstIndex(where: { $0 === q }) else { return }
                self.lastBox = i
            }
        }
        // keep "tomorrow"/"today" true: at midnight and when the Mac wakes up
        NotificationCenter.default.addObserver(self, selector: #selector(dayMayHaveChanged), name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(dayMayHaveChanged), name: NSWorkspace.didWakeNotification, object: nil)
        data.sync()
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
        grid.theme = ListTheme.current
        grid.pane.theme = grid.theme
        for (i, q) in quads.enumerated() { q.apply(card: grid.theme.card, index: i, picture: img != nil) }
        refreshHighlights()                                // done / due colours follow the card's text colour
        if let last = lastToday { setToday(last) }      // re-colour the Today strip
    }

    /// Switches the list's theme (for the active profile) or re-applies it after a profile switch.
    func applyTheme(_ theme: ListTheme? = nil) {
        if let theme { ListTheme.chosen = theme }
        applyBackground(grid.background)
    }

    var hasPicture: Bool { grid.background != nil }
    private var lastToday: [DayEvent]?

    private func save() {
        data.urgentImportant = quads[0].text
        data.urgentNotImportant = quads[1].text
        data.notUrgentImportant = quads[2].text
        data.notUrgentNotImportant = quads[3].text
        data.sync()
        data.updatedAt = Date()
        MatrixStore.save(data)
        refreshHighlights()
    }

    private func refreshHighlights() {
        quads.forEach { $0.highlight(dueDates: data.dueDates, completed: data.completed) }
    }

    /// Events for the calendar view (filled in by the app; empty until a calendar is connected).
    var events: (Date, Date) -> [DayEvent] {
        get { grid.pane.events }
        set { grid.pane.events = newValue }
    }
    var calendarConnected: () -> Bool {
        get { grid.pane.calendarConnected }
        set { grid.pane.calendarConnected = newValue }
    }

    /// Tasks or Calendar side (⌘1 / ⌘2).
    func showMode(_ mode: MatrixGridView.Mode) {
        grid.mode = mode
        if !isOpen { panel.makeKeyAndOrderFront(nil) }
    }

    @objc private func dayMayHaveChanged() {
        DispatchQueue.main.async { self.rollWords() }
    }

    /// Rewrites date words that went stale and puts the new text in the boxes.
    private func rollWords() {
        save()                                           // pick up anything being typed first
        guard data.rollRelativeWords() else { refreshHighlights(); return }
        for (q, t) in zip(quads, data.boxes) where q.text != t { q.text = t }
        MatrixStore.save(data)
        refreshHighlights()
    }

    /// Index (among the box's items) of every item line a selection touches.
    private func itemIndexes(in q: QuadrantView, range: NSRange) -> [Int] {
        let s = q.text as NSString
        guard s.length > 0 else { return [] }
        let sel = s.lineRange(for: NSRange(location: min(range.location, s.length - 1), length: range.length))
        var indexes: [Int] = [], item = -1, pos = 0
        for line in q.text.components(separatedBy: "\n") {
            let len = (line as NSString).length
            if !itemText(Substring(line)).isEmpty {
                item += 1
                if NSIntersectionRange(NSRange(location: pos, length: max(len, 1)), sel).length > 0 { indexes.append(item) }
            }
            pos += len + 1
        }
        return indexes
    }

    /// The (first) task under a selection.
    private func task(in q: QuadrantView, range: NSRange) -> TaskItem? {
        save()
        guard let box = quads.firstIndex(where: { $0 === q }), let i = itemIndexes(in: q, range: range).first else { return nil }
        return data.task(box: box, itemIndex: i)
    }

    // MARK: calendar

    /// Asked to add a task to the calendar (nil = the cursor isn't on a task).
    var onAddToCalendar: ((TaskItem?) -> Void)?
    /// Box you last worked in (for the menu's "Add Selected Task to Calendar").
    private var lastBox = 0

    /// The task where the cursor is in the box you last worked in.
    func selectedTask() -> TaskItem? {
        let q = quads[lastBox]
        return task(in: q, range: q.textView.selectedRange())
    }

    func task(withID id: UUID) -> TaskItem? { data.tasks.first { $0.id == id } }

    /// Remembers that a task now has a calendar event.
    func link(_ id: UUID, toEvent eventID: String) {
        guard let k = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[k].externalID = eventID
        data.tasks[k].syncedDue = data.tasks[k].due
        data.tasks[k].syncedTime = data.tasks[k].time
        MatrixStore.save(data)
    }

    /// Keeps linked tasks and events in step (see CalendarLink for the rules).
    func reconcile(with cal: CalendarSync) {
        guard cal.isConnected else { return }
        save()
        var textChanged = false
        for t in data.tasks where t.externalID != nil {
            switch CalendarLink.reconcile(t, event: cal.eventInfo(t.externalID!)) {
            case .none: break
            case .unlink:
                if let k = data.tasks.firstIndex(where: { $0.id == t.id }) {
                    data.tasks[k].externalID = nil; data.tasks[k].syncedDue = nil; data.tasks[k].syncedTime = nil
                }
            case .pushToEvent:
                cal.updateEvent(t.externalID!, from: t)
                link(t.id, toEvent: t.externalID!)
            case .pullFromEvent(let due, let time):
                data.rewriteLine(of: t.id) { DueParser.retarget($0, due: due, time: time) }
                if let k = data.tasks.firstIndex(where: { $0.id == t.id }) {
                    data.tasks[k].due = due; data.tasks[k].time = time
                    data.tasks[k].syncedDue = due; data.tasks[k].syncedTime = time
                }
                textChanged = true
            }
        }
        if textChanged { for (q, t) in zip(quads, data.boxes) where q.text != t { q.text = t } }
        MatrixStore.save(data)
        refreshHighlights()
    }

    /// Fills the Today strip (empty list hides it).
    func setToday(_ events: [DayEvent]) {
        lastToday = events
        let ink = grid.background != nil ? NSColor.white : grid.theme.ink
        let label = grid.todayLabel
        grid.showsToday = !events.isEmpty
        if grid.mode == .calendar { grid.pane.reload() }
        guard !events.isEmpty else { label.attributedStringValue = NSAttributedString(); grid.needsLayout = true; return }
        let out = NSMutableAttributedString(string: "📅 Today  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: ink])
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let now = Date()
        for (i, e) in events.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "   ·   ", attributes: [.foregroundColor: ink.withAlphaComponent(0.5)])) }
            let past = !e.allDay && e.end < now
            out.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: e.color ?? .systemBlue, .font: NSFont.systemFont(ofSize: 11)]))
            let when = e.allDay ? "" : f.string(from: e.start) + " "
            out.append(NSAttributedString(string: when + e.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(past ? 0.45 : 0.95)]))
        }
        label.attributedStringValue = out
        label.toolTip = events.map { ($0.allDay ? "All day" : f.string(from: $0.start)) + "  " + $0.title }.joined(separator: "\n")
        grid.needsLayout = true
    }

    /// ⌘⇧X: strike through (or un-strike) every item touched by the selection.
    private func toggleDone(in q: QuadrantView, range: NSRange) {
        save()
        guard let box = quads.firstIndex(where: { $0 === q }) else { return }
        let indexes = itemIndexes(in: q, range: range)
        data.toggleDone(box: box, itemIndexes: indexes)
        data.updatedAt = Date()
        MatrixStore.save(data)
        refreshHighlights()
    }

    /// Clears struck-through tasks out of the boxes (they're kept in done-log.json).
    @discardableResult
    func cleanUpDone() -> Int {
        save()
        let removed = data.cleanUpDone()
        guard !removed.isEmpty else { return 0 }
        DoneLog.append(removed)
        for (q, t) in zip(quads, data.boxes) where q.text != t { q.text = t }
        data.updatedAt = Date()
        MatrixStore.save(data)
        refreshHighlights()
        return removed.count
    }

    /// Items in the "Urgent & Important" box.
    var urgentItems: [String] {
        quads[0].text.split(separator: "\n").map(itemText).filter { !$0.isEmpty }
    }

    static let boxNames = ["Urgent & Important", "Urgent & Not Important", "Not Urgent & Important", "Not Urgent & Not Important"]
    static let boxEmoji = ["🟨", "🟩", "🟥", "🟦"]

    /// Every item, box by box (U&I, U&NI, NU&I, NU&NI); inside a box, dated items by due date
    /// (overdue first), then undated ones in the order you wrote them. One speech bubble each.
    func rundown() -> [String] {
        var out: [String] = []
        for (q, box) in data.boxes.enumerated() {
            let items = box.split(separator: "\n").map(itemText).filter { !$0.isEmpty && !data.completed.contains($0) }
            let dated = items.compactMap { t in data.dueDates[t].map { (t, $0) } }.sorted { $0.1 < $1.1 }
            let undated = items.filter { data.dueDates[$0] == nil }
            for (i, (text, due)) in dated.enumerated() {
                out.append(line(q, first: i == 0, "\(DueParser.stripDateWords(text)) · \(Self.dueWords(due))"))
            }
            for (i, text) in undated.enumerated() {
                out.append(line(q, first: dated.isEmpty && i == 0, text))
            }
        }
        return out
    }

    private func line(_ q: Int, first: Bool, _ body: String) -> String {
        "\(Self.boxEmoji[q]) \(Self.boxNames[q])\n\(body)"
    }

    /// "due today", "due tomorrow", "due Thursday", "1 day late", "3 days late".
    static func dueWords(_ due: Date) -> String {
        let d = DueParser.daysUntil(due)
        switch d {
        case ..<(-1): return "\(-d) days late ⚠️"
        case -1: return "was due yesterday ⚠️"
        case 0: return "due TODAY"
        default: return "due \(DueParser.describe(due))"
        }
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
        rollWords()           // "tomorrow" becomes "today" overnight
        grid.applyMode()      // opens on whichever side you used last
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        onVisibility?(true)
    }

    func windowWillClose(_ notification: Notification) { save(); onVisibility?(false) }
    func flush() { save() }
}

/// Lays the four boxes out in a 2×2 grid with a thin dark gutter, like the original.
final class MatrixGridView: NSView {
    enum Mode: Int { case tasks = 0, calendar = 1 }

    private let quads: [QuadrantView]
    let pane = CalendarPane(frame: .zero)
    /// Tasks | Calendar, in the title bar.
    let modeSwitch = NSSegmentedControl(labels: ["☑︎ Tasks", "📅 Calendar"], trackingMode: .selectOne, target: nil, action: nil)
    /// Schedule | Month (calendar mode only).
    let viewSwitch = NSSegmentedControl(labels: ["Schedule", "Month"], trackingMode: .selectOne, target: nil, action: nil)

    /// Which side is showing; remembered, so the window opens where you left it.
    var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: "list.mode")) ?? .tasks }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "list.mode"); applyMode() }
    }

    func applyMode() {
        modeSwitch.selectedSegment = mode.rawValue
        viewSwitch.selectedSegment = pane.view == .month ? 1 : 0
        let cal = mode == .calendar
        quads.forEach { $0.isHidden = cal }
        pane.isHidden = !cal
        viewSwitch.isHidden = !cal
        if cal { pane.theme = theme; pane.reload() }
        needsLayout = true
    }
    var background: NSImage? { didSet { needsLayout = true; needsDisplay = true } }
    var theme: ListTheme = .plain { didSet { styleControls(); needsLayout = true; needsDisplay = true } }

    /// Switches and buttons drawn on the background: dark style on Space/Plain/pictures, light on Garden.
    func styleControls() {
        let light = background == nil && theme.isLight
        let look = NSAppearance(named: light ? .aqua : .darkAqua)
        [modeSwitch, viewSwitch, pane].forEach { $0.appearance = look }
    }

    /// "📅 Today: …" line above the boxes (hidden when there's nothing to show).
    let todayLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.lineBreakMode = .byTruncatingTail
        l.maximumNumberOfLines = 1
        l.isHidden = true
        return l
    }()

    /// Whether the Today strip has something to show (set by the controller).
    var showsToday = false

    @objc private func modeChanged() { mode = Mode(rawValue: modeSwitch.selectedSegment) ?? .tasks }
    @objc private func viewChanged() { pane.view = viewSwitch.selectedSegment == 1 ? .month : .schedule }

    override func draw(_ dirtyRect: NSRect) {
        guard let img = background, img.size.width > 0, img.size.height > 0 else {
            theme.draw(in: bounds)
            return
        }
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
        addSubview(todayLabel)
        addSubview(pane)
        for s in [modeSwitch, viewSwitch] {
            s.segmentStyle = .capsule
            s.controlSize = .small
            s.target = self
            addSubview(s)
        }
        modeSwitch.action = #selector(modeChanged)
        viewSwitch.action = #selector(viewChanged)
        applyMode()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // switches sit in the title bar
        modeSwitch.sizeToFit(); viewSwitch.sizeToFit()
        modeSwitch.frame.origin = CGPoint(x: (bounds.width - modeSwitch.frame.width) / 2, y: bounds.height - 25)
        viewSwitch.frame.origin = CGPoint(x: bounds.width - viewSwitch.frame.width - 12, y: bounds.height - 25)
        if mode == .calendar {
            todayLabel.isHidden = true
            pane.frame = NSRect(x: 14, y: 10, width: bounds.width - 28, height: bounds.height - 28 - 18)
            return
        }
        let strip: CGFloat = todayLabel.attributedStringValue.length == 0 || !showsToday ? 0 : 26
        todayLabel.isHidden = strip == 0
        let gap: CGFloat = 16, top: CGFloat = 30 + strip    // cards floating on the background, not a grid
        todayLabel.frame = NSRect(x: 12, y: bounds.height - 28 - strip + 4, width: bounds.width - 24, height: 20)
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
