import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

// Persistent probe. Applies random assistant updates to tasks and one-off calendar events, then
// optionally a person's edit, then undoes the assistant's update, and checks the outcome field by
// field: a field the update moved and nothing touched since is back to what it was, a field a
// person changed since keeps the person's value, and a field the update did not move is as it
// was. A second undo must write nothing. An undo may only succeed or refuse in plain words.
//
// Run from apps/apple (the build must be current):
//   UNDOFUZZ_RUN=1 UNDOFUZZ_SEED=1 UNDOFUZZ_ROUNDS=300 swift test --skip-build -j 4 --filter ZZUndoRoundTripProbe
// The test is skipped unless UNDOFUZZ_RUN is set, so a full suite run stays fast. Findings print
// as `UNDOFUZZ` lines, and any finding fails the test.

private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private func pick<T>(_ items: [T], _ rng: inout SplitMix64) -> T {
  items[Int.random(in: 0..<items.count, using: &rng)]
}

private func chance(_ percent: Int, _ rng: inout SplitMix64) -> Bool {
  Int.random(in: 0..<100, using: &rng) < percent
}

private func day(_ number: Int) -> Date {
  Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: number, hour: 12))!
}

private func dayString(_ number: Int) -> String {
  String(format: "2026-11-%02d", number)
}

private func clock(_ minutes: Int) -> String {
  String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

final class ZZUndoRoundTripProbeTests: XCTestCase {
  private var findings: [String] = []
  /// How many undos ran, and how many of them restored something or kept a later edit, so a
  /// run that exercised nothing shows as such in the summary.
  private var counts = ["task": 0, "task restored": 0, "task kept": 0, "event": 0, "event restored": 0, "event kept": 0]

  private func assistant<T>(_ body: () async throws -> T) async throws -> T {
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await body()
    }
  }

  private func changelogCount(_ service: SwiftLorvexCoreService) throws -> Int {
    // The sync layer's own device-local audit rows (a coalesced outbox delete) are not changes.
    try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation NOT LIKE 'sync.%'") ?? -1
    }
  }

  private func latestUpdateID(_ service: SwiftLorvexCoreService, entity: String) throws -> String {
    try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT id FROM ai_changelog
            WHERE entity_id = ? AND operation = 'update' ORDER BY timestamp DESC, id DESC LIMIT 1
            """,
          arguments: [entity])
      })
  }

  private func note(_ seed: UInt64, _ round: Int, _ text: String) {
    findings.append("seed \(seed) round \(round): \(text)")
    print("UNDOFUZZ seed=\(seed) round=\(round) \(text)")
  }

  /// What the undo did, or the plain-words refusal it gave. Anything else is a finding.
  private func undo(
    _ service: SwiftLorvexCoreService, _ id: String, seed: UInt64, round: Int, context: String
  ) async -> UndoAIChangeResult? {
    do {
      return try await service.undoAIChange(changelogID: id)
    } catch let LorvexCoreError.validation(field, message) {
      note(seed, round, "undo refused (\(field)): \(message) | \(context)")
      return nil
    } catch {
      note(seed, round, "undo threw \(error) | \(context)")
      return nil
    }
  }

  /// The changelog rows written after the first `count` ones, newest last, for a finding.
  private func rowsAfter(_ service: SwiftLorvexCoreService, _ count: Int) throws -> String {
    try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT operation, entity_type, summary FROM ai_changelog
          WHERE operation NOT LIKE 'sync.%'
          ORDER BY timestamp ASC, id ASC LIMIT -1 OFFSET ?
          """,
        arguments: [count]
      ).map { "\($0["operation"] as String)/\($0["entity_type"] as String)" }.joined(separator: ",")
    }
  }

  // MARK: - Tasks

  private struct TaskState: Equatable {
    var title: String
    var notes: String
    var priority: Int?
    var estimatedMinutes: Int?
    var dueDate: Date?
    var plannedDate: Date?
    var plannedTime: Range<Int>?
    var availableFrom: Date?
    var tags: [String]
    var dependsOn: [String]

    /// `rawPriority` is the stored value: an unset priority reads as P2 in the model.
    init(_ task: LorvexTask, rawPriority: Int?) {
      title = task.title
      notes = task.notes
      priority = rawPriority
      estimatedMinutes = task.estimatedMinutes
      dueDate = task.dueDate
      plannedDate = task.plannedDate
      plannedTime = task.plannedTime
      availableFrom = task.availableFrom
      tags = task.tags.sorted()
      dependsOn = task.dependsOn.sorted()
    }

    /// The fields an undo restores, as groups: name and value. The planned day and its time are
    /// one group, because a change of day clears the time.
    var groups: [(name: String, value: AnyHashable)] {
      [
        ("title", title), ("notes", notes), ("priority", priority ?? -1),
        ("estimated_minutes", estimatedMinutes ?? -1),
        ("due_date", dueDate ?? .distantPast),
        (
          "planned_date",
          "\(plannedDate.map { "\($0)" } ?? "none")|"
            + (plannedTime.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "none")
        ),
        ("available_from", availableFrom ?? .distantPast),
        ("tags", tags), ("depends_on", dependsOn),
      ]
    }
  }

  private func taskState(_ service: SwiftLorvexCoreService, _ id: String) async throws -> TaskState {
    let task = try await service.loadTask(id: id)
    let raw = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT priority FROM tasks WHERE id = ?", arguments: [id])
    }
    return TaskState(task, rawPriority: raw)
  }

  private func randomTaskDraft(
    _ id: String, others: [String], rng: inout SplitMix64
  ) -> TaskUpdateDraft {
    var draft = TaskUpdateDraft(id: id)
    if chance(40, &rng) { draft.title = pick(["Report", "Taxes", "Call Ana", "Plan trip"], &rng) }
    if chance(40, &rng) { draft.notes = pick(["", "short note", "line one\nline two", "ünïcode ✓"], &rng) }
    if chance(30, &rng) {
      if chance(25, &rng) {
        draft.clearsPriority = true
      } else {
        draft.priority = pick([.p1, .p2, .p3], &rng)
      }
    }
    if chance(30, &rng) {
      draft.estimatedMinutes = chance(30, &rng) ? .clear : .set(pick([5, 25, 90], &rng))
    }
    if chance(30, &rng) {
      draft.dueDate = chance(30, &rng) ? .clear : .set(day(Int.random(in: 1...28, using: &rng)))
    }
    if chance(35, &rng) {
      if chance(30, &rng) {
        draft.plannedDate = .clear
      } else {
        draft.plannedDate = .set(day(Int.random(in: 1...28, using: &rng)))
        if chance(50, &rng) {
          let start = pick([540, 600, 780], &rng)
          draft.plannedTime = .set(start..<(start + pick([30, 60], &rng)))
        }
      }
    } else if chance(15, &rng) {
      draft.plannedTime = chance(50, &rng) ? .clear : .set(480..<540)
    }
    if chance(25, &rng) {
      draft.availableFrom = chance(30, &rng) ? .clear : .set(day(Int.random(in: 1...28, using: &rng)))
    }
    if chance(30, &rng) { draft.tags = ["a", "b", "c"].filter { _ in chance(50, &rng) } }
    if chance(25, &rng) { draft.dependsOn = others.filter { _ in chance(40, &rng) } }
    return draft
  }

  private func runTaskRound(
    _ service: SwiftLorvexCoreService, pool: [String], seed: UInt64, round: Int,
    rng: inout SplitMix64
  ) async throws {
    let id = pick(pool, &rng)
    // A task depends only on tasks later in the pool, so a draft never makes a cycle.
    let later = Array(pool[(pool.firstIndex(of: id)! + 1)...])
    let s0 = try await taskState(service, id)
    let countBefore = try changelogCount(service)
    let update = randomTaskDraft(id, others: later, rng: &rng)
    do {
      _ = try await assistant { try await service.updateTask(update) }
    } catch {
      return  // a draft the update itself refuses is not an undo case
    }
    guard try changelogCount(service) > countBefore else { return }  // it changed nothing
    let changelogID = try latestUpdateID(service, entity: id)
    let s1 = try await taskState(service, id)

    // Sometimes a person edits afterwards.
    var s2 = s1
    if chance(50, &rng) {
      let edit = randomTaskDraft(id, others: later, rng: &rng)
      do {
        _ = try await service.updateTask(edit)
        s2 = try await taskState(service, id)
      } catch {}
    }

    let countBeforeUndo = try changelogCount(service)
    let context = "before \(s0) update \(s1) since \(s2) draft \(update)"
    guard
      let result = await undo(
        service, changelogID, seed: seed, round: round, context: context)
    else { return }
    counts["task", default: 0] += 1
    if !result.reverted.isEmpty { counts["task restored", default: 0] += 1 }
    if !result.kept.isEmpty { counts["task kept", default: 0] += 1 }
    let s3 = try await taskState(service, id)
    for (index, group) in s0.groups.enumerated() {
      let moved = group.value != s1.groups[index].value
      let editedSince = s1.groups[index].value != s2.groups[index].value
      let expected: AnyHashable = (moved && !editedSince) ? group.value : s2.groups[index].value
      if s3.groups[index].value != expected {
        note(
          seed, round,
          "task \(group.name): expected \(expected), got \(s3.groups[index].value) "
            + "(before \(group.value), update \(s1.groups[index].value), since \(s2.groups[index].value)); "
            + "reverted \(result.reverted) kept \(result.kept); draft \(update)")
      }
    }
    let again = await undo(service, changelogID, seed: seed, round: round, context: context)
    if let again, !again.reverted.isEmpty {
      note(seed, round, "task: a second undo restored \(again.reverted)")
    }
    let written = try changelogCount(service) - countBeforeUndo
    if written != (result.reverted.isEmpty ? 0 : 1) {
      note(
        seed, round,
        "task: undo wrote \(written) changelog rows for reverted \(result.reverted): "
          + "\(try rowsAfter(service, countBeforeUndo)) | \(context)")
    }
  }

  // MARK: - Calendar events

  private func randomEventUpdate(
    _ service: SwiftLorvexCoreService, _ id: String, rng: inout SplitMix64
  ) async throws {
    let allDay: Bool? = chance(20, &rng) ? chance(50, &rng) : nil
    let timed = allDay.map { !$0 } ?? false
    let startDate: String? = chance(40, &rng) ? dayString(Int.random(in: 1...20, using: &rng)) : nil
    var startTime: String?
    var endTime: String?
    if timed || (allDay == nil && chance(35, &rng)) {
      let start = pick([480, 540, 720, 900], &rng)
      startTime = clock(start)
      if chance(60, &rng) { endTime = clock(start + pick([30, 60, 90], &rng)) }
    }
    var attendees: CalendarEventAttendeesPatch = .unset
    if chance(25, &rng) {
      attendees =
        chance(25, &rng)
        ? .clear
        : .set(
          [("ana@example.com", "Ana"), ("bo@example.com", nil), ("", "Cy")]
            .filter { _ in chance(50, &rng) }
            .map { CalendarEventAttendee(email: $0.0, name: $0.1) })
    }
    _ = try await service.updateCalendarEvent(
      id: id, title: chance(35, &rng) ? pick(["Dentist", "Lunch", "Review"], &rng) : nil,
      startDate: startDate, endDate: nil, startTime: startTime, endTime: endTime, allDay: allDay,
      location: chance(30, &rng) ? pick(["", "Clinic", "Annex"], &rng) : nil,
      notes: chance(30, &rng) ? pick(["", "bring forms", "a\nb"], &rng) : nil,
      recurrence: .unset,
      timezone: chance(20, &rng) ? pick(["America/New_York", "Europe/Berlin"], &rng) : nil,
      url: chance(20, &rng) ? pick(["", "https://example.com/a"], &rng) : nil,
      color: chance(20, &rng) ? pick(["", "#FF8800"], &rng) : nil,
      eventType: nil,
      personName: chance(20, &rng) ? pick(["", "Dr. Lee"], &rng) : nil,
      attendees: attendees)
  }

  private func eventGroups(_ event: CalendarTimelineEvent) -> [(name: String, value: AnyHashable)] {
    [
      ("title", event.title), ("description", event.notes ?? "\u{0}nil"),
      (
        "schedule",
        "\(event.startDate)|\(event.startTime ?? "-")|\(event.endDate ?? "-")|\(event.endTime ?? "-")|\(event.allDay)|\(event.timezone ?? "-")"
      ),
      ("location", event.location ?? "\u{0}nil"), ("url", event.url ?? "\u{0}nil"),
      ("color", event.color ?? "\u{0}nil"), ("person_name", event.personName ?? "\u{0}nil"),
      ("attendees", (event.attendees ?? []).map { "\($0.email)|\($0.name ?? "-")" }),
    ]
  }

  private func runEventRound(
    _ service: SwiftLorvexCoreService, pool: [String], seed: UInt64, round: Int,
    rng: inout SplitMix64
  ) async throws {
    let id = pick(pool, &rng)
    let before = try await eventNow(service, id)
    let countBefore = try changelogCount(service)
    do {
      try await assistant { try await randomEventUpdate(service, id, rng: &rng) }
    } catch {
      return
    }
    guard try changelogCount(service) > countBefore else { return }
    let changelogID = try latestUpdateID(service, entity: id)
    let afterUpdate = try await eventNow(service, id)

    var since = afterUpdate
    if chance(50, &rng) {
      do {
        try await randomEventUpdate(service, id, rng: &rng)
        since = try await eventNow(service, id)
      } catch {}
    }

    let countBeforeUndo = try changelogCount(service)
    let context = "before \(before) update \(afterUpdate) since \(since)"
    guard
      let result = await undo(
        service, changelogID, seed: seed, round: round, context: context)
    else { return }
    counts["event", default: 0] += 1
    if !result.reverted.isEmpty { counts["event restored", default: 0] += 1 }
    if !result.kept.isEmpty { counts["event kept", default: 0] += 1 }
    let after = try await eventNow(service, id)
    let g0 = eventGroups(before)
    let g1 = eventGroups(afterUpdate)
    let g2 = eventGroups(since)
    let g3 = eventGroups(after)
    for index in g0.indices {
      let moved = g0[index].value != g1[index].value
      let editedSince = g1[index].value != g2[index].value
      let expected: AnyHashable = (moved && !editedSince) ? g0[index].value : g2[index].value
      if g3[index].value != expected {
        note(
          seed, round,
          "event \(g0[index].name): expected \(expected), got \(g3[index].value) "
            + "(before \(g0[index].value), update \(g1[index].value), since \(g2[index].value)); "
            + "reverted \(result.reverted) kept \(result.kept)")
      }
    }
    let again = await undo(service, changelogID, seed: seed, round: round, context: context)
    if let again, !again.reverted.isEmpty {
      note(seed, round, "event: a second undo restored \(again.reverted)")
    }
    let written = try changelogCount(service) - countBeforeUndo
    if written != (result.reverted.isEmpty ? 0 : 1) {
      note(
        seed, round,
        "event: undo wrote \(written) changelog rows for reverted \(result.reverted): "
          + "\(try rowsAfter(service, countBeforeUndo)) | \(context)")
    }
  }

  private func eventNow(_ service: SwiftLorvexCoreService, _ id: String) async throws
    -> CalendarTimelineEvent
  {
    let row = try service.read { db in try CalendarTimelineQueries.getStoredCalendarEvent(db, id: id) }
    return SwiftLorvexCalendarDeserializers.event(try XCTUnwrap(row))
  }

  // MARK: - The run

  func testUndoRoundTrips() async throws {
    let environment = ProcessInfo.processInfo.environment
    try XCTSkipUnless(environment["UNDOFUZZ_RUN"] != nil, "set UNDOFUZZ_RUN=1 to run this probe")
    let seed = UInt64(environment["UNDOFUZZ_SEED"] ?? "1") ?? 1
    let rounds = Int(environment["UNDOFUZZ_ROUNDS"] ?? "300") ?? 300
    var rng = SplitMix64(state: seed)
    let service = try SwiftLorvexCoreService.inMemory()

    var tasks: [String] = []
    for title in ["One", "Two", "Three", "Four"] {
      tasks.append(try await service.createTask(title: title, notes: "start").id)
    }
    var events: [String] = []
    for (index, title) in ["Alpha", "Beta"].enumerated() {
      let created = try await service.createCalendarEvent(
        title: title, startDate: dayString(3 + index), endDate: nil, startTime: "09:00",
        endTime: "10:00", allDay: false, location: "Clinic", notes: "start", recurrence: nil,
        timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil, personName: nil,
        attendees: nil)
      events.append(created.id)
    }

    for round in 0..<rounds {
      if chance(55, &rng) {
        try await runTaskRound(service, pool: tasks, seed: seed, round: round, rng: &rng)
      } else {
        try await runEventRound(service, pool: events, seed: seed, round: round, rng: &rng)
      }
    }
    print(
      "UNDOFUZZ summary seed=\(seed) rounds=\(rounds) findings=\(findings.count) "
        + "\(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
    XCTAssertTrue(findings.isEmpty, "\(findings.count) finding(s), first: \(findings.first ?? "")")
  }
}
