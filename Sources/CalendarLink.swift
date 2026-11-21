import Foundation

/// How a task and its linked calendar event are kept in step (no EventKit here, so it's testable).
///
/// Each linked task remembers the date/time it had when it was last synced. Comparing both sides
/// with that tells us who changed:
/// - task changed since the last sync → update the event
/// - event moved in Calendar → update the task
/// - event deleted, or the task lost its date → unlink (nothing is deleted on either side)
enum CalendarLink {
    enum Action: Equatable {
        case none
        case pushToEvent
        case pullFromEvent(due: Date, time: Int?)
        case unlink
    }

    struct EventInfo: Equatable {
        var start: Date
        var allDay: Bool
    }

    static func reconcile(_ task: TaskItem, event: EventInfo?, calendar cal: Calendar = .current) -> Action {
        guard task.externalID != nil else { return .none }
        guard let event, task.due != nil else { return .unlink }
        let eventDue = cal.startOfDay(for: event.start)
        let eventTime: Int? = event.allDay ? nil : {
            let c = cal.dateComponents([.hour, .minute], from: event.start)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }()
        if task.due != task.syncedDue || task.time != task.syncedTime { return .pushToEvent }
        if eventDue != task.syncedDue || eventTime != task.syncedTime { return .pullFromEvent(due: eventDue, time: eventTime) }
        return .none
    }

    /// Start date for an event made from a task: the due day, at its time if it has one.
    static func start(for task: TaskItem, calendar cal: Calendar = .current) -> Date? {
        guard let due = task.due else { return nil }
        guard let t = task.time else { return due }
        return cal.date(byAdding: .minute, value: t, to: cal.startOfDay(for: due))
    }
}
