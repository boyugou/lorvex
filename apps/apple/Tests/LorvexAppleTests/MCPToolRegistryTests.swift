import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Tool Listing Contract

@Suite("MCP Tool Registry — tool listing")
struct ToolListingTests {

  @Test("typed definitions are the complete listing and dispatch authority")
  func definitionsAreCompleteAndInternallyConsistent() async {
    let definitions = ToolDefinitionRegistry.all
    let definitionNames = definitions.map { $0.tool.name }
    let listedNames = ToolRegistry.listTools().map(\.name)

    #expect(definitions.count == 118)
    #expect(definitionNames == listedNames)
    #expect(Set(definitionNames).count == definitions.count)
    #expect(ToolDefinitionRegistry.byName.count == definitions.count)
    #expect(definitions.map(\.listingOrder) == Array(0..<definitions.count))

    for definition in definitions {
      let properties = definition.tool.inputSchema.objectValue?["properties"]?.objectValue
      let advertisesIdempotency = properties?[IdempotencyKeySchema.propertyName] != nil
      #expect(definition.isWrite == definition.participatesInIdempotency)
      #expect(advertisesIdempotency == definition.participatesInIdempotency)
      #expect(definition.responseFencing.fenceTextContent)
      #expect(
        definition.responseFencing.stringFields == SecurityFencing.userContentKeys)
      #expect(
        definition.responseFencing.stringArrayFields
          == SecurityFencing.userContentArrayKeys)
    }
  }

  @Test("listTools returns at least 50 tools")
  func toolCountMeetsMinimum() async {
    let tools = ToolRegistry.listTools()
    #expect(tools.count >= 50)
  }

  @Test("every tool has a non-empty name")
  func everyToolHasName() async {
    let tools = ToolRegistry.listTools()
    for tool in tools {
      #expect(!tool.name.isEmpty, "Tool has empty name: \(tool)")
    }
  }

  @Test("every tool has a non-empty description")
  func everyToolHasDescription() async {
    let tools = ToolRegistry.listTools()
    for tool in tools {
      let desc = tool.description ?? ""
      #expect(!desc.isEmpty, "Tool '\(tool.name)' has empty description")
    }
  }

  @Test("every tool has a non-nil inputSchema")
  func everyToolHasInputSchema() async {
    let tools = ToolRegistry.listTools()
    for tool in tools {
      // inputSchema is Value (non-optional); confirm it's not .null
      if case .null = tool.inputSchema {
        Issue.record("Tool '\(tool.name)' has null inputSchema")
      }
    }
  }

  @Test("tool names are unique")
  func toolNamesAreUnique() async {
    let tools = ToolRegistry.listTools()
    let names = tools.map(\.name)
    let uniqueNames = Set(names)
    #expect(names.count == uniqueNames.count, "Duplicate tool names detected")
  }

  @Test("every listed tool name is dispatched without 'Unknown tool' error")
  func noOrphanTools() async throws {
    let registry = try mcpInMemoryRegistry()
    let tools = ToolRegistry.listTools()
    for tool in tools {
      let result = try await mcpRegistryCall(registry, tool: tool.name)
      let text = mcpTextContent(result)
      #expect(
        !(text.hasPrefix("Unknown tool:")),
        "Listed tool '\(tool.name)' is not dispatched"
      )
    }
  }
}

// MARK: - Task Area Happy Path

@Suite("MCP Tool Registry — task area")
struct TaskToolTests {

  @Test("create_task then get_task round-trip")
  func createAndGetTask() async throws {
    let registry = try mcpInMemoryRegistry()
    let createResult = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Test task for registry round-trip")]
    )
    #expect(createResult.isError != true)

    // Extract the new task id from structured content
    guard
      let obj = createResult.structuredContent?.objectValue,
      let idValue = obj["id"],
      let taskID = idValue.stringValue
    else {
      Issue.record("create_task did not return structured content with an id")
      return
    }

    let getResult = try await mcpRegistryCall(registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(getResult.isError != true)
    let returnedID = getResult.structuredContent?.objectValue?["id"]?.stringValue
    #expect(returnedID == taskID)
  }

  @Test("create_task with missing title returns structured error")
  func createTaskMissingTitle() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "create_task", arguments: [:])
    #expect(mcpTextContent(result).contains("title") || mcpTextContent(result).contains("required"))
    expectMCPStructuredError(
      result,
      code: "validation",
      tool: "create_task",
      message: "A non-empty title is required."
    )
  }

  @Test("get_task with missing id returns structured error")
  func getTaskMissingID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_task", arguments: [:])
    expectMCPStructuredError(
      result,
      code: "validation",
      tool: "get_task",
      message: "A task id is required."
    )
  }

  @Test("get_task with unknown id returns structured not-found error")
  func getTaskUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "get_task",
      arguments: ["id": .string("missing-task-id")]
    )
    expectMCPStructuredError(
      result,
      code: "not_found",
      tool: "get_task",
      message: "The task could not be found."
    )
  }

  @Test("update_task with missing id returns structured error")
  func updateTaskMissingID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "update_task",
      arguments: ["title": .string("Updated title")]
    )
    expectMCPStructuredError(
      result,
      code: "validation",
      tool: "update_task",
      message: "A task id is required."
    )
  }

  @Test("update_task with omitted title keeps the existing title")
  func updateTaskOmittedTitleKeepsExisting() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Keep this title")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let result = try await mcpRegistryCall(
      registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "priority": .int(2)]
    )
    #expect(result.isError != true)
    let fencedTitle: String = SecurityFencing.fence("Keep this title")
    #expect(result.structuredContent?.objectValue?["title"]?.stringValue == fencedTitle)
    #expect(result.structuredContent?.objectValue?["priority"]?.intValue == 2)
  }

  @Test("update_task with an explicitly empty title returns structured error")
  func updateTaskEmptyTitle() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Blank-guard target")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let result = try await mcpRegistryCall(
      registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "title": .string("   ")]
    )
    expectMCPStructuredError(
      result,
      code: "validation",
      tool: "update_task",
      message: "A non-empty title is required."
    )
  }

  @Test("update_task with unknown id returns structured not-found error")
  func updateTaskUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "update_task",
      arguments: [
        "id": .string("missing-update-task-id"),
        "title": .string("Updated title"),
      ]
    )
    expectMCPStructuredError(
      result,
      code: "not_found",
      tool: "update_task",
      message: "The task could not be found."
    )
  }

  @Test("list_tasks returns non-error result")
  func listTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "list_tasks")
    #expect(result.isError != true)
  }

  @Test("set_task_someday is registered and transitions a task to someday")
  func setTaskSomedayTransitions() async throws {
    let registry = try mcpInMemoryRegistry()
    let listed = ToolRegistry.listTools().map(\.name)
    #expect(listed.contains("set_task_someday"))

    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Park me as someday")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await mcpRegistryCall(
      registry, tool: "set_task_someday", arguments: ["id": .string(taskID)])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["status"]?.stringValue == "someday")
  }

  @Test("set_task_someday with missing id returns structured error")
  func setTaskSomedayMissingID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "set_task_someday", arguments: [:])
    #expect(result.isError == true)
    #expect(mcpTextContent(result).contains("id"))
  }
}

// MARK: - Entity not-found emits the not_found wire code

/// The list / habit / calendar entity lookups throw the typed
/// `LorvexCoreError.notFound`, which the dispatch catch-all maps to the
/// `not_found` machine code — joining `taskNotFound` so every lookup miss shares
/// one failure class. The emitted message stays the fenced "<Noun> '<id>' not
/// found." sentence, id-bearing for diagnostics while the machine code, not the
/// prose, marks the failure class.
@Suite("MCP Tool Registry — entity not-found envelope")
struct EntityNotFoundEnvelopeTests {
  private let bad = "0192f3a1-7c4b-7def-9abc-1234567890ab"

  @Test("get_list with an unknown id emits a not_found + raw message envelope")
  func getListUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_list", arguments: ["id": .string(bad)])
    expectMCPStructuredError(
      result, code: "not_found", tool: "get_list", message: "List '\(bad)' not found.")
  }

  @Test("complete_habit with an unknown id emits a not_found + raw message envelope")
  func completeHabitUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "complete_habit", arguments: ["id": .string(bad)])
    expectMCPStructuredError(
      result, code: "not_found", tool: "complete_habit", message: "Habit '\(bad)' not found.")
  }

  @Test("update_calendar_event with an unknown event_id emits a not_found + raw message envelope")
  func updateCalendarEventUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "update_calendar_event",
      arguments: ["event_id": .string(bad), "title": .string("x")])
    expectMCPStructuredError(
      result, code: "not_found", tool: "update_calendar_event",
      message: "Calendar event '\(bad)' not found.")
  }
}

// MARK: - Core-service validation emits the validation wire code

/// A core-service caller-input validation guard throws
/// `LorvexCoreError.validation`, which the dispatch catch-all maps to the
/// `validation` machine code (distinct from the `tool_error` fallback reserved
/// for conflict / invariant / serialization failures). These guards surface via
/// a tool when a handler forwards a value it does not itself pre-check; the
/// message stays the guard's exact sentence while the machine code marks it as a
/// caller-input rejection.
@Suite("MCP Tool Registry — core validation emits validation")
struct CoreValidationEnvelopeTests {
  @Test("create_habit with a non-positive milestone_target emits a validation envelope")
  func createHabitNonPositiveMilestone() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Meditate"), "milestone_target": .int(-1)])
    expectMCPStructuredError(
      result, code: "validation", tool: "create_habit",
      message: "milestone_target must be a positive number.")
  }

  @Test("create_calendar_event with an unsupported event_type emits a validation envelope")
  func createCalendarEventUnsupportedType() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Sync"), "start_date": .string("2026-07-12"),
        "event_type": .string("banquet"),
      ])
    expectMCPStructuredError(
      result, code: "validation", tool: "create_calendar_event",
      message: "Unsupported calendar event type 'banquet'.")
  }
}

// MARK: - Uniqueness collisions emit the conflict wire code

/// Renaming a tag or memory onto a name/key that already belongs to a different
/// entity throws `LorvexCoreError.conflict`, which the dispatch catch-all maps to
/// the `conflict` machine code (the same code as `StoreError.staleVersion`), so a
/// client distinguishes a name collision from a plain validation or generic
/// failure. The message stays the guard's exact "… already exists. …" sentence.
@Suite("MCP Tool Registry — uniqueness conflict envelope")
struct ConflictEnvelopeTests {
  @Test("rename_tag onto an existing tag emits a conflict envelope")
  func renameTagOntoExisting() async throws {
    let registry = try mcpInMemoryRegistry()
    // Seed two distinct tags by creating a task that carries both.
    let seed = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Tagged"), "tags_set": .array([.string("alpha"), .string("beta")]),
      ])
    #expect(seed.isError != true)

    let result = try await mcpRegistryCall(
      registry, tool: "rename_tag",
      arguments: ["old_name": .string("alpha"), "new_name": .string("beta")])
    expectMCPStructuredError(
      result, code: "conflict", tool: "rename_tag",
      message: "A tag named 'beta' already exists. Re-tag those tasks onto it "
        + "instead of renaming 'alpha' into it.")
  }
}
