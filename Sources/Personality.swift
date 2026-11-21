import Foundation

/// Moments when the pet says something. Raw values match the `## section` names in Personality.md.
enum Moment: String, CaseIterable {
    case greeting, hover, idle, overdue, today, tomorrow, soon
    case nothingDue = "nothing due", dragged, landed
    case listOpened = "list opened", listClosed = "list closed"
    case wokeUp = "woke up", newSprite = "new sprite", lonely, summoned
    case rundownStart = "rundown start", rundownEnd = "rundown end", rundownEmpty = "rundown empty"
    case cleaned, cleanNothing = "clean nothing"
    case meetingSoon = "meeting soon", meetingNow = "meeting now", addedToCalendar = "added to calendar"
    case calendarConnected = "calendar connected", calendarDenied = "calendar denied", needsDate = "needs a date"
}

/// What the pet says, loaded from Personality.md.
/// Looks in ~/Library/Application Support/MochiPet/Personality.md first (your own override),
/// then the copy bundled inside the app. Any missing section falls back to a built-in line.
enum Personality {
    static var lines: [Moment: [String]] = load()
    private static var lastLine: [Moment: String] = [:]


    static func reload() { lines = load() }

    /// A random line for the moment (never the same as last time), with {item}/{when} filled in.
    static func line(_ m: Moment, item: String = "", when: String = "") -> String {
        let pool = lines[m] ?? fallback[m] ?? ["…"]
        var choice = pool.randomElement()!
        if pool.count > 1 { while choice == lastLine[m] { choice = pool.randomElement()! } }
        lastLine[m] = choice
        return choice.replacingOccurrences(of: "{item}", with: item).replacingOccurrences(of: "{when}", with: when)
    }

    /// The reminder line for a due item, picked by how close it is.
    static func reminder(for item: DueItem) -> String {
        let d = item.daysLeft
        let moment: Moment = d < 0 ? .overdue : d == 0 ? .today : d == 1 ? .tomorrow : .soon
        return line(moment, item: DueParser.stripDateWords(item.text), when: when(item.due))
    }

    /// "today", "tomorrow", "Thursday", "yesterday", "3 days ago", "Thu 26 Nov".
    static func when(_ date: Date) -> String {
        let d = DueParser.daysUntil(date)
        switch d {
        case ..<(-1): return "\(-d) days ago"
        case -1: return "yesterday"
        default: return DueParser.describe(date)
        }
    }

    // MARK: - Loading

    static func parse(_ text: String) -> [Moment: [String]] {
        var out: [Moment: [String]] = [:]
        var current: Moment?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                current = Moment(rawValue: line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased())
            } else if let m = current, line.hasPrefix("- ") {
                let entry = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !entry.isEmpty { out[m, default: []].append(entry) }
            }
        }
        return out
    }

    private static func load() -> [Moment: [String]] {
        // the active profile's voice; the built-in Mochi as a safety net
        let candidates = [Profiles.active.personalityFile,
                          Profiles.bundleDir?.appendingPathComponent("mochi/Personality.md")].compactMap { $0 }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let parsed = parse(text)
                if !parsed.isEmpty { return parsed }
            }
        }
        return [:]
    }

    private static let fallback: [Moment: [String]] = [
        .greeting: ["Rick's here. Click me for your list."],
        .hover: ["Click me. The list's in there."],
        .idle: ["*burp* ...anyway."],
        .overdue: ["{item} was due {when}. Let's fix it."],
        .today: ["{item} is due today."],
        .tomorrow: ["{item} is due tomorrow."],
        .soon: ["{item} by {when}."],
        .nothingDue: ["Nothing due for days. Suspicious."],
        .dragged: ["Put me down!"],
        .landed: ["Ow."],
        .listOpened: ["Here's your list."],
        .listClosed: ["Now go do it."],
        .wokeUp: ["Huh? I'm up."],
        .newSprite: ["New body. Same genius."],
        .lonely: ["Don't forget your to-do list, please!"],
        .summoned: ["You rang?"],
        .rundownStart: ["Fine. Here's the damage."],
        .rundownEnd: ["That's everything. Go."],
        .rundownEmpty: ["Your list is empty. Suspicious."],
        .cleaned: ["Cleared {item} done tasks."],
        .cleanNothing: ["Nothing's done yet. Nothing to clean."],
        .meetingSoon: ["{item} {when}."],
        .meetingNow: ["{item} is starting now."],
        .addedToCalendar: ["Added {item} to your calendar for {when}."],
        .calendarConnected: ["Calendar connected."],
        .calendarDenied: ["No calendar access. You can turn it on in System Settings."],
        .needsDate: ["That one has no date. Give it a day first."],
    ]
}
