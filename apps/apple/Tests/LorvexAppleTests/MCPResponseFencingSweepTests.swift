import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import MCP
import Testing

@testable import LorvexMCPHost

/// A model reads every MCP response, so text a person or another session
/// authored must sit inside the `⟦user⟧…⟦/user⟧` fence wherever a tool returns
/// it. The fence is applied by response key name, so a field the key list does
/// not name, or a user string used as a JSON object key, escapes it.
///
/// Each user-text field of a seeded dataset carries its own marker
/// (`ZQtaskTitleZQ`). The suite writes the dataset, rewrites and refuses
/// operations on it, calls every read tool, and applies the writes that end
/// records (cancel, archive, delete) to a second copy of the dataset. It fails
/// when a marker appears in a response outside a fence or as an object key, and
/// when some write tool never ran successfully, since an unexercised tool's
/// response would go unchecked. Text the caller itself sent is not stored
/// content, so a call sends a marker only to store it or to name the record it
/// ends.
@Suite("MCP responses fence user text")
struct MCPResponseFencingSweepTests {
  // MARK: - Scanner

  /// Finds markers that a response leaves outside the fence.
  enum FenceScan {
    private static let open = "\u{27E6}user\u{27E7}"
    private static let close = "\u{27E6}/user\u{27E7}"
    // Tags are stored in lower case, so the match ignores case.
    private static let markerPattern = try! NSRegularExpression(
      pattern: "zq[a-z]+zq", options: [.caseInsensitive])

    /// Every marker in `text`, in order, each with whether a fence covers it.
    static func markers(in text: String) -> [(marker: String, fenced: Bool)] {
      var fences: [Range<String.Index>] = []
      var cursor = text.startIndex
      while let start = text.range(of: open, range: cursor..<text.endIndex) {
        // An opening sentinel nothing closes fences nothing.
        guard let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
          break
        }
        fences.append(start.upperBound..<end.lowerBound)
        cursor = end.upperBound
      }
      let whole = NSRange(text.startIndex..., in: text)
      return markerPattern.matches(in: text, range: whole).compactMap { match in
        guard let range = Range(match.range, in: text) else { return nil }
        return (
          String(text[range]),
          fences.contains { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }
        )
      }
    }

    /// Where `value` carries a marker outside a fence or as an object key.
    static func leaks(in value: Value, path: String = "$") -> [String] {
      switch value {
      case .string(let text):
        return markers(in: text).filter { !$0.fenced }.map { "\(path): \($0.marker) outside a fence" }
      case .object(let object):
        var found: [String] = []
        for (key, child) in object.sorted(by: { $0.key < $1.key }) {
          for hit in markers(in: key) { found.append("\(path): object key carries \(hit.marker)") }
          found += leaks(in: child, path: "\(path).\(key)")
        }
        return found
      case .array(let items):
        return items.enumerated().flatMap { leaks(in: $0.element, path: "\(path)[\($0.offset)]") }
      default:
        return []
      }
    }

    /// Every marker anywhere in `value`, lower-cased, fenced or not.
    static func allMarkers(in value: Value) -> Set<String> {
      switch value {
      case .string(let text):
        return Set(markers(in: text).map { $0.marker.lowercased() })
      case .object(let object):
        return object.reduce(into: Set<String>()) { found, entry in
          found.formUnion(markers(in: entry.key).map { $0.marker.lowercased() })
          found.formUnion(allMarkers(in: entry.value))
        }
      case .array(let items):
        return items.reduce(into: Set<String>()) { $0.formUnion(allMarkers(in: $1)) }
      default:
        return []
      }
    }
  }

  /// Collects what a run of calls returned.
  private final class Recorder {
    var leaks: [String] = []
    var seen: Set<String> = []
    var rejected: [String] = []
    var succeeded: Set<String> = []
    var lastFailure: [String: String] = [:]

    func record(_ result: CallTool.Result, tool: String, label: String) {
      if let structured = result.structuredContent {
        for leak in FenceScan.leaks(in: structured) { leaks.append("\(tool) \(label): \(leak)") }
        seen.formUnion(FenceScan.allMarkers(in: structured))
      }
      let text = mcpTextContent(result)
      for hit in FenceScan.markers(in: text) {
        seen.insert(hit.marker.lowercased())
        if !hit.fenced {
          leaks.append("\(tool) \(label): text content carries \(hit.marker) outside a fence")
        }
      }
    }
  }

  private static func marker(_ field: String) -> String { "ZQ\(field)ZQ" }

  private static func text(_ field: String) -> Value { .string(marker(field)) }

  @Test("the scanner finds a marker outside a fence and accepts one inside")
  func scannerBehavior() {
    let fenced = "\u{27E6}user\u{27E7}ZQaZQ\u{27E6}/user\u{27E7}"
    #expect(FenceScan.leaks(in: .string(fenced)).isEmpty)
    #expect(FenceScan.leaks(in: .string("ZQaZQ")).count == 1)
    #expect(FenceScan.leaks(in: .string("zqaZQ")).count == 1)
    #expect(FenceScan.leaks(in: .string("Created \(fenced) in ZQbZQ")).count == 1)
    #expect(FenceScan.leaks(in: .string("\u{27E6}user\u{27E7}ZQaZQ")).count == 1)
    #expect(FenceScan.leaks(in: .object(["ZQkeyZQ": .int(1)])).count == 1)
    #expect(FenceScan.leaks(in: .object(["title": .array([.string("ZQaZQ")])])).count == 1)
    #expect(FenceScan.leaks(in: .object(["title": .array([.string(fenced)])])).isEmpty)
    #expect(
      FenceScan.allMarkers(in: .object(["a": .string(fenced), "b": .string("ZQcZQ")]))
        == ["zqazq", "zqczq"])
  }

  // MARK: - Dataset

  /// One marker for every user-text field a tool can store, so a leak names
  /// the field it came from. Every one must reach some response, or the sweep
  /// proves nothing about its field.
  private static let storedMarkers: Set<String> = [
    "listName", "listDescription", "listAiNotes", "listAiNotesAgain",
    "taskTitle", "taskNotes", "taskTag", "taskAiNotes", "rawInput", "checklistItem",
    "appendedBody", "blockedTitle", "deferNote", "batchDeferNote",
    "habitName", "habitCue",
    "eventTitle", "eventNotes", "eventLocation", "eventPerson", "attendeeName",
    "memoryKey", "memoryContent",
    "reviewSummary", "reviewWins", "reviewBlockers", "reviewLearnings",
    "briefing", "setupSummary",
    "renamedTag", "mergedTag", "updatedTitle", "updatedNotes", "updatedTag", "updatedListName",
    "updatedListDescription", "updatedHabitName", "updatedHabitCue", "updatedEventTitle",
    "updatedEventLocation", "renamedMemoryKey", "amendedSummary", "amendedWins",
    "checklistExtra", "checklistUpdated", "batchUpdatedTitle", "batchCreatedTitle", "batchTag",
    "batchEventTitle", "providerTitle", "providerNotes", "providerLocation",
    "spareListName", "seriesTitle", "scopedTitle", "scopedLocation", "scopedNotes",
  ].reduce(into: Set<String>()) { $0.insert("zq\($1)zq".lowercased()) }

  private struct Dataset {
    var list = ""
    var task = ""
    var blocked = ""
    var habit = ""
    var event = ""
    /// A recent day: a daily review refuses a date more than a week old.
    var reviewDate = ""
  }

  private static func isoDay(daysAgo: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)))
  }

  /// Mirrors one event from another calendar (EventKit), whose title, notes,
  /// and location a stranger's invitation can set, and returns its key.
  private func mirrorProviderEvent(_ service: SwiftLorvexCoreService) async throws -> String {
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(
        from: [
          EventKitFetchedEvent(
            key: "ek-sweep", title: Self.marker("providerTitle"),
            notes: Self.marker("providerNotes"), startDate: "2026-05-30", startTime: "15:00",
            endDate: "2026-05-30", endTime: "15:45", allDay: false,
            location: Self.marker("providerLocation"), timezone: nil)
        ],
        scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-05-30", windowEnd: "2026-05-30")
    return "ek-sweep"
  }

  private func id(of structured: Value?) -> String {
    structured?.objectValue?["id"]?.stringValue ?? ""
  }

  /// How a write is expected to end.
  private enum Outcome { case succeeds, refused, either }

  /// Calls tools on a registry and scans every response.
  private struct Caller {
    let registry: ToolRegistry
    let recorder: Recorder

    /// Calls `tool`. A call whose outcome differs from `outcome` is recorded as
    /// rejected, since the sweep would then miss the fields it was meant to
    /// store or refuse.
    @discardableResult
    func call(
      _ tool: String, _ arguments: [String: Value], _ outcome: Outcome = .succeeds
    ) async throws -> Value? {
      let result = try await mcpRegistryCall(registry, tool: tool, arguments: arguments)
      recorder.record(result, tool: tool, label: "write")
      let failed = result.isError == true
      if failed {
        recorder.lastFailure[tool] = String(mcpTextContent(result).prefix(160))
      } else {
        recorder.succeeded.insert(tool)
      }
      if (outcome == .succeeds && failed) || (outcome == .refused && !failed) {
        recorder.rejected.append(
          "\(tool) \(outcome == .refused ? "was not refused" : "failed"): \(mcpTextContent(result).prefix(200))"
        )
      }
      return result.structuredContent
    }
  }

  /// Writes the dataset through the real tools, then rewrites and refuses
  /// operations on it, scanning every response as it goes.
  private func buildDataset(
    _ caller: Caller, _ service: SwiftLorvexCoreService
  ) async throws -> Dataset {
    func call(
      _ tool: String, _ arguments: [String: Value], refused: Bool = false
    ) async throws -> Value? {
      try await caller.call(tool, arguments, refused ? .refused : .succeeds)
    }

    var data = Dataset()
    data.reviewDate = Self.isoDay(daysAgo: 1)

    // MARK: Stored text, one marker per field
    data.list = id(
      of: try await call(
        "create_list",
        [
          "name": Self.text("listName"), "description": Self.text("listDescription"),
          "ai_notes": Self.text("listAiNotes"),
        ]))
    data.task = id(
      of: try await call(
        "create_task",
        [
          "title": Self.text("taskTitle"), "notes": Self.text("taskNotes"),
          "tags": .array([Self.text("taskTag")]), "raw_input": Self.text("rawInput"),
          "checklist": .array([Self.text("checklistItem")]), "list_id": .string(data.list),
          "due_date": "2026-05-30", "planned_date": "2026-05-30", "priority": 1,
        ]))
    _ = try await call(
      "set_task_ai_notes", ["task_id": .string(data.task), "notes": Self.text("taskAiNotes")])
    _ = try await call(
      "append_to_task_body", ["task_id": .string(data.task), "text": Self.text("appendedBody")])
    _ = try await call(
      "add_task_reminder",
      ["task_id": .string(data.task), "reminder_at": "2026-05-30T09:00:00Z"])
    data.blocked = id(
      of: try await call(
        "create_task",
        ["title": Self.text("blockedTitle"), "depends_on": .array([.string(data.task)])]))
    _ = try await call(
      "defer_task",
      ["id": .string(data.blocked), "until_date": "2026-06-02", "reason": Self.text("deferNote")])

    data.habit = id(
      of: try await call(
        "create_habit", ["name": Self.text("habitName"), "cue": Self.text("habitCue")]))
    _ = try await call("complete_habit", ["id": .string(data.habit)])
    _ = try await call(
      "upsert_habit_reminder_policy",
      ["habit_id": .string(data.habit), "reminder_time": "08:00"])

    data.event = id(
      of: try await call(
        "create_calendar_event",
        [
          "title": Self.text("eventTitle"), "start_date": "2026-05-30", "start_time": "10:00",
          "end_time": "11:00", "location": Self.text("eventLocation"),
          "notes": Self.text("eventNotes"), "person_name": Self.text("eventPerson"),
          "attendees": .array([.object(["name": Self.text("attendeeName")])]),
        ]))
    _ = try await call(
      "link_task_to_event", ["task_id": .string(data.task), "event_id": .string(data.event)])
    let providerEvent = try await mirrorProviderEvent(service)
    _ = try await call(
      "link_task_to_provider_event",
      [
        "task_id": .string(data.task), "provider_event_id": .string(providerEvent),
        "provider_source": "eventkit",
      ])

    _ = try await call(
      "write_memory", ["key": Self.text("memoryKey"), "content": Self.text("memoryContent")])
    _ = try await call(
      "add_daily_review",
      [
        "date": .string(data.reviewDate), "summary": Self.text("reviewSummary"),
        "wins": Self.text("reviewWins"), "blockers": Self.text("reviewBlockers"),
        "learnings": Self.text("reviewLearnings"), "linked_task_ids": .array([.string(data.task)]),
      ])
    _ = try await call(
      "set_daily_briefing", ["date": .string(data.reviewDate), "briefing": Self.text("briefing")])
    _ = try await call(
      "set_preference", ["key": "setup_summary", "value": Self.text("setupSummary")])
    _ = try await call(
      "save_daily_schedule",
      [
        "date": "2026-05-30",
        "times": .array([
          .object(["task_id": .string(data.task), "start_time": "09:00", "end_time": "10:00"])
        ]),
      ])

    // MARK: Rewrites that echo stored text
    _ = try await call(
      "update_task",
      [
        "id": .string(data.task), "title": Self.text("updatedTitle"),
        "notes": Self.text("updatedNotes"), "tags": .array([Self.text("updatedTag")]),
      ])
    _ = try await call(
      "update_list",
      [
        "id": .string(data.list), "name": Self.text("updatedListName"),
        "description": Self.text("updatedListDescription"),
      ])
    _ = try await call(
      "set_list_ai_notes", ["list_id": .string(data.list), "notes": Self.text("listAiNotesAgain")])
    _ = try await call(
      "update_habit",
      [
        "id": .string(data.habit), "name": Self.text("updatedHabitName"),
        "cue": Self.text("updatedHabitCue"),
      ])
    _ = try await call(
      "update_calendar_event",
      [
        "event_id": .string(data.event), "title": Self.text("updatedEventTitle"),
        "location": Self.text("updatedEventLocation"),
      ])
    _ = try await call(
      "rename_memory",
      ["old_key": Self.text("memoryKey"), "new_key": Self.text("renamedMemoryKey")])
    _ = try await call(
      "amend_daily_review",
      [
        "date": .string(data.reviewDate), "summary": Self.text("amendedSummary"),
        "wins": Self.text("amendedWins"),
      ])
    _ = try await call(
      "add_task_checklist_item", ["task_id": .string(data.task), "text": Self.text("checklistExtra")])
    let checklist = try await call("get_task", ["id": .string(data.task)])?
      .objectValue?["checklist_items"]?.arrayValue
    if let item = checklist?.first?.objectValue?["id"]?.stringValue {
      _ = try await call(
        "update_task_checklist_item", ["item_id": .string(item), "text": Self.text("checklistUpdated")])
      _ = try await call(
        "toggle_task_checklist_item", ["item_id": .string(item), "completed": true])
    }
    _ = try await call(
      "batch_update_tasks",
      ["updates": .array([.object(["id": .string(data.task), "title": Self.text("batchUpdatedTitle")])])])
    _ = try await call(
      "batch_create_tasks",
      [
        "tasks": .array([
          .object(["title": Self.text("batchCreatedTitle"), "tags": .array([Self.text("batchTag")])])
        ])
      ])
    _ = try await call(
      "batch_create_calendar_events",
      [
        "events": .array([
          .object([
            "title": Self.text("batchEventTitle"), "start_date": "2026-05-31",
            "start_time": "13:00", "end_time": "14:00",
          ])
        ])
      ])
    _ = try await call(
      "batch_defer_tasks",
      [
        "task_ids": .array([.string(data.task)]), "until_date": "2026-06-03",
        "reason": Self.text("batchDeferNote"),
      ])
    _ = try await call("move_task_to_list", ["id": .string(data.task), "list_id": "inbox"])
    _ = try await call(
      "batch_move_tasks", ["task_ids": .array([.string(data.blocked)]), "list_id": .string(data.list)]
    )
    _ = try await call("rename_tag", ["old_name": "zqtasktagzq", "new_name": Self.text("renamedTag")])
    _ = try await call(
      "create_task", ["title": "Tagged for the merge", "tags": .array([Self.text("mergedTag")])])
    _ = try await call("merge_tags", ["source": "zqrenamedtagzq", "target": "zqmergedtagzq"])

    // MARK: Refusals that name stored text
    _ = try await call("start_task", ["id": .string(data.blocked)], refused: true)
    _ = try await call(
      "update_task",
      ["id": .string(data.task), "depends_on": .array([.string(data.blocked)])], refused: true)
    return data
  }

  /// Applies the write tools the dataset has not used to a second copy of it,
  /// scanning each echo. Some of these end a record, so they run on their own
  /// copy and leave the first one for the read calls.
  private func consumeDataset(_ caller: Caller, _ data: Dataset) async throws {
    func call(_ tool: String, _ arguments: [String: Value]) async throws -> Value? {
      try await caller.call(tool, arguments, .either)
    }
    let task = Value.string(data.task)
    let blocked = Value.string(data.blocked)

    // Reminders come first: ending a task clears its pending ones.
    _ = try await call(
      "set_task_reminders",
      ["task_id": task, "reminders": ["2026-05-31T09:00:00Z", "2026-06-01T09:00:00Z"]])
    let fetched = try await call("get_task", ["id": task])?.objectValue
    if let reminder = fetched?["reminders"]?.arrayValue?.first?.objectValue?["id"]?.stringValue {
      _ = try await call("remove_task_reminder", ["task_id": task, "reminder_id": .string(reminder)])
    }

    // Lifecycle
    for tool in ["pause_task", "set_task_someday", "reopen_task", "start_task", "complete_task"] {
      _ = try await call(tool, ["id": task])
    }
    _ = try await call("cancel_task", ["id": blocked])
    _ = try await call("reopen_task", ["id": blocked])
    _ = try await call("batch_cancel_tasks", ["task_ids": .array([task, blocked])])
    _ = try await call("batch_reopen_tasks", ["task_ids": .array([task, blocked])])
    _ = try await call("batch_complete_tasks", ["task_ids": .array([task, blocked])])
    _ = try await call("batch_cancel_tasks_in_list", ["list_id": .string(data.list)])

    // Recurrence
    _ = try await call(
      "set_task_recurrence",
      ["task_id": blocked, "recurrence": .object(["freq": "WEEKLY", "interval": 1])])
    _ = try await call(
      "add_task_recurrence_exception", ["task_id": blocked, "occurrence_date": "2026-06-09"])
    _ = try await call(
      "remove_task_recurrence_exception", ["task_id": blocked, "occurrence_date": "2026-06-09"])
    _ = try await call("remove_task_recurrence", ["task_id": blocked])

    // Checklist items
    let refreshed = try await call("get_task", ["id": task])?.objectValue
    let items = (refreshed?["checklist_items"]?.arrayValue ?? []).compactMap {
      $0.objectValue?["id"]?.stringValue
    }
    _ = try await call(
      "reorder_task_checklist_items",
      ["task_id": task, "item_ids": .array(items.reversed().map(Value.string))])
    if let item = items.first {
      _ = try await call("remove_task_checklist_item", ["item_id": .string(item)])
    }

    // Links, then a repeating event for the scoped edits and exceptions
    _ = try await call("unlink_task_from_event", ["task_id": task, "event_id": .string(data.event)])
    _ = try await call(
      "unlink_task_from_provider_event", ["task_id": task, "provider_event_id": "ek-sweep"])
    let series = Value.string(
      id(
        of: try await call(
          "create_calendar_event",
          [
            "title": Self.text("seriesTitle"), "start_date": "2026-05-30", "start_time": "10:00",
            "end_time": "11:00", "recurrence": .object(["freq": "WEEKLY", "interval": 1]),
          ])))
    _ = try await call(
      "add_calendar_event_exception", ["event_id": series, "occurrence_date": "2026-06-06"])
    _ = try await call(
      "remove_calendar_event_exception", ["event_id": series, "occurrence_date": "2026-06-06"])
    for (scope, date) in [("this_only", "2026-06-13"), ("this_and_following", "2026-06-20")] {
      _ = try await call(
        "edit_scoped_calendar_event",
        [
          "event_id": series, "occurrence_date": .string(date), "scope": .string(scope),
          "title": Self.text("scopedTitle"), "location": Self.text("scopedLocation"),
          "notes": Self.text("scopedNotes"),
        ])
    }
    _ = try await call(
      "delete_scoped_calendar_event",
      ["event_id": series, "occurrence_date": "2026-06-06", "scope": "this_only"])
    _ = try await call("delete_calendar_event", ["event_id": .string(data.event)])

    // Lists: only an empty one can be deleted
    _ = try await call("archive_list", ["id": .string(data.list)])
    _ = try await call("unarchive_list", ["id": .string(data.list)])
    _ = try await call("reorder_lists", ["list_ids": .array([.string(data.list), "inbox"])])
    let spare = id(of: try await call("create_list", ["name": Self.text("spareListName")]))
    _ = try await call("delete_list", ["id": .string(spare)])

    // Habits
    _ = try await call("adjust_habit_completion", ["id": .string(data.habit), "delta": 1])
    _ = try await call("uncomplete_habit", ["id": .string(data.habit)])
    _ = try await call(
      "batch_complete_habits",
      ["habit_ids": .array([.string(data.habit)]), "date": .string(data.reviewDate)])
    _ = try await call("reorder_habits", ["habit_ids": .array([.string(data.habit)])])
    let policies = try await call("get_habit_reminder_policies", ["habit_id": .string(data.habit)])
    if let policy = policies?.objectValue?["policies"]?.arrayValue?.first?.objectValue?["id"]?
      .stringValue
    {
      _ = try await call("delete_habit_reminder_policy", ["id": .string(policy)])
    }
    _ = try await call("delete_habit", ["id": .string(data.habit)])

    // Memory, tags, preferences, setup, and tasks that end for good
    _ = try await call("delete_memory", ["key": Self.text("renamedMemoryKey")])
    _ = try await call("delete_tag", ["name": "zqupdatedtagzq"])
    _ = try await call("delete_preference", ["key": "setup_summary"])
    _ = try await call(
      "complete_setup",
      [
        "working_hours": "09:00-17:00", "timezone": "America/New_York",
        "default_list_id": .string(data.list),
      ])
    _ = try await call("archive_task", ["id": task])
    _ = try await call("unarchive_task", ["id": task])
    _ = try await call("archive_task", ["id": task])
    _ = try await call("permanent_delete_task", ["id": task])
  }

  /// The arguments each read tool is called with. A read tool with a required
  /// argument must have an entry, so a tool added later cannot go unscanned.
  private func readCalls(_ data: Dataset) -> [(tool: String, arguments: [String: Value])] {
    let range: [String: Value] = ["from": "2026-05-01", "to": "2026-06-30"]
    var calls: [(String, [String: Value])] = [
      ("export_calendar_ics", range),
      ("export_data", ["entities": ["all"]]),
      ("export_data", ["entities": ["all"], "format": "csv"]),
      ("get_ai_changelog", [:]),
      ("get_all_preferences", [:]),
      ("get_calendar_timeline", range),
      ("get_calendar_timeline", range.merging(["shape": "full"]) { $1 }),
      ("get_daily_review", ["date": .string(data.reviewDate)]),
      ("get_daily_schedule", ["date": "2026-05-30"]),
      ("get_deferred_tasks", [:]),
      ("get_deferred_tasks", ["shape": "full"]),
      ("get_dependency_graph", [:]),
      ("get_dependency_graph", ["task_id": .string(data.blocked), "include_inactive": true]),
      ("get_due_task_reminders", ["as_of": "2030-01-01T00:00:00Z"]),
      ("get_guide", [:]),
      ("get_habit_completions", ["habit_id": .string(data.habit)]),
      ("get_habit_reminder_policies", ["habit_id": .string(data.habit)]),
      ("get_habit_stats", ["habit_id": .string(data.habit)]),
      ("get_habits", ["include_stats": true]),
      ("get_linked_events_for_task", ["task_id": .string(data.task)]),
      ("get_linked_events_for_task", ["task_id": .string(data.task), "shape": "full"]),
      ("get_linked_tasks_for_event", ["event_id": .string(data.event)]),
      ("get_list", ["id": .string(data.list)]),
      ("get_list_health_snapshot", [:]),
      ("get_lists", ["include_archived": true]),
      ("get_overview", [:]),
      ("get_overview", ["shape": "full"]),
      ("get_preference", ["key": "setup_summary"]),
      ("get_recent_logs", ["include_details": true, "redact": false, "limit": 500]),
      ("get_review_history", [:]),
      ("get_session_context", [:]),
      ("get_setup_status", [:]),
      ("get_sync_status", [:]),
      ("get_task", ["id": .string(data.task)]),
      ("get_task", ["id": .string(data.blocked)]),
      ("get_upcoming_task_reminders", ["hours": 100_000]),
      ("get_upcoming_tasks", ["days": 3650]),
      ("get_upcoming_tasks", ["days": 3650, "shape": "full"]),
      ("get_weekly_brief", [:]),
      ("list_all_tags", [:]),
      ("list_tasks", [:]),
      ("list_tasks", ["shape": "full"]),
      ("propose_daily_schedule", ["date": "2026-05-30"]),
      ("read_memory", [:]),
      ("search_calendar_events", ["query": "zq"]),
      ("search_calendar_events", ["query": "zq", "shape": "full"]),
      ("search_tasks", ["query": "zq", "status": "all"]),
      ("search_tasks", ["query": "zq", "status": "all", "shape": "full"]),
    ]
    for status in ["open", "completed", "cancelled", "someday"] {
      calls.append(("list_tasks", ["status": .string(status)]))
    }
    return calls
  }

  @Test("every tool fences each user-text field of a dataset it stores, rewrites, refuses, and reads")
  func toolsFenceStoredText() async throws {
    let recorder = Recorder()
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let caller = Caller(registry: registry, recorder: recorder)
    let data = try await buildDataset(caller, service)

    for call in readCalls(data) {
      let result = try await mcpRegistryCall(registry, tool: call.tool, arguments: call.arguments)
      recorder.record(result, tool: call.tool, label: "read \(call.arguments.keys.sorted())")
    }

    // The writes that end records run against a copy of the dataset.
    let (spareRegistry, spareService) = try mcpInMemoryRegistryWithService()
    let spare = Caller(registry: spareRegistry, recorder: recorder)
    try await consumeDataset(spare, try await buildDataset(spare, spareService))

    #expect(
      recorder.rejected.isEmpty,
      "setup calls did not behave as intended:\n\(recorder.rejected.joined(separator: "\n"))")
    #expect(
      recorder.leaks.isEmpty,
      "\(Set(recorder.leaks).count) leaks:\n\(Set(recorder.leaks).sorted().joined(separator: "\n"))")
    let unseen = Self.storedMarkers.subtracting(recorder.seen)
    #expect(
      unseen.isEmpty, "no response carried \(unseen.sorted()); the sweep proves nothing for them")

    let writeTools = Set(ToolDefinitionRegistry.all.filter(\.isWrite).map(\.tool.name))
    let neverSucceeded = writeTools.subtracting(recorder.succeeded)
    #expect(
      neverSucceeded.isEmpty,
      """
      no call to these tools succeeded; add one to buildDataset or consumeDataset:
      \(neverSucceeded.sorted().map { "\($0): \(recorder.lastFailure[$0] ?? "never called")" }.joined(separator: "\n"))
      """)
  }

  @Test("every read tool has an argument entry in the sweep")
  func everyReadToolIsSwept() {
    let swept = Set(readCalls(Dataset()).map(\.tool))
    let readTools = Set(ToolDefinitionRegistry.all.filter { !$0.isWrite }.map(\.tool.name))
    #expect(
      readTools.subtracting(swept).isEmpty,
      "add an entry to readCalls for \(readTools.subtracting(swept).sorted())")
    #expect(
      swept.subtracting(readTools).isEmpty,
      "readCalls names tools that are not read tools: \(swept.subtracting(readTools).sorted())")
  }
}
