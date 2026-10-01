import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — day planning")
struct DayPlanningToolTests {

  @Test("propose_daily_schedule suggests without saving; save_daily_schedule stores the times")
  func proposeSaveReadRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let date = "2026-05-24"
    let taskID = try await createPlannedTaskID(registry, title: "Scheduled task", date: date)

    let proposed = try await mcpRegistryCall(
      registry, tool: "propose_daily_schedule", arguments: ["date": .string(date)])
    #expect(proposed.isError != true)
    let placements = proposed.structuredContent?.objectValue?["placements"]?.arrayValue ?? []
    let placement = try #require(
      placements.first { $0.objectValue?["task"]?.objectValue?["id"]?.stringValue == taskID }?
        .objectValue)
    let start = try #require(placement["start_time"]?.stringValue)
    let end = try #require(placement["end_time"]?.stringValue)
    #expect(try await timedTaskIDs(registry, date: date).isEmpty)

    let saved = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: [
        "date": .string(date),
        "times": .array([time(taskID, start, end)]),
      ])
    #expect(saved.isError != true)
    let timed = saved.structuredContent?.objectValue?["timed_tasks"]?.arrayValue ?? []
    #expect(timed.compactMap { $0.objectValue?["id"]?.stringValue } == [taskID])

    let loaded = try await mcpRegistryCall(
      registry, tool: "get_daily_schedule", arguments: ["date": .string(date)])
    #expect(loaded.isError != true)
    let task = try #require(
      loaded.structuredContent?.objectValue?["timed_tasks"]?.arrayValue?.first?.objectValue)
    #expect(task["id"]?.stringValue == taskID)
    #expect(task["planned_start_time"]?.stringValue == start)
    #expect(task["planned_end_time"]?.stringValue == end)
  }

  @Test("an empty times array clears the day's times and keeps the tasks on the day")
  func emptySaveClearsTimes() async throws {
    let registry = try mcpInMemoryRegistry()
    let date = "2026-05-24"
    let taskID = try await createPlannedTaskID(registry, title: "Timed then cleared", date: date)
    _ = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": .array([time(taskID, "10:00", "10:45")])])

    let cleared = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": .array([])])

    #expect(cleared.isError != true)
    let clearedTasks = cleared.structuredContent?.objectValue?["cleared_tasks"]?.arrayValue ?? []
    let clearedTask = try #require(clearedTasks.first?.objectValue)
    #expect(clearedTasks.count == 1)
    #expect(clearedTask["id"]?.stringValue == taskID)
    #expect(clearedTask["planned_date"]?.stringValue == date)
    #expect(clearedTask["planned_start_time"] == .null)
    #expect(try await timedTaskIDs(registry, date: date).isEmpty)
  }

  @Test("save_daily_schedule rejects a time that ends before it starts")
  func saveRejectsInvertedTime() async throws {
    let registry = try mcpInMemoryRegistry()
    let date = "2026-05-24"
    let taskID = try await createPlannedTaskID(registry, title: "Backwards time", date: date)

    let result = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": .array([time(taskID, "11:00", "10:00")])])

    #expect(result.isError == true)
    #expect(try await timedTaskIDs(registry, date: date).isEmpty)
  }

  @Test("get_daily_schedule reads today when no date is given")
  func getDefaultsToToday() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let today = try await service.getSessionContext().date

    let result = try await mcpRegistryCall(registry, tool: "get_daily_schedule")

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["date"]?.stringValue == today)
    #expect(result.structuredContent?.objectValue?["timed_tasks"]?.arrayValue?.isEmpty == true)
  }

  @Test("propose_daily_schedule describes device events only as far as calendar access allows")
  func proposalHonorsCalendarAccess() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let date = "2026-06-24"
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    try ingestPrivateAppointment(service, date: date, accessMode: .fullDetails)

    let full = try await proposalEvents(registry, date: date)
    let fullEvent = try #require(full.first)
    let fencedTitle: String = SecurityFencing.fence("Private appointment")
    #expect(full.count == 1)
    #expect(fullEvent["title"]?.stringValue == fencedTitle)
    #expect(fullEvent["source"]?.stringValue == "provider")
    #expect(fullEvent["event_id"] == .null)
    #expect(fullEvent["start_time"]?.stringValue == "10:00")

    // Lowering the access purges the full-detail mirror; the next EventKit
    // refresh ingests the day again at the lower tier.
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)
    #expect(try await proposalEvents(registry, date: date).isEmpty)
    try ingestPrivateAppointment(service, date: date, accessMode: .busyOnly)
    let busy = try await proposalEvents(registry, date: date)
    #expect(busy.count == 1)
    #expect(busy.first?["title"] == .null)
    #expect(busy.first?["end_time"]?.stringValue == "11:00")

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.off.asString)
    #expect(try await proposalEvents(registry, date: date).isEmpty)
  }

  @Test("set_daily_briefing writes, reports, and clears the day's briefing")
  func briefingRoundTrip() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let today = try await service.getSessionContext().date

    let set = try await mcpRegistryCall(
      registry, tool: "set_daily_briefing",
      arguments: ["briefing": .string("Ship the release notes before the review.")])
    #expect(set.isError != true)
    let setPayload = set.structuredContent?.objectValue
    let fencedBriefing: String = SecurityFencing.fence("Ship the release notes before the review.")
    #expect(setPayload?["date"]?.stringValue == today)
    #expect(setPayload?["briefing"]?.stringValue == fencedBriefing)
    #expect(setPayload?["previous"]?.objectValue?["briefing"] == .null)
    #expect(setPayload?["changed"]?.boolValue == true)
    #expect(try await service.loadToday().briefing == "Ship the release notes before the review.")

    let again = try await mcpRegistryCall(
      registry, tool: "set_daily_briefing",
      arguments: ["briefing": .string("Ship the release notes before the review.")])
    #expect(again.structuredContent?.objectValue?["changed"]?.boolValue == false)

    let cleared = try await mcpRegistryCall(
      registry, tool: "set_daily_briefing",
      arguments: ["date": .string(today), "briefing": .string("")])
    #expect(cleared.isError != true)
    #expect(cleared.structuredContent?.objectValue?["briefing"] == .null)
    #expect(cleared.structuredContent?.objectValue?["changed"]?.boolValue == true)
    #expect(try await service.loadToday().briefing == nil)
  }
}

/// Creates a task through `create_task`, planned for `date`, and returns its id.
private func createPlannedTaskID(
  _ registry: ToolRegistry, title: String, date: String
) async throws -> String {
  let createResult = try await mcpRegistryCall(
    registry,
    tool: "create_task",
    arguments: ["title": .string(title), "planned_date": .string(date)]
  )
  return try #require(createResult.structuredContent?.objectValue?["id"]?.stringValue)
}

private func time(_ taskID: String, _ start: String, _ end: String) -> Value {
  .object([
    "task_id": .string(taskID), "start_time": .string(start), "end_time": .string(end),
  ])
}

/// The ids `get_daily_schedule` lists as timed on `date`, in start order.
private func timedTaskIDs(_ registry: ToolRegistry, date: String) async throws -> [String] {
  let result = try await mcpRegistryCall(
    registry, tool: "get_daily_schedule", arguments: ["date": .string(date)])
  let tasks = result.structuredContent?.objectValue?["timed_tasks"]?.arrayValue ?? []
  return tasks.compactMap { $0.objectValue?["id"]?.stringValue }
}

/// Mirrors one 10:00–11:00 device event titled "Private appointment" on `date`,
/// redacted for `accessMode` the way the EventKit refresh stores it.
private func ingestPrivateAppointment(
  _ service: SwiftLorvexCoreService, date: String, accessMode: CalendarAiAccessMode
) throws {
  _ = try service.ingestEventKitEvents(
    EventKitIngest.providerRows(
      from: [
        EventKitFetchedEvent(
          key: "ek-private", title: "Private appointment", notes: nil,
          startDate: date, startTime: "10:00", endDate: date,
          endTime: "11:00", allDay: false, location: nil, timezone: nil)
      ],
      scope: "device", accessMode: accessMode),
    builtAtMode: accessMode, windowStart: date, windowEnd: date)
}

/// The events a suggestion for `date` worked around, as the tool returns them.
private func proposalEvents(
  _ registry: ToolRegistry, date: String
) async throws -> [[String: Value]] {
  let result = try await mcpRegistryCall(
    registry, tool: "propose_daily_schedule", arguments: ["date": .string(date)])
  #expect(result.isError != true)
  let events = result.structuredContent?.objectValue?["events"]?.arrayValue ?? []
  return events.compactMap(\.objectValue)
}
