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
