import Foundation
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

    let groups = object["by_date"]?.objectValue ?? [:]
    let firstTask = groups.values
      .compactMap { $0.arrayValue?.first?.objectValue }
      .first
    let task = try #require(firstTask)
    #expect(task["id"]?.stringValue == taskID)
    #expect(task["priority"]?.intValue == 1)
    #expect(task["priority_label"]?.stringValue == "P1")
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
    // by_date groups the very same rows; the flat array is the ungrouped page.
    let grouped = try #require(object["by_date"]?.objectValue)
    let groupedIDs = grouped.values.flatMap { $0.arrayValue ?? [] }
      .compactMap { $0.objectValue?["id"]?.stringValue }
    #expect(groupedIDs.contains(taskID))
    #expect(groupedIDs.count == flat.count)
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
}
