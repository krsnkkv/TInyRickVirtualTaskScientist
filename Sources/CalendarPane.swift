import Cocoa

/// The "Calendar" side of the list window: your tasks with due dates next to your events.
/// Two views: **Schedule** (scrolling, day by day) and **Month** (grid + the picked day's list).
final class CalendarPane: NSView {
    enum View: String { case schedule, month }

    // what to show (filled in by the list window)
    var events: (Date, Date) -> [DayEvent] = { _, _ in [] }
    var tasks: () -> [TaskItem] = { [] }
    var calendarConnected: () -> Bool = { false }
    var onToggleDone: (UUID) -> Void = { _ in }
    var theme: ListTheme = .space { didSet { reload() } }

    var view: View {
        get { View(rawValue: UserDefaults.standard.string(forKey: "calendar.view") ?? "") ?? .schedule }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "calendar.view"); needsLayout = true; reload() }
    }

    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let stack = NSStackView()
    private let month = MonthGridView()
    private let cal = Calendar.current

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = doc
        addSubview(scroll)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        doc.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        month.onSelect = { [weak self] day in self?.selectedDay = day; self?.reload() }
        month.onMonthChange = { [weak self] in self?.reload() }
        addSubview(month)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Day picked in Month view.
    var selectedDay = Calendar.current.startOfDay(for: Date())

    override func layout() {
        super.layout()
        if view == .month {
            month.isHidden = false
            let h = min(max(bounds.height * 0.56, 230), 340)
            month.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
            scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - h - 8)
        } else {
            month.isHidden = true
            scroll.frame = bounds
        }
    }

    // MARK: building the list

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let today = cal.startOfDay(for: Date())
        let allTasks = tasks()

        if view == .month {
            month.theme = theme
            fillMonth(allTasks)
            let day = selectedDay
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let dayEvents = events(day, next)
            let dayTasks = allTasks.filter { $0.due.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            addCard(title: dayTitle(day), events: dayEvents, tasks: dayTasks,
                    empty: "Nothing on this day.")
        } else {
            let overdue = allTasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }.sorted { $0.due! < $1.due! }
            if !overdue.isEmpty { addCard(title: "⚠️ Overdue", events: [], tasks: overdue, showDate: true) }

            let end = cal.date(byAdding: .day, value: 30, to: today)!
            let evs = events(today, end)
            var shownAny = !overdue.isEmpty
            var day = today
            while day < end {
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let dayEvents = evs.filter { $0.start < next && ($0.end > day || cal.isDate($0.start, inSameDayAs: day)) }
                let dayTasks = allTasks.filter { $0.due.map { cal.isDate($0, inSameDayAs: day) } ?? false }
                if !dayEvents.isEmpty || !dayTasks.isEmpty || day == today {
                    addCard(title: dayTitle(day), events: dayEvents, tasks: dayTasks, empty: "Nothing planned. Nice.")
                    shownAny = true
                }
                day = next
            }
            if !shownAny { addNote("Nothing with a date yet. Write things like “by Friday” in your list.") }
        }
        if !calendarConnected() { addNote("Connect your calendar (🧪 ▸ Calendar) to see events here too.") }
        needsLayout = true
    }

    private func fillMonth(_ allTasks: [TaskItem]) {
        let start = month.gridStart, end = cal.date(byAdding: .day, value: 42, to: start)!
        var dots: [Date: [NSColor]] = [:]
        for e in events(start, end) {
            dots[cal.startOfDay(for: e.start), default: []].append(e.color ?? .systemBlue)
        }
        for t in allTasks where !t.done {
            if let d = t.due { dots[cal.startOfDay(for: d), default: []].append(Self.boxColor[t.box]) }
        }
        month.dots = dots
        month.selected = selectedDay
        month.needsDisplay = true
    }

    private func dayTitle(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
        if cal.isDateInToday(day) { return "Today · " + f.string(from: day) }
        if cal.isDateInTomorrow(day) { return "Tomorrow · " + f.string(from: day) }
        return f.string(from: day)
    }

    // MARK: cards and rows

    static let boxColor = [NSColor(hex: 0xD9A800), NSColor(hex: 0x3FA34D), NSColor(hex: 0xE0566B), NSColor(hex: 0x4F74D9)]
    static let boxShort = ["U&I", "U&NI", "NU&I", "NU&NI"]

    private var cardFill: NSColor { theme == .garden ? NSColor(white: 1, alpha: 0.72) : NSColor(white: 1, alpha: 0.9) }

    private func addCard(title: String, events: [DayEvent], tasks: [TaskItem], empty: String = "", showDate: Bool = false) {
        let card = NSView()
        card.appearance = NSAppearance(named: .aqua)          // cards are light, whatever the background
        card.wantsLayer = true
        card.layer?.backgroundColor = cardFill.cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        inner.addArrangedSubview(label(title, size: 13, weight: .bold, color: NSColor(white: 0.1, alpha: 1)))
        let timeF = DateFormatter(); timeF.timeStyle = .short; timeF.dateStyle = .none
        for e in events {
            let time = e.allDay ? "All day" : timeF.string(from: e.start)
            let past = !e.allDay && e.end < Date()
            inner.addArrangedSubview(row(lead: label(time, size: 12, weight: .medium, color: .secondaryLabelColor, width: 64),
                                         dot: e.color ?? .systemBlue,
                                         text: label(e.title, size: 13, weight: .regular, color: NSColor(white: 0.1, alpha: past ? 0.45 : 1))))
        }
        for t in tasks.sorted(by: { ($0.done ? 1 : 0, $0.time ?? -1, $0.box) < ($1.done ? 1 : 0, $1.time ?? -1, $1.box) }) {
            inner.addArrangedSubview(taskRow(t, showDate: showDate))
        }
        if events.isEmpty && tasks.isEmpty && !empty.isEmpty {
            inner.addArrangedSubview(label(empty, size: 12, weight: .regular, color: .secondaryLabelColor))
        }
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func taskRow(_ t: TaskItem, showDate: Bool) -> NSView {
        let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
        box.state = t.done ? .on : .off
        box.identifier = NSUserInterfaceItemIdentifier(t.id.uuidString)
        box.toolTip = t.done ? "Mark not done" : "Mark done"

        var lead = t.time.map { DueParser.timeLabel($0) } ?? "Task"
        if showDate, let due = t.due { lead = DueParser.describe(due) }
        let title = NSMutableAttributedString(string: t.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 0.1, alpha: t.done ? 0.4 : 1)])
        if t.done { title.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: title.length)) }
        let text = NSTextField(labelWithAttributedString: title)
        text.lineBreakMode = .byTruncatingTail

        let pill = label(" \(Self.boxShort[t.box]) ", size: 10, weight: .bold, color: .white)
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Self.boxColor[t.box].cgColor
        pill.layer?.cornerRadius = 4

        let leadLabel = label(lead, size: 12, weight: .medium, color: .secondaryLabelColor, width: 64)
        let h = NSStackView(views: [leadLabel, box, text, pill])
        h.orientation = .horizontal
        h.spacing = 6
        h.alignment = .centerY
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return h
    }

    private func row(lead: NSView, dot color: NSColor, text: NSTextField) -> NSView {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 9, height: 9))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 4.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 9), dot.heightAnchor.constraint(equalToConstant: 9)])
        text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let h = NSStackView(views: [lead, dot, text])
        h.orientation = .horizontal
        h.spacing = 8
        h.alignment = .centerY
        return h
    }

    private func addNote(_ s: String) {
        stack.addArrangedSubview(label(s, size: 12, weight: .medium, color: theme.ink.withAlphaComponent(0.8)))
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat? = nil) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        if let width {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return l
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        onToggleDone(id)
        reload()
    }
}

/// Scroll content that starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Month grid

/// A month of days with coloured dots (events in their calendar colour, tasks in their box colour).
final class MonthGridView: NSView {
    var dots: [Date: [NSColor]] = [:]
    var selected = Calendar.current.startOfDay(for: Date())
    var theme: ListTheme = .space
    var onSelect: (Date) -> Void = { _ in }
    var onMonthChange: () -> Void = {}

    private let cal = Calendar.current
    private(set) var monthStart: Date
    private let prev = NSButton(title: "‹", target: nil, action: nil)
    private let next = NSButton(title: "›", target: nil, action: nil)
    private let todayButton = NSButton(title: "Today", target: nil, action: nil)

    override init(frame: NSRect) {
        let c = Calendar.current
        monthStart = c.date(from: c.dateComponents([.year, .month], from: Date()))!
        super.init(frame: frame)
        for (b, sel) in [(prev, #selector(goPrev)), (next, #selector(goNext)), (todayButton, #selector(goToday))] {
            b.bezelStyle = .rounded
            b.target = self
            b.action = sel
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// First cell shown (the week containing the 1st).
    var gridStart: Date {
        let weekday = cal.component(.weekday, from: monthStart)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: monthStart)!
    }

    @objc private func goPrev() { monthStart = cal.date(byAdding: .month, value: -1, to: monthStart)!; onMonthChange() }
    @objc private func goNext() { monthStart = cal.date(byAdding: .month, value: 1, to: monthStart)!; onMonthChange() }
    @objc private func goToday() {
        monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        onSelect(cal.startOfDay(for: Date()))
    }

    private let header: CGFloat = 34, weekdayRow: CGFloat = 20

    override func layout() {
        super.layout()
        todayButton.frame = NSRect(x: bounds.width - 66, y: 4, width: 62, height: 24)
        next.frame = NSRect(x: bounds.width - 100, y: 4, width: 32, height: 24)
        prev.frame = NSRect(x: bounds.width - 134, y: 4, width: 32, height: 24)
    }

    private func cellRect(_ i: Int) -> NSRect {
        let w = bounds.width / 7, h = (bounds.height - header - weekdayRow) / 6
        return NSRect(x: CGFloat(i % 7) * w, y: header + weekdayRow + CGFloat(i / 7) * h, width: w, height: h).insetBy(dx: 2, dy: 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = theme.ink
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        (f.string(from: monthStart) as NSString).draw(at: CGPoint(x: 4, y: 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: ink])

        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let w = bounds.width / 7
        for i in 0..<7 {
            let s = symbols[(i + cal.firstWeekday - 1) % 7] as NSString
            let para = NSMutableParagraphStyle(); para.alignment = .center
            s.draw(in: NSRect(x: CGFloat(i) * w, y: header + 2, width: w, height: weekdayRow), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: para])
        }

        let start = gridStart
        let thisMonth = cal.component(.month, from: monthStart)
        for i in 0..<42 {
            let day = cal.date(byAdding: .day, value: i, to: start)!
            let r = cellRect(i)
            let inMonth = cal.component(.month, from: day) == thisMonth
            let isSelected = cal.isDate(day, inSameDayAs: selected)
            let fill: NSColor = isSelected ? NSColor(hex: 0x7B5CFF, alpha: 0.9)
                : NSColor(white: 1, alpha: inMonth ? (theme == .garden ? 0.7 : 0.88) : 0.35)
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            if cal.isDateInToday(day) && !isSelected {
                NSColor(hex: 0x7B5CFF).setStroke()
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7); ring.lineWidth = 2; ring.stroke()
            }
            let num = "\(cal.component(.day, from: day))" as NSString
            num.draw(at: CGPoint(x: r.minX + 6, y: r.minY + 4), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: cal.isDateInToday(day) ? .bold : .medium),
                .foregroundColor: isSelected ? NSColor.white : NSColor(white: 0.1, alpha: inMonth ? 1 : 0.4)])
            // up to 5 dots along the bottom
            let colors = Array((dots[cal.startOfDay(for: day)] ?? []).prefix(5))
            for (k, c) in colors.enumerated() {
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.minX + 6 + CGFloat(k) * 9, y: r.maxY - 11, width: 7, height: 7)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in 0..<42 where cellRect(i).contains(p) {
            onSelect(cal.date(byAdding: .day, value: i, to: gridStart)!)
            return
        }
    }
}
