import Foundation
import LorvexCore
import LorvexDomain
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — focus area")
struct FocusToolTests {

  @Test("set_current_focus then get_current_focus round-trip")
  func setAndGetFocus() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createTaskID(registry, title: "Focus round-trip task")
    let setResult = try await mcpRegistryCall(
      registry, tool: "set_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_ids": .array([.string(taskID)]),
      ]
    )
    #expect(setResult.isError != true)

    let getResult = try await mcpRegistryCall(
      registry, tool: "get_current_focus",
      arguments: ["date": .string("2026-05-24")]
    )
    #expect(getResult.isError != true)
    let payload = getResult.structuredContent?.objectValue
    let ids = payload?["task_ids"]?.arrayValue ?? []
    #expect(ids.contains(.string(taskID)))
    let tasks = payload?["tasks"]?.arrayValue ?? []
    #expect(tasks.contains { $0.objectValue?["id"]?.stringValue == taskID })
  }

  @Test("get_current_focus with no prior set returns non-error result")
  func getCurrentFocusEmpty() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "get_current_focus",
      arguments: ["date": .string("2026-05-24")]
    )
    #expect(result.isError != true)
  }

  @Test("clear_current_focus returns non-error result")
  func clearCurrentFocus() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "clear_current_focus",
      arguments: ["date": .string("2026-05-24")]
    )
    #expect(result.isError != true)
  }

  @Test("add_to_current_focus dedupes without emitting skipped_duplicates")
  func addToFocusDedupesWithoutSkippedField() async throws {
    let registry = try mcpInMemoryRegistry()
    let firstID = try await createTaskID(registry, title: "Focus lead task")
    let secondID = try await createTaskID(registry, title: "Focus follow-up")
    _ = try await mcpRegistryCall(
      registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_ids": .array([.string(firstID)]),
      ]
    )

    let addResult = try await mcpRegistryCall(
      registry,
      tool: "add_to_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_ids": .array([.string(firstID), .string(secondID)]),
      ]
    )

    #expect(addResult.isError != true)
    let payload = addResult.structuredContent?.objectValue
    // The plan is deduped, but no `skipped_duplicates` field is reported: the
    // on-disk core never emits it, so the preview must not either.
    #expect(payload?["task_ids"]?.arrayValue == [.string(firstID), .string(secondID)])
    #expect(payload?["task_count"]?.intValue == 2)
    #expect(payload?["skipped_duplicates"] == nil)
  }

  @Test("remove_from_current_focus reports removal and remaining tasks")
  func removeFromFocusReportsRemainingTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let firstID = try await createTaskID(registry, title: "Focus lead task")
    let secondID = try await createTaskID(registry, title: "Focus follow-up")
    _ = try await mcpRegistryCall(
      registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_ids": .array([.string(firstID), .string(secondID)]),
      ]
    )

    let removeResult = try await mcpRegistryCall(
      registry,
      tool: "remove_from_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_id": .string(firstID),
      ]
    )

    #expect(removeResult.isError != true)
    let payload = removeResult.structuredContent?.objectValue
    #expect(payload?["removed"]?.boolValue == true)
    #expect(payload?["task_ids"]?.arrayValue == [.string(secondID)])
    #expect(payload?["task_count"]?.intValue == 1)
    #expect(payload?["plan_cleared"]?.boolValue == false)
  }

  @Test("set_current_focus rejects missing tasks")
  func setFocusRejectsMissingTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string("2026-05-24"),
        "task_ids": .array([.string("missing-task-id")]),
      ]
    )

    #expect(result.isError == true)
    #expect(
      mcpTextContent(result)
        == SecurityFencing.fence(
          "Current focus task_id 'missing-task-id' does not reference an active task."))
  }

  @Test("set_current_focus with no timezone resolves to the preference timezone, not UTC")
  func setFocusResolvesPreferenceTimezone() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let seed = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    _ = try await seed.setPreference(key: "timezone", value: "America/Los_Angeles")
    let task = try await seed.createTask(title: "Anchored focus task", notes: "")

    let setResult = try await mcpRegistryCall(
      fixture.registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string("2026-06-24"),
        "task_ids": .array([.string(task.id)]),
      ]
    )
    #expect(setResult.isError != true)
    let setTimezone = try #require(
      setResult.structuredContent?.objectValue?["timezone"]?.stringValue)
    #expect(setTimezone == "America/Los_Angeles")

    // add_to_current_focus resolves the same anchored timezone when omitted.
    let other = try await seed.createTask(title: "Second anchored task", notes: "")
    let addResult = try await mcpRegistryCall(
      fixture.registry,
      tool: "add_to_current_focus",
      arguments: [
        "date": .string("2026-06-24"),
        "task_ids": .array([.string(other.id)]),
      ]
    )
    #expect(addResult.isError != true)
    let addTimezone = try #require(
      addResult.structuredContent?.objectValue?["timezone"]?.stringValue)
    #expect(addTimezone == "America/Los_Angeles")

    // An explicit timezone argument is still honoured verbatim.
    let explicit = try await mcpRegistryCall(
      fixture.registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string("2026-06-25"),
        "task_ids": .array([.string(task.id)]),
        "timezone": .string("Europe/Berlin"),
      ]
    )
    #expect(explicit.isError != true)
    #expect(
      explicit.structuredContent?.objectValue?["timezone"]?.stringValue == "Europe/Berlin")
  }

  @Test("propose then save focus schedule round-trips the blocks")
  func focusScheduleRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createTaskID(registry, title: "Scheduled focus task")
    let date = "2026-05-24"
    _ = try await mcpRegistryCall(
      registry,
      tool: "set_current_focus",
      arguments: [
        "date": .string(date),
        "task_ids": .array([.string(taskID)]),
      ]
    )

    let proposed = try await mcpRegistryCall(
      registry,
      tool: "propose_daily_schedule",
      arguments: ["date": .string(date)]
    )
    #expect(proposed.isError != true)
    let blocks = proposed.structuredContent?.objectValue?["blocks"]?.arrayValue ?? []
    #expect(!blocks.isEmpty)

    let saved = try await mcpRegistryCall(
      registry,
      tool: "save_focus_schedule",
      arguments: [
        "date": .string(date),
        "blocks": .array(blocks),
        "rationale": .string("Preview MCP schedule"),
      ]
    )
    #expect(saved.isError != true)

    let loaded = try await mcpRegistryCall(
      registry,
      tool: "get_saved_focus_schedule",
      arguments: ["date": .string(date)]
    )
    #expect(loaded.isError != true)
    #expect(loaded.structuredContent?.objectValue?["blocks"]?.arrayValue?.count == blocks.count)
  }

  @Test("save focus schedule preserves explicit freeform provenance")
  func saveFreeformFocusSchedulePreservesSource() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "save_focus_schedule",
      arguments: [
        "date": .string("2026-05-25"),
        "blocks": .array([
          .object([
            "block_type": .string("event"),
            "event_source": .string("freeform"),
            "start_time": .string("12:00"),
            "end_time": .string("12:30"),
            "title": .string("Lunch"),
          ])
        ]),
      ])

    #expect(result.isError != true)
    let block = result.structuredContent?.objectValue?["blocks"]?.arrayValue?.first?.objectValue
    #expect(block?["event_source"]?.stringValue == "freeform")
    #expect(block?["event_id"] == .null)
  }

  @Test("save focus schedule rejects event blocks without provenance")
  func saveEventFocusScheduleRequiresSource() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "save_focus_schedule",
      arguments: [
        "date": .string("2026-05-25"),
        "blocks": .array([
          .object([
            "block_type": .string("event"),
            "start_time": .string("12:00"),
            "end_time": .string("12:30"),
            "title": .string("Lunch"),
          ])
        ]),
      ])

    #expect(result.isError == true)
  }

  @Test("saved focus schedule MCP read honors calendar AI access")
  func savedFocusScheduleReadUsesAIPrivacyProjection() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let service = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let date = "2026-06-24"
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    _ = try await service.saveFocusSchedule(
      date: date,
      blocks: [
        FocusScheduleBlock(
          blockType: "event", startTime: "09:00", endTime: "10:00",
          eventSource: .provider, title: "Private appointment"),
        FocusScheduleBlock(
          blockType: "event", startTime: "10:00", endTime: "10:30",
          eventSource: .freeform, title: "Authored hold"),
      ],
      rationale: nil)

    let fullResult = try await mcpRegistryCall(
      fixture.registry, tool: "get_saved_focus_schedule",
      arguments: ["date": .string(date)])
    let fullBlocks = fullResult.structuredContent?.objectValue?["blocks"]?.arrayValue ?? []
    let fencedPrivateTitle: String = SecurityFencing.fence("Private appointment")
    #expect(
      fullBlocks.contains {
        $0.objectValue?["title"]?.stringValue == fencedPrivateTitle
      })

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.off.asString)
    let human = try await service.loadFocusSchedule(date: date)
    #expect(human?.blocks.count == 2)
    #expect(human?.blocks.first?.title == "Event")

    let offResult = try await mcpRegistryCall(
      fixture.registry, tool: "get_saved_focus_schedule",
      arguments: ["date": .string(date)])
    let offBlocks = offResult.structuredContent?.objectValue?["blocks"]?.arrayValue ?? []
    #expect(offBlocks.count == 1)
    #expect(offBlocks.first?.objectValue?["event_source"]?.stringValue == "freeform")
    let fencedAuthoredTitle: String = SecurityFencing.fence("Authored hold")
    #expect(
      offBlocks.first?.objectValue?["title"]?.stringValue
        == fencedAuthoredTitle)
  }
}

private func createTaskID(_ registry: ToolRegistry, title: String) async throws -> String {
  let createResult = try await mcpRegistryCall(
    registry,
    tool: "create_task",
    arguments: ["title": .string(title)]
  )
  return try #require(createResult.structuredContent?.objectValue?["id"]?.stringValue)
}
