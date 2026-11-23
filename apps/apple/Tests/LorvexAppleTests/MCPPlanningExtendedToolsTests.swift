import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Extended — dependency and upcoming registry")
struct MCPDependencyUpcomingExtendedToolsTests {
  @Test("get_dependency_graph returns graph keys")
  func dependencyGraph() async throws {
    let result = try await planningCall(try mcpInMemoryRegistry(), tool: "get_dependency_graph")
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["nodes"] != nil)
    #expect(object?["edges"] != nil)
    #expect(object?["node_count"] != nil)
  }

  @Test("get_upcoming_tasks returns structured task window")
  func upcomingTasks() async throws {
    let result = try await planningCall(
      try mcpInMemoryRegistry(),
      tool: "get_upcoming_tasks",
      arguments: ["days": .int(30)]
    )
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["by_date"] != nil)
    #expect(object?["total_matching"] != nil)
    #expect(object?["from"]?.stringValue != nil)
    #expect(object?["to"]?.stringValue != nil)
  }

  @Test("get_upcoming_tasks reports real pagination and numeric priority")
  func upcomingTasksPaginationAndPriorityShape() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await planningCall(
      registry, tool: "create_task", arguments: ["title": .string("Upcoming paged task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    // Plan a few days out relative to today so the task lands inside the
    // next-30-days upcoming window regardless of the wall-clock date (a
    // hardcoded date silently falls out of the window once the clock passes it).
    let cal = Calendar.current
    let target = cal.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    let ymd = DateFormatter()
    ymd.calendar = cal
    ymd.timeZone = cal.timeZone
    ymd.locale = Locale(identifier: "en_US_POSIX")
    ymd.dateFormat = "yyyy-MM-dd"
    let plannedDate = ymd.string(from: target)
    let updated = try await planningCall(
      registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "planned_date": .string(plannedDate),
        "priority": .int(1),
      ])
    #expect(updated.isError != true)

    let result = try await planningCall(
      registry,
      tool: "get_upcoming_tasks",
      arguments: [
        "days": .int(30),
        "limit": .int(1),
        "offset": .int(0),
      ])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["total_matching"]?.intValue == 1)
    #expect(object["returned"]?.intValue == 1)
    #expect(object["truncated"]?.boolValue == false)
    #expect(object["next_offset"] == nil || object["next_offset"] == .null)

    // The flat `tasks` array is the paginated page and lines up with `returned`.
    let flat = try #require(object["tasks"]?.arrayValue)
    #expect(flat.count == object["returned"]?.intValue)
    #expect(flat.first?.objectValue?["id"]?.stringValue == taskID)

    let task = try #require(flat.first?.objectValue)
    #expect(task["priority"]?.intValue == 1)
    #expect(task["priority_label"]?.stringValue == "P1")

    // `by_date` names the day's rows by id, so no row is sent twice.
    let groups = object["by_date"]?.objectValue ?? [:]
    #expect(groups[plannedDate]?.arrayValue == [.string(taskID)])
  }

  @Test("get_upcoming_tasks on the core bridge emits a flat tasks array aligned with by_date")
  func upcomingTasksCoreBridgeFlatAndGrouped() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let cal = Calendar.current
    let target = cal.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    let ymd = DateFormatter()
    ymd.calendar = cal
    ymd.timeZone = cal.timeZone
    ymd.locale = Locale(identifier: "en_US_POSIX")
    ymd.dateFormat = "yyyy-MM-dd"
    let plannedDate = ymd.string(from: target)
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Upcoming flat task"), "planned_date": .string(plannedDate)])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "get_upcoming_tasks", arguments: ["days": .int(30)])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    let flat = try #require(object["tasks"]?.arrayValue)
    #expect(flat.contains { $0.objectValue?["id"]?.stringValue == taskID })
    #expect(flat.count == object["returned"]?.intValue)
    // by_date groups the ids of the very same rows; the flat array is the page.
    let grouped = try #require(object["by_date"]?.objectValue)
    let groupedIDs = grouped.values.flatMap { $0.arrayValue ?? [] }.compactMap(\.stringValue)
    #expect(groupedIDs.contains(taskID))
    #expect(groupedIDs.count == flat.count)
  }

  /// The product day `offset` days from the one the server calls today.
  private func day(_ offset: Int, in registry: ToolRegistry) async throws -> String {
    let context = try await mcpRegistryCall(registry, tool: "get_session_context")
    let today = try #require(context.structuredContent?.objectValue?["date"]?.stringValue)
    return try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: offset))
  }

  /// The ids of the task rows under `key` in a result's structured payload.
  private func ids(_ result: CallTool.Result, _ key: String) -> [String] {
    (result.structuredContent?.objectValue?[key]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["id"]?.stringValue }
  }

  @Test("the upcoming window starts tomorrow and ends N days after today")
  func upcomingWindowStartsTomorrow() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "get_upcoming_tasks", arguments: ["days": .int(7)])
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["from"]?.stringValue == (try await day(1, in: registry)))
    #expect(object["to"]?.stringValue == (try await day(7, in: registry)))
  }

  @Test("a deferred overdue task leaves today's list and is upcoming on the day it moved to")
  func deferredOverdueTaskLeavesToday() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Reply to legal"), "due_date": .string(try await day(-3, in: registry)),
      ])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let before = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(ids(before, "today") == [taskID])

    let moved = try await day(2, in: registry)
    let deferred = try await mcpRegistryCall(
      registry, tool: "defer_task",
      arguments: ["id": .string(taskID), "until_date": .string(moved)])
    #expect(deferred.isError != true)

    let after = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(ids(after, "today").isEmpty)
    let stats = try await mcpRegistryCall(registry, tool: "get_overview")
    let counts = try #require(stats.structuredContent?.objectValue?["stats"]?.objectValue)
    #expect(counts["overdue_count"]?.intValue == 0)
    #expect(counts["attention_count"]?.intValue == 0)
    #expect(counts["upcoming_week_count"]?.intValue == 1)
    let upcoming = try await mcpRegistryCall(registry, tool: "get_upcoming_tasks")
    let window = try #require(upcoming.structuredContent?.objectValue)
    #expect(window["by_date"]?.objectValue?[moved]?.arrayValue == [.string(taskID)])
  }

  @Test("deferring a started task pauses it")
  func deferringAStartedTaskPausesIt() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Analyze churn numbers")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(taskID)])

    let deferred = try await mcpRegistryCall(
      registry, tool: "defer_task",
      arguments: ["id": .string(taskID), "until_date": .string(try await day(1, in: registry))])

    #expect(deferred.structuredContent?.objectValue?["status"]?.stringValue == "open")
    let overview = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(ids(overview, "today").isEmpty)
  }

  /// The ids of every task a schedule suggestion placed or left unscheduled.
  private func suggestedIDs(_ result: CallTool.Result) -> Set<String> {
    let object = result.structuredContent?.objectValue
    let placed = (object?["placements"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["task"]?.objectValue?["id"]?.stringValue }
    return Set(placed + ids(result, "unscheduled"))
  }

  @Test("a schedule suggestion for a later day holds that day's tasks, not today's")
  func scheduleForALaterDayHoldsThatDaysTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let late = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Reply to legal"), "due_date": .string(try await day(-3, in: registry)),
      ])
    let lateID = try #require(late.structuredContent?.objectValue?["id"]?.stringValue)
    let later = try await day(2, in: registry)
    let planned = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Prepare slides"), "planned_date": .string(later)])
    let plannedID = try #require(planned.structuredContent?.objectValue?["id"]?.stringValue)

    let laterDay = try await mcpRegistryCall(
      registry, tool: "propose_daily_schedule", arguments: ["date": .string(later)])
    #expect(suggestedIDs(laterDay) == [plannedID])
    let today = try await mcpRegistryCall(registry, tool: "propose_daily_schedule")
    #expect(suggestedIDs(today) == [lateID])
  }

  @Test("a task with no due date starts repeating on the day it is planned for")
  func recurrenceStartsOnThePlannedDay() async throws {
    let registry = try mcpInMemoryRegistry()
    let rule: Value = .object(["freq": .string("DAILY"), "interval": .int(3)])
    let later = try await day(3, in: registry)
    // A plan that has passed is not a start day: the series starts today and
    // the plan moves to today with it.
    for (plannedDate, firstOccurrence) in [
      (later, later), (try await day(-2, in: registry), try await day(0, in: registry)),
    ] {
      let created = try await mcpRegistryCall(
        registry, tool: "create_task",
        arguments: ["title": .string("Water the plants"), "planned_date": .string(plannedDate)])
      let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
      let repeating = try await mcpRegistryCall(
        registry, tool: "set_task_recurrence",
        arguments: ["task_id": .string(taskID), "recurrence": rule])
      #expect(repeating.isError != true)
      let task = try #require(repeating.structuredContent?.objectValue)
      #expect(task["due_date"]?.stringValue == firstOccurrence)
      #expect(task["planned_date"]?.stringValue == firstOccurrence)
    }
  }

  @Test("defer_task and batch_defer_tasks refuse a day that is not after today")
  func deferRefusesTodayAndEarlier() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Reply to legal"), "due_date": .string(try await day(-3, in: registry)),
      ])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    for offset in [0, -1] {
      let single = try await mcpRegistryCall(
        registry, tool: "defer_task",
        arguments: ["id": .string(taskID), "until_date": .string(try await day(offset, in: registry))])
      #expect(single.isError == true)
      #expect(single.structuredContent?.objectValue?["code"]?.stringValue == "validation")
      let batch = try await mcpRegistryCall(
        registry, tool: "batch_defer_tasks",
        arguments: [
          "task_ids": .array([.string(taskID)]),
          "until_date": .string(try await day(offset, in: registry)),
        ])
      #expect(batch.isError == true)
      #expect(batch.structuredContent?.objectValue?["code"]?.stringValue == "validation")
    }
    let malformed = try await mcpRegistryCall(
      registry, tool: "batch_defer_tasks",
      arguments: ["task_ids": .array([.string(taskID)]), "until_date": .string("tomorrow")])
    #expect(malformed.structuredContent?.objectValue?["code"]?.stringValue == "validation")

    let task = try await mcpRegistryCall(registry, tool: "get_task", arguments: ["id": .string(taskID)])
    let row = try #require(task.structuredContent?.objectValue)
    #expect(row["planned_date"] == .null)
    #expect(row["defer_count"]?.intValue == 0)
  }

  @Test("the full overview's other tasks are chosen after the day's rows are left out")
  func fullOverviewOtherTasksAreNotCrowdedOutByToday() async throws {
    let registry = try mcpInMemoryRegistry()
    let today = try await day(0, in: registry)
    // Eleven priority-1 tasks due today outrank every other task in the workspace.
    let dayTasks = (1...11).map { index in
      Value.object([
        "title": .string("Today \(index)"), "priority": .int(1), "due_date": .string(today),
      ])
    }
    let others = (1...3).map { index in
      Value.object(["title": .string("Later \(index)"), "priority": .int(3)])
    }
    let created = try await mcpRegistryCall(
      registry, tool: "batch_create_tasks", arguments: ["tasks": .array(dayTasks + others)])
    #expect(created.isError != true)

    let result = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(ids(result, "today").count == 11)
    #expect(ids(result, "tasks").count == 3)
  }

  @Test("the full overview lists a task once and leaves out its empty fields")
  func fullOverviewListsEachTaskOnce() async throws {
    let registry = try mcpInMemoryRegistry()
    let onToday = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Send the roadmap"), "priority": .int(1),
        "due_date": .string(try await day(0, in: registry)),
      ])
    let todayID = try #require(onToday.structuredContent?.objectValue?["id"]?.stringValue)
    let elsewhere = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Book the venue"), "priority": .int(1)])
    let otherID = try #require(elsewhere.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    let object = try #require(result.structuredContent?.objectValue)
    #expect(ids(result, "today") == [todayID])
    #expect(ids(result, "tasks") == [otherID])
    let row = try #require(object["today"]?.arrayValue?.first?.objectValue)
    #expect(row["due_date"]?.stringValue == (try await day(0, in: registry)))
    #expect(!row.values.contains(.null))
    #expect(row["notes"] == nil)
  }

  @Test("get_due_task_reminders returns reminders array")
  func dueTaskReminders() async throws {
    let result = try await planningCall(try mcpInMemoryRegistry(), tool: "get_due_task_reminders")
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["reminders"] != nil)
  }

  @Test("get_upcoming_task_reminders returns reminders array")
  func upcomingTaskReminders() async throws {
    let result = try await planningCall(try mcpInMemoryRegistry(), tool: "get_upcoming_task_reminders")
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["reminders"] != nil)
  }

  /// The shared slim task-summary keys a client can rely on across every task
  /// projection. `list_id` is always present and nullable.
  private static let slimSummaryKeys: Set<String> = [
    "id", "title", "status", "list_id", "priority", "due_date", "planned_date",
  ]

  private func expectSlimSummary(_ value: MCP.Value?) throws {
    let object = try #require(value?.objectValue)
    for key in Self.slimSummaryKeys { #expect(object[key] != nil, "missing \(key)") }
    // list_id is nullable across every projection: present as a string or null,
    // never absent.
    let listID = try #require(object["list_id"])
    #expect(listID == .null || listID.stringValue != nil)
  }

  @Test("dependency nodes and reminder task context share the slim task summary")
  func slimTaskSummaryIsUniform() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let blocker = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Blocker task")])
    let blockerID = try #require(blocker.structuredContent?.objectValue?["id"]?.stringValue)
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Summary shape task"), "depends_on": .array([.string(blockerID)])])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "add_task_reminder",
      arguments: ["task_id": .string(taskID), "reminder_at": .string("2026-01-01T09:00:00Z")])

    // Dependency-graph nodes are slim summaries.
    let graph = try await mcpRegistryCall(registry, tool: "get_dependency_graph")
    let node = try #require(
      graph.structuredContent?.objectValue?["nodes"]?.arrayValue?
        .first { $0.objectValue?["id"]?.stringValue == taskID })
    try expectSlimSummary(node)

    // Reminder rows embed the task context as a nested `task` summary, not as
    // `task_`-prefixed flat fields.
    let due = try await mcpRegistryCall(
      registry, tool: "get_due_task_reminders",
      arguments: ["as_of": .string("2030-01-01T00:00:00Z")])
    let reminder = try #require(due.structuredContent?.objectValue?["reminders"]?.arrayValue?.first)
    #expect(reminder.objectValue?["task_title"] == nil)
    #expect(reminder.objectValue?["task_due_date"] == nil)
    try expectSlimSummary(reminder.objectValue?["task"])
  }

  @Test("overview top_tasks are slim summaries with a nullable list_id")
  func overviewTopTasksAreSlimSummaries() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    _ = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Overview summary task")])
    let overview = try await mcpRegistryCall(registry, tool: "get_overview")
    let top = try #require(overview.structuredContent?.objectValue?["top_tasks"]?.arrayValue?.first)
    try expectSlimSummary(top)
  }

  @Test("weekly-brief items are slim summaries with defer_count/completed_at extras")
  func weeklyBriefItemsAreSlimSummaries() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Weekly brief task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "complete_task", arguments: ["id": .string(taskID)])

    let brief = try await mcpRegistryCall(registry, tool: "get_weekly_brief")
    let item = try #require(
      brief.structuredContent?.objectValue?["completed_this_week"]?.arrayValue?
        .first { $0.objectValue?["id"]?.stringValue == taskID })
    try expectSlimSummary(item)
    // Weekly-brief extras layered on the shared base.
    #expect(item.objectValue?["completed_at"] != nil)
    #expect(item.objectValue?["defer_count"]?.intValue != nil)
    // Slim, not the full task object: heavy fields are absent.
    #expect(item.objectValue?["notes"] == nil)
  }

  @Test("get_due_task_reminders pages by offset with a real next_offset on the core bridge")
  func dueRemindersPageByOffsetCoreBridge() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Reminder paging task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    for at in ["2026-01-01T09:00:00Z", "2026-01-02T09:00:00Z"] {
      _ = try await mcpRegistryCall(
        registry, tool: "add_task_reminder",
        arguments: ["task_id": .string(taskID), "reminder_at": .string(at)])
    }
    // Far-future cutoff so both reminders are due.
    let asOf = "2030-01-01T00:00:00Z"

    let first = try await mcpRegistryCall(
      registry, tool: "get_due_task_reminders",
      arguments: ["as_of": .string(asOf), "limit": .int(1)])
    let firstObject = try #require(first.structuredContent?.objectValue)
    #expect(firstObject["reminders"]?.arrayValue?.count == 1)
    #expect(firstObject["returned"]?.intValue == 1)
    #expect(firstObject["offset"]?.intValue == 0)
    #expect(firstObject["truncated"]?.boolValue == true)
    // next_offset is now real, not a null pointer.
    #expect(firstObject["next_offset"]?.intValue == 1)
    #expect(firstObject["total_matching"] == .null)

    let second = try await mcpRegistryCall(
      registry, tool: "get_due_task_reminders",
      arguments: ["as_of": .string(asOf), "limit": .int(1), "offset": .int(1)])
    let secondObject = try #require(second.structuredContent?.objectValue)
    #expect(secondObject["offset"]?.intValue == 1)
    #expect(secondObject["reminders"]?.arrayValue?.count == 1)
    let firstID = firstObject["reminders"]?.arrayValue?.first?.objectValue?["id"]?.stringValue
    let secondID = secondObject["reminders"]?.arrayValue?.first?.objectValue?["id"]?.stringValue
    #expect(firstID != secondID)
  }


  @Test("add_task_reminder then remove_task_reminder updates the task reminders")
  func addRemoveTaskReminder() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await planningCall(
      registry, tool: "create_task", arguments: ["title": .string("Reminder host task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let added = try await planningCall(
      registry,
      tool: "add_task_reminder",
      arguments: [
        "task_id": .string(taskID),
        "reminder_at": .string("2026-06-01T09:00:00Z"),
      ]
    )
    #expect(added.isError != true)
    let reminders = added.structuredContent?.objectValue?["reminders"]?.arrayValue ?? []
    let reminderObject = try #require(reminders.first?.objectValue)
    let reminderID = try #require(reminderObject["id"]?.stringValue)
    // Embedded reminders expose delivery state as `delivery_state` (matching the
    // DB column and the standalone reminder-query tools), never as `status`.
    #expect(reminderObject["delivery_state"] != nil)
    #expect(reminderObject["status"] == nil)

    let removed = try await planningCall(
      registry,
      tool: "remove_task_reminder",
      arguments: [
        "task_id": .string(taskID),
        "reminder_id": .string(reminderID),
      ]
    )
    #expect(removed.isError != true)
    #expect(removed.structuredContent?.objectValue?["reminders"]?.arrayValue?.isEmpty == true)
  }

  /// The pending reminders of a task result, as `[reminder_at, local_time, timezone]`.
  private func reminderClocks(_ result: CallTool.Result) -> [[String?]] {
    (result.structuredContent?.objectValue?["reminders"]?.arrayValue ?? []).compactMap {
      guard let row = $0.objectValue else { return nil }
      return [
        row["reminder_at"]?.stringValue, row["local_time"]?.stringValue,
        row["timezone"]?.stringValue,
      ]
    }
  }

  @Test("a reminder time without an offset is read on the user's clock and reported there")
  func reminderTimeOnTheUsersClock() async throws {
    let registry = try mcpInMemoryRegistry()
    let zone = "America/Los_Angeles"
    _ = try await mcpRegistryCall(
      registry, tool: "complete_setup", arguments: ["timezone": .string(zone)])
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Call the landlord")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // Standard time in December: 10:00 in Los Angeles is 18:00 UTC.
    let added = try await mcpRegistryCall(
      registry, tool: "add_task_reminder",
      arguments: ["task_id": .string(taskID), "reminder_at": .string("2031-12-01T10:00")])
    #expect(added.isError != true)
    #expect(reminderClocks(added) == [["2031-12-01T18:00:00.000Z", "2031-12-01T10:00", zone]])

    // A local time and an instant in one call; daylight time in June.
    let replaced = try await mcpRegistryCall(
      registry, tool: "set_task_reminders",
      arguments: [
        "task_id": .string(taskID),
        "reminders": .array([
          .string("2031-06-02T09:30"), .string("2031-06-03T16:30:00Z"),
          .string("2031-06-04T09:30:15"),
        ]),
      ])
    #expect(replaced.isError != true)
    #expect(
      reminderClocks(replaced) == [
        ["2031-06-02T16:30:00.000Z", "2031-06-02T09:30", zone],
        ["2031-06-03T16:30:00.000Z", "2031-06-03T09:30", zone],
        ["2031-06-04T16:30:15.000Z", "2031-06-04T09:30:15", zone],
      ])

    // The clocks in Los Angeles skip 02:00 to 03:00 on 2031-03-09.
    let skipped = try await mcpRegistryCall(
      registry, tool: "add_task_reminder",
      arguments: ["task_id": .string(taskID), "reminder_at": .string("2031-03-09T02:30")])
    #expect(skipped.isError == true)
    #expect(skipped.structuredContent?.objectValue?["code"]?.stringValue == "validation")
    let unchanged = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(reminderClocks(unchanged).count == 3)
  }

  @Test("reminder queries report each reminder's time on the user's clock")
  func reminderQueriesReportTheUsersClock() async throws {
    let registry = try mcpInMemoryRegistry()
    let zone = "America/Los_Angeles"
    _ = try await mcpRegistryCall(
      registry, tool: "complete_setup", arguments: ["timezone": .string(zone)])
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("File the report")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    // A reminder in the past is due now.
    _ = try await mcpRegistryCall(
      registry, tool: "add_task_reminder",
      arguments: ["task_id": .string(taskID), "reminder_at": .string("2026-01-05T08:15")])

    let due = try await mcpRegistryCall(registry, tool: "get_due_task_reminders")
    let row = try #require(
      due.structuredContent?.objectValue?["reminders"]?.arrayValue?.first?.objectValue)
    #expect(row["reminder_at"]?.stringValue == "2026-01-05T16:15:00.000Z")
    #expect(row["local_time"]?.stringValue == "2026-01-05T08:15")
    #expect(row["timezone"]?.stringValue == zone)
  }
}
