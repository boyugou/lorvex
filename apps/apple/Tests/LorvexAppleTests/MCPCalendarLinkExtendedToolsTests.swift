import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with MCPToolRegistryTests)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xtext(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let t, _, _) = $0 { return t }
    return nil
  }.joined()
}

// MARK: - Calendar Links

private func makeTask(_ registry: ToolRegistry, title: String) async throws -> String {
  let created = try await xcall(
    registry, tool: "create_task", arguments: ["title": .string(title)])
  guard let id = created.structuredContent?.objectValue?["id"]?.stringValue else {
    throw CalendarLinkFixtureError()
  }
  return id
}

private struct CalendarLinkFixtureError: Error {}

/// Provider links reference the EventKit provider mirror (scope enabled +
/// refreshed), not Lorvex-owned canonical events. Builds a registry whose
/// backing core has one mirrored EventKit event, keyed `ek-swift-review`,
/// addressable on the timeline as `eventkit:device:ek-swift-review`.
private func makeRegistryWithMirroredEvent() async throws -> ToolRegistry {
  let (registry, service) = try mcpInMemoryRegistryWithService()
  _ = try await service.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.fullDetails.asString)
  _ = try service.ingestEventKitEvents(
    EventKitIngest.providerRows(
      from: [
        EventKitFetchedEvent(
          key: "ek-swift-review", title: "Swift migration review", notes: nil,
          startDate: "2026-06-04", startTime: "15:00", endDate: "2026-06-04",
          endTime: "15:45", allDay: false, location: nil, timezone: nil)
      ],
      scope: "device", accessMode: .fullDetails),
    builtAtMode: .fullDetails, windowStart: "2026-06-04", windowEnd: "2026-06-04")
  return registry
}

private let mirroredEventKey = "ek-swift-review"
private let mirroredEventTimelineID = "eventkit:device:ek-swift-review"

@Suite("MCP Extended — calendar links round-trip")
struct CalendarLinkExtendedTests {
  @Test("link_task_to_provider_event then get_linked_events_for_task reflects the link")
  func linkAndGetLinkedEvents() async throws {
    let registry = try await makeRegistryWithMirroredEvent()
    let taskID = try await makeTask(registry, title: "Linked task")
    let linkResult = try await xcall(
      registry, tool: "link_task_to_provider_event",
      arguments: [
        "task_id": .string(taskID),
        "provider_event_id": .string(mirroredEventKey),
        "provider_source": .string("eventkit"),
      ]
    )
    #expect(linkResult.isError != true)
    let linkedTaskID = linkResult.structuredContent?.objectValue?["task_id"]?.stringValue
    #expect(linkedTaskID == taskID)

    let getResult = try await xcall(
      registry, tool: "get_linked_events_for_task",
      arguments: ["task_id": .string(taskID)]
    )
    #expect(getResult.isError != true)
    let returnedTaskID = getResult.structuredContent?.objectValue?["task_id"]?.stringValue
    #expect(returnedTaskID == taskID)
    // Linked events surface under their provider timeline id.
    let events = getResult.structuredContent?.objectValue?["events"]?.arrayValue ?? []
    #expect(events.contains { $0.objectValue?["id"]?.stringValue == mirroredEventTimelineID })
  }

  @Test("link_task_to_provider_event rejects a provider event absent from the mirror")
  func linkRejectsUnmirroredProviderEvent() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Unlinkable task")
    let result = try await xcall(
      registry, tool: "link_task_to_provider_event",
      arguments: [
        "task_id": .string(taskID),
        "provider_event_id": .string("ek-not-mirrored"),
        "provider_source": .string("eventkit"),
      ]
    )
    #expect(result.isError == true)
    #expect(xtext(result).contains("not available"))
  }

  @Test("get_linked_events_for_task with missing task_id returns structured error")
  func linkedEventsForTaskMissingID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(registry, tool: "get_linked_events_for_task", arguments: [:])
    #expect(result.isError == true)
  }

  @Test("get_linked_tasks_for_event returns non-error result with event_id key")
  func linkedTasksForEvent() async throws {
    let registry = try await makeRegistryWithMirroredEvent()
    let taskID = try await makeTask(registry, title: "Task behind the event")
    _ = try await xcall(
      registry,
      tool: "link_task_to_provider_event",
      arguments: [
        "task_id": .string(taskID),
        "provider_event_id": .string(mirroredEventKey),
        "provider_source": .string("eventkit"),
      ]
    )

    let result = try await xcall(
      registry, tool: "get_linked_tasks_for_event",
      arguments: ["event_id": .string(mirroredEventTimelineID)]
    )
    #expect(result.isError != true)
    let eventID = result.structuredContent?.objectValue?["event_id"]?.stringValue
    #expect(eventID == mirroredEventTimelineID)
    let tasks = result.structuredContent?.objectValue?["tasks"]?.arrayValue ?? []
    #expect(tasks.contains { $0.objectValue?["id"]?.stringValue == taskID })
  }

  @Test("unlink_task_from_provider_event removes the link")
  func unlinkProviderEvent() async throws {
    let registry = try await makeRegistryWithMirroredEvent()
    let taskID = try await makeTask(registry, title: "Task to unlink")
    _ = try await xcall(
      registry,
      tool: "link_task_to_provider_event",
      arguments: [
        "task_id": .string(taskID),
        "provider_event_id": .string(mirroredEventKey),
        "provider_source": .string("eventkit"),
      ]
    )

    let result = try await xcall(
      registry,
      tool: "unlink_task_from_provider_event",
      arguments: [
        "task_id": .string(taskID),
        "provider_event_id": .string(mirroredEventKey),
      ]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["deleted"]?.boolValue == true)

    let tasks = try await xcall(
      registry,
      tool: "get_linked_tasks_for_event",
      arguments: ["event_id": .string(mirroredEventTimelineID)]
    )
    #expect(tasks.structuredContent?.objectValue?["count"]?.intValue == 0)
  }
}
