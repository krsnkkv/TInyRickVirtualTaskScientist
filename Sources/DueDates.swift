import Foundation

/// Finds a due date in a list item like "MSc Industry by Thursday".
///
/// - "today", "tonight" → today; "tomorrow", "tmrw" → tomorrow
/// - A weekday ("thursday", "this thu") → the coming one; today counts if it's that day
/// - "next thursday" → the one after the coming one
/// - Explicit dates ("20 Nov", "Nov 20", "20/11/2026") via NSDataDetector
///
/// Dates are resolved once, when an item is first written, and remembered, so
/// "Thursday" written on Sunday still means that Thursday when you look on Friday.
enum DueParser {
    private static let weekdays: [(names: [String], number: Int)] = [   // Calendar: 1 = Sunday
        (["sunday"], 1), (["monday", "mon"], 2), (["tuesday", "tues", "tue"], 3),
        (["wednesday", "weds", "wed"], 4), (["thursday", "thurs", "thur", "thu"], 5),
        (["friday", "fri"], 6), (["saturday"], 7),
    ]

    static func dueDate(in text: String, now: Date = Date(), calendar cal: Calendar = .current) -> Date? {
        let s = " " + text.lowercased() + " "
        let today = cal.startOfDay(for: now)
        func has(_ word: String) -> Bool {
            s.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
        }

        if has("today") || has("tonight") || has("eod") { return today }
        if has("tomorrow") || has("tmrw") || has("tmr") { return cal.date(byAdding: .day, value: 1, to: today) }

        for (names, number) in weekdays {
            for name in names where has(name) {
                let current = cal.component(.weekday, from: today)
                var ahead = (number - current + 7) % 7          // 0 = today
                if has("next \(name)") { ahead += 7 }
                return cal.date(byAdding: .day, value: ahead, to: today)
            }
        }

        // "by 18th", "the 2nd" → that day this month, or next month if it has passed
        if let m = s.range(of: "\\b([0-9]{1,2})(st|nd|rd|th)\\b", options: .regularExpression),
           !has("jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december"),
           let day = Int(s[m].filter(\.isNumber)), (1...31).contains(day) {
            var c = cal.dateComponents([.year, .month], from: today)
            c.day = day
            if let d = cal.date(from: c), cal.component(.day, from: d) == day, d >= today { return d }
            if let next = cal.date(byAdding: .month, value: 1, to: today) {
                var n = cal.dateComponents([.year, .month], from: next); n.day = day
                if let d = cal.date(from: n) { return d }
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let date = match.date {
            return cal.startOfDay(for: date)
        }
        return nil
    }

    /// Keeps relative date words true as days pass, using the date the item was resolved to:
    /// "Pay fees by tomorrow" → (next day) "by today" → "by yesterday" → "by Mon 16 Nov".
    /// A weekday word whose date has passed becomes "yesterday" / the date too.
    static func rollRelativeWords(in line: String, due: Date, now: Date = Date()) -> String {
        let d = daysUntil(due, now: now)
        let word: String = d == 1 ? "tomorrow" : d == 0 ? "today" : d == -1 ? "yesterday" : {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: due)
        }()
        func matchCase(_ original: String, _ replacement: String) -> String {
            if original.count > 1, original == original.uppercased() { return replacement.uppercased() }
            if original.first?.isUppercase == true { return replacement.prefix(1).uppercased() + replacement.dropFirst() }
            return replacement
        }
        func replaceFirst(_ pattern: String, in s: String, capitalize: Bool = true, when keep: (String) -> Bool) -> String {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range, in: s) else { return s }
            let found = String(s[r])
            if keep(found.lowercased()) { return s }
            let replacement = capitalize || found == found.uppercased() ? matchCase(found, word) : word
            return s.replacingCharacters(in: r, with: replacement)
        }
        let offsets = ["today": 0, "tonight": 0, "eod": 0, "tomorrow": 1, "tmrw": 1, "tmr": 1, "yesterday": -1]
        var out = replaceFirst("(?i)\\b(today|tonight|eod|tomorrow|tmrw|tmr|yesterday)\\b", in: line) { offsets[$0] == d }
        if d < 0 {
            let days = "monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sunday"
            // weekday names are always capitalised, so don't turn "by Thursday" into "by Yesterday";
            // skip ones already followed by a date ("Mon 16 Nov")
            out = replaceFirst("(?i)\\b((this|next)\\s+)?(\(days))\\b(?!\\s+[0-9])", in: out, capitalize: false) { _ in false }
        }
        return out
    }

    /// The item without its due-date words, so reminders don't repeat them:
    /// "Cross check MLS by tomorrow!" → "Cross check MLS", "Essay due next thu" → "Essay".
    static func stripDateWords(_ text: String) -> String {
        let months = "jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t|tember)?|oct(ober)?|nov(ember)?|dec(ember)?"
        let days = "monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sunday"
        let ordinal = "[0-9]{1,2}(st|nd|rd|th)?"
        let date = "[0-9]{1,2}/[0-9]{1,2}(/[0-9]{2,4})?"
            + "|today|tonight|eod|tomorrow|tmrw|tmr|yesterday|((this|next)\\s+)?(\(days))"
            + "|(the\\s+)?\(ordinal)(\\s+(of\\s+)?(\(months)))?"
            + "|(\(months))\\s+\(ordinal)"
        let pattern = "(?i)\\s*\\b((by|on|due|before|until|for|this)\\s+)*(\(date))\\b"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        dateWordsRegex = re
        let stripped = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        let cleaned = stripped.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "!?.,:;-–—")))
        return cleaned.isEmpty ? text : cleaned
    }

    private static var dateWordsRegex: NSRegularExpression?

    private static let timePattern = "(?i)\\s*\\b(?:at\\s+)?(?:(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)|([01]?\\d|2[0-3]):([0-5]\\d)|noon)\\b"

    /// Time of day written in an item, in minutes after midnight: "at 3pm" → 900, "9:30am" → 570,
    /// "15:45" → 945, "noon" → 720. nil if there's no time.
    static func time(in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: timePattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        if let h12 = group(1).flatMap(Int.init), let ampm = group(3)?.lowercased(), (1...12).contains(h12) {
            let minutes = group(2).flatMap(Int.init) ?? 0
            let hour = (h12 % 12) + (ampm == "pm" ? 12 : 0)
            return hour * 60 + minutes
        }
        if let h = group(4).flatMap(Int.init), let mm = group(5).flatMap(Int.init) { return h * 60 + mm }
        if text.lowercased().contains("noon") { return 720 }
        return nil
    }

    /// The item without date *or* time words (for calendar event titles).
    static func stripDateAndTimeWords(_ text: String) -> String {
        let noDate = stripDateWords(text)
        guard let re = try? NSRegularExpression(pattern: timePattern) else { return noDate }
        let s = re.stringByReplacingMatches(in: noDate, range: NSRange(noDate.startIndex..., in: noDate), withTemplate: "")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "!?.,:;-–—@")))
        return s.isEmpty ? noDate : s
    }

    /// Points an item's date (and time) words at a new date, e.g. after its calendar event was moved:
    /// "Essay by Thursday" → "Essay by Friday"; "Call at 3pm" → "Call at 4pm". Adds nothing if the
    /// item had no date words (the due date still changes behind the scenes).
    static func retarget(_ line: String, due: Date, time: Int?, now: Date = Date()) -> String {
        if dateWordsRegex == nil { _ = stripDateWords("") }
        var out = line
        let d = daysUntil(due, now: now)
        let f = DateFormatter()
        let word: String
        switch d {
        case 0: word = "today"
        case 1: word = "tomorrow"
        case 2...6: f.dateFormat = "EEEE"; word = f.string(from: due)
        default: f.dateFormat = "EEE d MMM"; word = f.string(from: due)
        }
        if let re = dateWordsRegex, let m = re.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
           let r = Range(m.range, in: out) {
            let matched = String(out[r])
            let prefix = matched.range(of: "^\\s*((by|on|due|before|until|for|this)\\s+)*", options: [.regularExpression, .caseInsensitive])
                .map { String(matched[$0]) } ?? " "
            out.replaceSubrange(r, with: prefix + word)
        }
        if let time, let re = try? NSRegularExpression(pattern: timePattern),
           let m = re.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)), let r = Range(m.range, in: out) {
            let h = time / 60, mm = time % 60
            let label = "\((h + 11) % 12 + 1)\(mm == 0 ? "" : String(format: ":%02d", mm))\(h < 12 ? "am" : "pm")"
            out.replaceSubrange(r, with: " at " + label)
        }
        return out
    }

    /// "3:00 PM" style label for minutes after midnight.
    static func timeLabel(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return Calendar.current.date(from: c).map(f.string) ?? ""
    }

    /// Just the date words of an item, normalised ("by tomorrow", "thursday"…), "" if none.
    /// Used to tell whether an edit changed *when* something is due.
    static func datePhrase(_ text: String) -> String {
        if dateWordsRegex == nil { _ = stripDateWords("") }
        guard let re = dateWordsRegex else { return "" }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { text[$0].lowercased().trimmingCharacters(in: .whitespaces) } }
            .joined(separator: " ")
    }

    /// Whole days from today until `date` (negative = overdue).
    static func daysUntil(_ date: Date, now: Date = Date(), calendar cal: Calendar = .current) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    /// "today", "tomorrow", "Thursday", "Thu 26 Nov", "2 days ago"…
    static func describe(_ date: Date, now: Date = Date()) -> String {
        let d = daysUntil(date, now: now)
        let f = DateFormatter()
        switch d {
        case ..<(-1): return "\(-d) days overdue"
        case -1: return "yesterday"
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: f.dateFormat = "EEEE"
        default: f.dateFormat = "EEE d MMM"
        }
        return f.string(from: date)
    }
}

/// A list item that has a due date.
struct DueItem {
    let text: String
    let due: Date
    let quadrant: Int        // 0 = Urgent & Important … 3 = Not Urgent & Not Important
    var daysLeft: Int { DueParser.daysUntil(due) }

    /// What Rick says about it.
    var reminder: String { Personality.reminder(for: self) }
}

/// Turns a raw line of a box into the item text (drops the ">>" bullet).
func itemText(_ line: Substring) -> String {
    var t = line.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix(">>") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    return t
}
