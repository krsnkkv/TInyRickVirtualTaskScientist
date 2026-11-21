import Foundation

// Tiny test runner: ./test.sh
var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if ok { passes += 1 } else { failures += 1; print("✗ \(what)  (\(URL(fileURLWithPath: file).lastPathComponent):\(line))") }
}
let cal = Calendar.current
let sunday = cal.startOfDay(for: ISO8601DateFormatter().date(from: "2026-11-15T12:00:00Z")!)   // a Sunday
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: sunday)! }

// --- due dates
check(DueParser.dueDate(in: "MSc Industry by Thursday", now: sunday) == day(4), "weekday → coming one")
check(DueParser.dueDate(in: "next thursday", now: sunday) == day(11), "next weekday")
check(DueParser.dueDate(in: "Pay fees by Tomorrow!", now: sunday) == day(1), "tomorrow")
check(DueParser.dueDate(in: "CCS by 18th", now: sunday) == day(3), "ordinal day")
check(DueParser.dueDate(in: "I sat down", now: sunday) == nil, "no false 'sat'")
check(DueParser.stripDateWords("Cross check MLS by tomorrow!") == "Cross check MLS", "strip date words")
check(DueParser.datePhrase("Pay fees by tomorrow") == "by tomorrow", "date phrase")

// --- rolling words
check(DueParser.rollRelativeWords(in: ">> Pay by Tomorrow!", due: day(1), now: day(1)) == ">> Pay by Today!", "tomorrow → today")
check(DueParser.rollRelativeWords(in: ">> Pay by Today!", due: day(1), now: day(2)) == ">> Pay by Yesterday!", "today → yesterday")
check(DueParser.rollRelativeWords(in: ">> Pay by Yesterday!", due: day(1), now: day(3)) == ">> Pay by Mon 16 Nov!", "→ date")
check(DueParser.rollRelativeWords(in: ">> Pay by Mon 16 Nov!", due: day(1), now: day(4)) == ">> Pay by Mon 16 Nov!", "date stays put")

// --- migration from v1
let v1 = """
{"urgentImportant": ">> MSc Industry by Thursday\\n>> Find sample projects",
 "urgentNotImportant": ">> Pay fees by Tomorrow!", "notUrgentImportant": "", "notUrgentNotImportant": "",
 "dueDates": {"MSc Industry by Thursday": "2026-11-19T00:00:00Z", "Pay fees by Tomorrow!": "2026-11-16T00:00:00Z"},
 "completed": ["Find sample projects"], "updatedAt": "2026-11-15T10:00:00Z"}
""".data(using: .utf8)!
let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
var m = try! dec.decode(MatrixData.self, from: v1)
check(m.migratedFrom == 1 && m.version == 2, "v1 migrated")
check(m.tasks.count == 3, "3 tasks from v1")
check(m.tasks.first { $0.title == "Find sample projects" }?.done == true, "done flag migrated")
check(m.tasks.first { $0.title.hasPrefix("Pay fees") }?.due != nil, "due date migrated")

// --- identity survives edits
let feesID = m.tasks.first { $0.title.hasPrefix("Pay fees") }!.id
m.urgentNotImportant = ">> Pay the fees by Tomorrow!"          // edit the text, same date words
m.sync(now: day(1))
let fees = m.tasks.first { $0.id == feesID }
check(fees?.title == "Pay the fees by Tomorrow!", "edited task keeps its id")
check(fees?.due == ISO8601DateFormatter().date(from: "2026-11-16T00:00:00Z"), "edit without date change keeps due date")

m.urgentNotImportant = ">> Pay the fees by Friday"              // change the date words → re-resolved
m.sync(now: sunday)
check(m.tasks.first { $0.id == feesID }?.due == day(5), "changing date words re-resolves the date")

let findID = m.tasks.first { $0.title == "Find sample projects" }!.id
m.urgentImportant = ">> MSc Industry by Thursday"               // move "Find sample projects" to another box
m.notUrgentImportant = ">> Find sample projects"
m.sync(now: sunday)
let moved = m.tasks.first { $0.id == findID }
check(moved?.box == 2 && moved?.done == true, "moved task keeps id and done state")

m.notUrgentNotImportant = ">> Totally new thing"
m.sync(now: sunday)
check(m.tasks.first { $0.title == "Totally new thing" }?.done == false, "new task isn't done")

// --- done toggling + cleanup
m.toggleDone(box: 0, itemIndexes: [0], now: sunday)
check(m.tasks.first { $0.box == 0 }?.done == true, "toggle done")
let removed = m.cleanUpDone()
check(removed.count == 2, "cleanup removes both done tasks (got \(removed.count))")
check(!m.urgentImportant.contains("MSc") && !m.notUrgentImportant.contains("Find"), "done lines removed from text")
check(m.tasks.allSatisfy { !$0.done }, "only open tasks remain")

// --- round trip
let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
let again = try! dec.decode(MatrixData.self, from: try! enc.encode(m))
check(again.tasks == m.tasks && again.migratedFrom == nil, "save/load round trip keeps tasks and ids")

print(failures == 0 ? "✓ all \(passes) checks passed" : "\(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
