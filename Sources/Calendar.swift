import Cocoa
import EventKit

/// An event as the list and the pet see it.
struct DayEvent: Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: NSColor?
}

/// Talks to the Calendar app (EventKit). Google calendars show up here too once your Google
/// account is added in System Settings ▸ Internet Accounts, so one connection covers both.
///
/// Nothing is ever deleted from your calendars: tasks can create events and move them,
/// and that's it.
final class CalendarSync {
    let store = EKEventStore()
    /// Called (on the main thread) when anything changes in your calendars.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.onChange?()
        }
    }

    // MARK: access

    var isConnected: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return s == .fullAccess }
        return s == .authorized
    }

    var wasDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    /// Shows macOS's permission prompt (first time only). Calls back on the main thread.
    func connect(_ done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: finish)
        } else {
            store.requestAccess(to: .event, completion: finish)
        }
    }

    /// Opens System Settings ▸ Privacy ▸ Calendars (to turn access back on after saying no).
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: settings

    var calendars: [EKCalendar] {
        guard isConnected else { return [] }
        return store.calendars(for: .event).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Calendars whose events show in the Today strip and get heads-ups (none chosen = all).
    var hiddenCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "calendar.hidden") ?? []) }
        set { defaults.set(Array(newValue), forKey: "calendar.hidden") }
    }

    /// Where "Add to Calendar" puts new events.
    var targetCalendar: EKCalendar? {
        get {
            if let id = defaults.string(forKey: "calendar.target"), let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
            return store.defaultCalendarForNewEvents
        }
        set { defaults.set(newValue?.calendarIdentifier, forKey: "calendar.target") }
    }

    var showToday: Bool {
        get { defaults.object(forKey: "calendar.showToday") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "calendar.showToday") }
    }

    var headsUp: Bool {
        get { defaults.object(forKey: "calendar.headsUp") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "calendar.headsUp") }
    }

    /// Minutes before a meeting that the pet speaks up.
    var headsUpMinutes = 10

    // MARK: reading

    func events(from start: Date, to end: Date) -> [DayEvent] {
        guard isConnected else { return [] }
        let shown = calendars.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !shown.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: shown)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { DayEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "(no title)",
                            start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, color: $0.calendar?.color) }
    }

    /// Today's events, all-day ones first.
    func today(now: Date = Date()) -> [DayEvent] {
        let start = Calendar.current.startOfDay(for: now)
        return events(from: start, to: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }

    func eventInfo(_ id: String) -> CalendarLink.EventInfo? {
        guard isConnected, let e = store.event(withIdentifier: id) else { return nil }
        return CalendarLink.EventInfo(start: e.startDate, allDay: e.isAllDay)
    }

    // MARK: writing (create + update only, never delete)

    /// Creates an event for a task; returns its identifier.
    func addEvent(for task: TaskItem) throws -> String {
        guard isConnected, let cal = targetCalendar else { throw CalendarError.notConnected }
        guard let start = CalendarLink.start(for: task) else { throw CalendarError.noDate }
        let e = EKEvent(eventStore: store)
        e.calendar = cal
        fill(e, from: task, start: start)
        e.notes = "Added from your list by your desktop pet."
        try store.save(e, span: .thisEvent, commit: true)
        guard let id = e.eventIdentifier else { throw CalendarError.notSaved }
        return id
    }

    /// Moves/renames the linked event to match the task.
    func updateEvent(_ id: String, from task: TaskItem) {
        guard isConnected, let e = store.event(withIdentifier: id), let start = CalendarLink.start(for: task) else { return }
        fill(e, from: task, start: start)
        try? store.save(e, span: .thisEvent, commit: true)
    }

    private func fill(_ e: EKEvent, from task: TaskItem, start: Date) {
        e.title = DueParser.stripDateAndTimeWords(task.title)
        e.isAllDay = task.time == nil
        e.startDate = start
        e.endDate = task.time == nil ? start : start.addingTimeInterval(3600)
    }

    enum CalendarError: LocalizedError {
        case notConnected, noDate, notSaved
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Calendar isn't connected."
            case .noDate: return "That task has no due date."
            case .notSaved: return "The event couldn't be saved."
            }
        }
    }
}
