import Foundation

// MARK: - One task

/// A task with a stable identity, so it can be linked to a calendar event or an email later.
/// You still just type `>>` lines; each line is matched to its task behind the scenes.
struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String              // the line without its ">>" bullet
    var box: Int                   // 0 = U&I, 1 = U&NI, 2 = NU&I, 3 = NU&NI
    var due: Date?
    var done = false
    var doneAt: Date?
    var createdAt = Date()
    var source = "typed"           // typed / calendar / mail
    var externalID: String?        // calendar event or email this came from
    var time: Int?                 // minutes after midnight if a time was written ("at 3pm")
    var syncedDue: Date?           // due date/time when last synced with the calendar event,
    var syncedTime: Int?           //   used to tell which side changed
    var doneByWord: Bool?          // marked done because the text says DONE (removing the word re-opens it)

    /// "Pay fees DONE", "done: email Akila", "Read papers – done ✓" → true.
    /// "get it done by Friday" → false (lower-case "done" only counts as the first or last word).
    static func saysDone(_ title: String) -> Bool {
        let patterns = ["\\bDONE\\b",                                         // capitals anywhere
                        "(?i)^[\\s✅✔️✓-]*done\\b",                              // first word
                        "(?i)\\bdone[\\s!.:✅✔️✓)-]*$"]                         // last word
        return patterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    init(title: String, box: Int, due: Date?, createdAt: Date = Date()) {
        self.title = title; self.box = box; self.due = due; self.createdAt = createdAt
        self.time = DueParser.time(in: title)
    }
}

// MARK: - The whole list

/// Saved to ~/Library/Application Support/MochiPet/matrix.json.
/// The four box texts are kept exactly as typed (that's what you see and edit);
/// `tasks` holds what each line *is* (id, due date, done…), in box-then-line order.
struct MatrixData: Codable {
    static let currentVersion = 2

    var version = MatrixData.currentVersion
    var urgentImportant = ">> MSc Industry by Thursday"
    var urgentNotImportant = ""
    var notUrgentImportant = ""
    var notUrgentNotImportant = ""
    var tasks: [TaskItem] = []
    var updatedAt = Date()

    /// Set when this was read from an older file; the store keeps a backup before overwriting.
    var migratedFrom: Int?

    enum CodingKeys: String, CodingKey {
        case version, urgentImportant, urgentNotImportant, notUrgentImportant, notUrgentNotImportant, tasks, updatedAt
        case dueDates, completed                               // version 1 only (read, never written)
    }

    init() { sync() }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MatrixData()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        urgentImportant = try c.decodeIfPresent(String.self, forKey: .urgentImportant) ?? d.urgentImportant
        urgentNotImportant = try c.decodeIfPresent(String.self, forKey: .urgentNotImportant) ?? ""
        notUrgentImportant = try c.decodeIfPresent(String.self, forKey: .notUrgentImportant) ?? ""
        notUrgentNotImportant = try c.decodeIfPresent(String.self, forKey: .notUrgentNotImportant) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []

        if version < 2 {
            // v1: due dates and done flags were looked up by the item's text
            let dueDates = try c.decodeIfPresent([String: Date].self, forKey: .dueDates) ?? [:]
            let completed = try c.decodeIfPresent(Set<String>.self, forKey: .completed) ?? []
            tasks = []
            for (q, box) in boxes.enumerated() {
                for title in Self.titles(in: box) {
                    var t = TaskItem(title: title, box: q, due: dueDates[title], createdAt: updatedAt)
                    if completed.contains(title) { t.done = true; t.doneAt = updatedAt }
                    tasks.append(t)
                }
            }
            migratedFrom = version
            version = Self.currentVersion
        }
        sync(now: Date())
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(urgentImportant, forKey: .urgentImportant)
        try c.encode(urgentNotImportant, forKey: .urgentNotImportant)
        try c.encode(notUrgentImportant, forKey: .notUrgentImportant)
        try c.encode(notUrgentNotImportant, forKey: .notUrgentNotImportant)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    var boxes: [String] {
        get { [urgentImportant, urgentNotImportant, notUrgentImportant, notUrgentNotImportant] }
        set {
            urgentImportant = newValue[0]; urgentNotImportant = newValue[1]
            notUrgentImportant = newValue[2]; notUrgentNotImportant = newValue[3]
        }
    }

    /// Item titles of a box, in order (blank lines skipped).
    static func titles(in box: String) -> [String] {
        box.split(separator: "\n", omittingEmptySubsequences: false).map(itemText).filter { !$0.isEmpty }
    }

    /// Tasks of one box, in line order.
    func tasks(inBox q: Int) -> [TaskItem] { tasks.filter { $0.box == q } }

    // MARK: matching lines to tasks

    /// Re-matches the typed lines to tasks, keeping each task's identity through edits:
    /// 1. same text in the same box, 2. same text moved from another box,
    /// 3. an edited line in the same spot (similar text). Anything left is a new task.
    /// New tasks (and edits that change the date words) get their due date resolved against `now`.
    mutating func sync(now: Date = Date()) {
        let pool = tasks
        var used = Set<UUID>()
        var assigned: [[TaskItem?]] = boxes.map { Self.titles(in: $0).map { _ in nil } }
        let titles = boxes.map(Self.titles)

        // 1 + 2: exact text, same box first, then any box
        for sameBox in [true, false] {
            for q in 0..<4 {
                for (i, title) in titles[q].enumerated() where assigned[q][i] == nil {
                    if let k = pool.firstIndex(where: { !used.contains($0.id) && $0.title == title && (!sameBox || $0.box == q) }) {
                        assigned[q][i] = pool[k]; used.insert(pool[k].id)
                    }
                }
            }
        }
        // 3: edited in place: leftover old tasks of the box ↔ leftover lines, in order, if similar
        for q in 0..<4 {
            var leftovers = pool.filter { $0.box == q && !used.contains($0.id) }
            for (i, title) in titles[q].enumerated() where assigned[q][i] == nil {
                if let k = leftovers.firstIndex(where: { Self.similar($0.title, title) }) {
                    assigned[q][i] = leftovers[k]; used.insert(leftovers[k].id)
                    leftovers.remove(at: k)
                }
            }
        }

        var result: [TaskItem] = []
        for q in 0..<4 {
            for (i, title) in titles[q].enumerated() {
                if var t = assigned[q][i] {
                    if t.title != title {
                        if DueParser.datePhrase(t.title) != DueParser.datePhrase(title) {
                            t.due = DueParser.dueDate(in: title, now: now)     // the "when" changed
                        }
                        t.title = title
                        t.time = DueParser.time(in: title)
                    }
                    t.box = q
                    result.append(Self.applyDoneWord(t, now: now))
                } else {
                    let t = TaskItem(title: title, box: q, due: DueParser.dueDate(in: title, now: now), createdAt: now)
                    result.append(Self.applyDoneWord(t, now: now))
                }
            }
        }
        tasks = result
    }

    /// Writing DONE marks a task done; deleting the word re-opens it (only if the word did it).
    static func applyDoneWord(_ task: TaskItem, now: Date) -> TaskItem {
        var t = task
        if TaskItem.saysDone(t.title) {
            if !t.done { t.done = true; t.doneAt = now }
            t.doneByWord = true
        } else if t.doneByWord == true {
            t.done = false; t.doneAt = nil; t.doneByWord = nil
        }
        return t
    }

    /// Same task, just edited? Shares a start or an end of 3+ characters.
    static func similar(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        let n = min(3, a.count, b.count)
        guard n > 0 else { return false }
        return a.hasPrefix(String(b.prefix(n))) || a.hasSuffix(String(b.suffix(n)))
    }

    // MARK: what the rest of the app asks

    /// Due dates of open (not done) tasks, by title (for colouring lines).
    var dueDates: [String: Date] {
        var out: [String: Date] = [:]
        for t in tasks where !t.done { if let d = t.due { out[t.title] = d } }
        return out
    }

    /// Titles of done tasks (for strikethrough).
    var completed: Set<String> { Set(tasks.filter(\.done).map(\.title)) }

    var dueItems: [DueItem] {
        tasks.compactMap { t in
            guard let d = t.due, !t.done else { return nil }
            return DueItem(text: t.title, due: d, quadrant: t.box)
        }
    }

    /// Marks the given lines (by index among a box's items) done or not done.
    /// If they're all done already, un-does them; otherwise marks them all done.
    mutating func toggleDone(box q: Int, itemIndexes: [Int], now: Date = Date()) {
        let ids = tasks(inBox: q).enumerated().filter { itemIndexes.contains($0.offset) }.map(\.element.id)
        guard !ids.isEmpty else { return }
        let allDone = tasks.filter { ids.contains($0.id) }.allSatisfy(\.done)
        for i in tasks.indices where ids.contains(tasks[i].id) {
            tasks[i].done = !allDone
            tasks[i].doneAt = allDone ? nil : now
        }
    }

    /// Marks one task done / not done (e.g. ticked in the calendar view).
    mutating func setDone(_ id: UUID, _ done: Bool, now: Date = Date()) {
        guard let k = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[k].done = done
        tasks[k].doneAt = done ? now : nil
    }

    /// Removes done tasks from the boxes; returns them (for the done log).
    mutating func cleanUpDone() -> [TaskItem] {
        let doneTasks = tasks.filter(\.done)
        guard !doneTasks.isEmpty else { return [] }
        var newBoxes = boxes
        for q in 0..<4 {
            var doneIdx = Set(tasks(inBox: q).enumerated().filter { $0.element.done }.map(\.offset))
            var item = -1
            newBoxes[q] = boxes[q].components(separatedBy: "\n").filter { line in
                guard !itemText(Substring(line)).isEmpty else { return true }
                item += 1
                if doneIdx.contains(item) { doneIdx.remove(item); return false }
                return true
            }.joined(separator: "\n")
        }
        boxes = newBoxes
        tasks.removeAll(where: \.done)
        return doneTasks
    }

    /// Rewrites the line of one task (keeps its id), e.g. to retarget its date words.
    mutating func rewriteLine(of id: UUID, _ transform: (String) -> String) {
        guard let k = tasks.firstIndex(where: { $0.id == id }) else { return }
        let q = tasks[k].box
        let index = tasks(inBox: q).firstIndex { $0.id == id }!
        var item = -1
        var newBoxes = boxes
        newBoxes[q] = boxes[q].components(separatedBy: "\n").map { line in
            guard !itemText(Substring(line)).isEmpty else { return line }
            item += 1
            guard item == index else { return line }
            let newLine = transform(line)
            tasks[k].title = itemText(Substring(newLine))
            return newLine
        }.joined(separator: "\n")
        boxes = newBoxes
    }

    /// The task on a given item line of a box.
    func task(box q: Int, itemIndex: Int) -> TaskItem? {
        let list = tasks(inBox: q)
        return list.indices.contains(itemIndex) ? list[itemIndex] : nil
    }

    /// Rewrites "tomorrow"/"today"/"yesterday" (and passed weekdays) in the text so they stay true.
    /// The task keeps its id and due date. Returns true if any text changed.
    mutating func rollRelativeWords(now: Date = Date()) -> Bool {
        var changed = false
        var newBoxes = boxes
        for q in 0..<4 {
            let boxTasks = tasks(inBox: q)
            var item = -1
            newBoxes[q] = boxes[q].components(separatedBy: "\n").map { line in
                guard !itemText(Substring(line)).isEmpty else { return line }
                item += 1
                guard item < boxTasks.count, let due = boxTasks[item].due else { return line }
                let newLine = DueParser.rollRelativeWords(in: line, due: due, now: now)
                if newLine != line {
                    changed = true
                    if let k = tasks.firstIndex(where: { $0.id == boxTasks[item].id }) { tasks[k].title = itemText(Substring(newLine)) }
                }
                return newLine
            }.joined(separator: "\n")
        }
        if changed { boxes = newBoxes }
        return changed
    }
}

/// Tasks you've cleared away, so nothing done is ever truly lost.
/// Saved to ~/Library/Application Support/MochiPet/done-log.json.
enum DoneLog {
    static var file: URL { MatrixStore.dir.appendingPathComponent("done-log.json") }

    static func append(_ items: [TaskItem]) {
        guard !items.isEmpty else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        var all = (try? Data(contentsOf: file)).flatMap { try? dec.decode([TaskItem].self, from: $0) } ?? []
        all.append(contentsOf: items)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: MatrixStore.dir, withIntermediateDirectories: true)
        if let data = try? enc.encode(all) { try? data.write(to: file, options: .atomic) }
    }
}
