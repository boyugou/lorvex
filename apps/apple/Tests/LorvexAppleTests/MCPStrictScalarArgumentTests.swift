import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// Write-path scalar arguments decode strictly: a PRESENT argument of the wrong
/// type rejects with a typed validation error naming the parameter, instead of
/// silently applying a default/other value than the caller sent. Absent
/// arguments keep their documented defaults.
struct MCPStrictScalarArgumentTests {
  private func expectValidationError(
    _ result: CallTool.Result, naming field: String,
    _ comment: Comment? = nil
  ) throws {
    #expect(result.isError == true, comment)
    let payload = try #require(result.structuredContent?.objectValue)
    #expect(payload["code"]?.stringValue == "validation", comment)
    let message = try #require(payload["message"]?.stringValue)
    #expect(message.contains(field), comment)
  }

  @Test("create_habit rejects a fractional or string target_count instead of storing 1")
  func createHabitRejectsWrongTypedTargetCount() async throws {
    let registry = try mcpInMemoryRegistry()
    for wrongTyped: Value in [.double(5.5), .string("7")] {
      let result = try await mcpRegistryCall(
        registry, tool: "create_habit",
        arguments: ["name": .string("Read"), "target_count": wrongTyped])
      try expectValidationError(result, naming: "target_count")
    }
    // Correctly-typed and absent both still work.
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Read"), "target_count": .int(7)])
    #expect(created.isError != true)
    #expect(created.structuredContent?.objectValue?["target_count"]?.intValue == 7)
  }

  @Test("complete_habit rejects an integer date instead of completing today")
  func completeHabitRejectsWrongTypedDate() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Stretch")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let wrongTyped = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(id), "date": .int(20_260_718)])
    try expectValidationError(wrongTyped, naming: "date")

    // The absent-date default (today) is unchanged.
    let defaulted = try await mcpRegistryCall(
      registry, tool: "complete_habit", arguments: ["id": .string(id)])
    #expect(defaulted.isError != true)
  }

  @Test("update_habit rejects a numeric frequency_type instead of ignoring it")
  func updateHabitRejectsWrongTypedFrequencyType() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Journal")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "update_habit",
      arguments: ["id": .string(id), "frequency_type": .int(3)])
    try expectValidationError(result, naming: "frequency_type")
  }

  @Test("batch_cancel_tasks rejects a string cancel_series instead of treating it as false")
  func batchCancelRejectsWrongTypedCancelSeries() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Ship it")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "batch_cancel_tasks",
      arguments: ["task_ids": .array([.string(id)]), "cancel_series": .string("true")])
    try expectValidationError(result, naming: "cancel_series")
  }

  @Test("update_task rejects wrong-typed notes instead of clearing them")
  func updateTaskRejectsWrongTypedNotes() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep notes"), "notes": .string("important context")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "update_task", arguments: ["id": .string(id), "notes": .int(5)])
    try expectValidationError(result, naming: "notes")

    let read = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string(id)])
    let notes = try #require(read.structuredContent?.objectValue?["notes"]?.stringValue)
    #expect(notes.contains("important context"), "wrong-typed notes must not clear the field")
  }

  @Test("a wrong-typed idempotency_key rejects instead of running unkeyed")
  func idempotencyKeyRejectsWrongType() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keyed"), "idempotency_key": .int(42)])
    try expectValidationError(result, naming: "idempotency_key")
  }

  @Test("an over-long idempotency_key rejects with a typed length error")
  func idempotencyKeyRejectsOverLongValue() async throws {
    let registry = try mcpInMemoryRegistry()
    let longKey = String(repeating: "k", count: ToolRegistry.maxIdempotencyKeyBytes + 1)
    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keyed"), "idempotency_key": .string(longKey)])
    try expectValidationError(result, naming: "idempotency_key")

    // A maximal-length key still works.
    let maxKey = String(repeating: "k", count: ToolRegistry.maxIdempotencyKeyBytes)
    let accepted = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keyed"), "idempotency_key": .string(maxKey)])
    #expect(accepted.isError != true)
  }

  @Test("create_calendar_event rejects a string all_day instead of treating it as false")
  func calendarCreateRejectsWrongTypedAllDay() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Standup"), "start_date": .string("2026-07-20"),
        "all_day": .string("yes"),
      ])
    try expectValidationError(result, naming: "all_day")
  }

  @Test("create_calendar_event rejects a wrong-typed attendee email instead of dropping it")
  func calendarCreateRejectsWrongTypedAttendeeEmail() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Sync"), "start_date": .string("2026-07-20"),
        "attendees": .array([.object(["email": .int(42), "name": .string("A")])]),
      ])
    try expectValidationError(result, naming: "attendees[0].email")
  }

  @Test("batch_update_tasks rejects wrong-typed notes instead of clearing them")
  func batchUpdateRejectsWrongTypedNotes() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep notes"), "notes": .string("original")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "batch_update_tasks",
      arguments: ["updates": .array([.object(["id": .string(id), "notes": .int(7)])])])
    try expectValidationError(result, naming: "notes")

    let read = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string(id)])
    let notes = read.structuredContent?.objectValue?["notes"]?.stringValue ?? ""
    #expect(notes.contains("original"), "the wrong-typed update must not clear stored notes")
  }

  @Test("save_focus_schedule rejects a wrong-typed block field instead of defaulting it")
  func saveFocusScheduleRejectsWrongTypedBlockField() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "save_focus_schedule",
      arguments: [
        "date": .string("2026-07-20"),
        "blocks": .array([
          .object([
            "block_type": .int(1), "start_time": .string("09:00"),
            "end_time": .string("10:00"), "title": .string("Deep work"),
          ])
        ]),
      ])
    try expectValidationError(result, naming: "blocks[0].block_type")
  }

  @Test("set_current_focus rejects a wrong-typed optional briefing")
  func setCurrentFocusRejectsWrongTypedBriefing() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Focus target")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "set_current_focus",
      arguments: [
        "date": .string("2026-07-20"), "task_ids": .array([.string(id)]),
        "briefing": .int(42),
      ])
    try expectValidationError(result, naming: "briefing")
  }

  @Test("upsert_habit_reminder_policy rejects a wrong-typed optional id")
  func habitReminderPolicyRejectsWrongTypedID() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Hydrate")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "upsert_habit_reminder_policy",
      arguments: [
        "habit_id": .string(id), "reminder_time": .string("09:00"), "id": .int(7),
      ])
    try expectValidationError(result, naming: "id")
  }
}
