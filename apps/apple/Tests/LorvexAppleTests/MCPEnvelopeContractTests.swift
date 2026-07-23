import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import LorvexSync
import MCP
import Testing

@testable import LorvexMCPHost

/// Contracts for the unified MCP response envelopes: the shared pagination
/// shape, the batch partial-success shape, the granular dispatch error codes,
/// and the reject-clean MCP priority decoder.
@Suite("MCP envelope contracts")
struct MCPEnvelopeContractTests {

  // MARK: - Pagination envelope

  private static let canonicalPaginationKeys = [
    "total_matching", "returned", "limit", "offset", "next_offset", "next_cursor", "truncated",
  ]
  private static let retiredPaginationAliases = ["count", "returned_count", "total_tasks", "total"]

  @Test("list_tasks emits the canonical pagination envelope with no legacy aliases")
  func listTasksCanonicalEnvelope() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["limit": .int(1)])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    for key in Self.canonicalPaginationKeys {
      #expect(object[key] != nil, "missing canonical pagination key: \(key)")
    }
    // next_cursor is reserved for future cursor pagination and is null today.
    #expect(object["next_cursor"] == .null)
    for alias in Self.retiredPaginationAliases {
      #expect(object[alias] == nil, "legacy pagination alias should be dropped: \(alias)")
    }
  }

  @Test("get_upcoming_tasks shares the canonical envelope and drops total_tasks")
  func upcomingTasksCanonicalEnvelope() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "get_upcoming_tasks", arguments: ["days": .int(30), "limit": .int(5)])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["next_cursor"] == .null)
    #expect(object["total_matching"] != nil)
    #expect(object["returned"] != nil)
    #expect(object["total_tasks"] == nil)
  }

  @Test("search_tasks empty result carries the canonical envelope, not count")
  func searchTasksCanonicalEnvelope() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "search_tasks", arguments: ["query": .string("")])
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["returned"]?.intValue == 0)
    #expect(object["next_cursor"] == .null)
    #expect(object["count"] == nil)
  }

  // MARK: - Batch partial-success shape

  /// Every batch tool now returns the identical `{results, count, skipped}`
  /// spine (plus additive context). None of the pre-unification array keys
  /// (`created`/`updated`/`tasks`/`reopened`/`deferred`/`habits`) or count
  /// aliases (`*_count`) survive.
  private static let retiredBatchArrayKeys = [
    "created", "updated", "tasks", "reopened", "deferred", "habits",
  ]
  private static let retiredBatchCountKeys = [
    "created_count", "completed_count", "reopened_count", "cancelled_count", "moved_count",
    "deferred_count",
  ]

  @Test("batch_create_tasks returns the unified {results, count, skipped} spine")
  func batchCreatePartialSuccessShape() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "batch_create_tasks",
      arguments: ["tasks": .array([.object(["title": .string("Envelope batch task")])])])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["results"]?.arrayValue?.count == 1)
    #expect(object["count"]?.intValue == 1)
    #expect(object["skipped"]?.arrayValue?.isEmpty == true)
    for key in Self.retiredBatchArrayKeys { #expect(object[key] == nil, "retired array key: \(key)") }
    for key in Self.retiredBatchCountKeys { #expect(object[key] == nil, "retired count key: \(key)") }
  }

  @Test("batch_update_tasks returns the unified {results, count, skipped} spine")
  func batchUpdatePartialSuccessShape() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "batch_create_tasks",
      arguments: ["tasks": .array([.object(["title": .string("Update shape seed")])])])
    let id = try #require(
      created.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue?["id"]?
        .stringValue)
    let updated = try await mcpRegistryCall(
      registry, tool: "batch_update_tasks",
      arguments: ["updates": .array([.object(["id": .string(id), "priority": .int(1)])])])
    #expect(updated.isError != true)
    let object = try #require(updated.structuredContent?.objectValue)
    #expect(object["results"]?.arrayValue?.count == 1)
    #expect(object["count"]?.intValue == 1)
    #expect(object["skipped"]?.arrayValue?.isEmpty == true)
    for key in Self.retiredBatchArrayKeys { #expect(object[key] == nil, "retired array key: \(key)") }
    for key in Self.retiredBatchCountKeys { #expect(object[key] == nil, "retired count key: \(key)") }
  }

  @Test("batch skipped entries are {id, reason} objects, not bare id strings")
  func batchSkippedObjectShape() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string("task-mcp-swift-sdk-spike"), .string("ghost-id")])])
    #expect(result.isError != true)
    let skipped = try #require(result.structuredContent?.objectValue?["skipped"]?.arrayValue)
    let ghost = try #require(skipped.first { $0.objectValue?["id"]?.stringValue == "ghost-id" })
    #expect(ghost.objectValue?["reason"]?.stringValue?.isEmpty == false)
    // A bare-string skipped entry (the pre-unification form) must never appear.
    #expect(skipped.allSatisfy { $0.objectValue != nil })
  }

  // MARK: - Priority reject-clean (DE-6)

  @Test("priority decoder accepts 1/2/3 and absence, rejects anything else")
  func priorityDecoderRejectsClean() throws {
    #expect(try CoreBridgeClient.priority(from: .int(1)) == .p1)
    #expect(try CoreBridgeClient.priority(from: .int(2)) == .p2)
    #expect(try CoreBridgeClient.priority(from: .int(3)) == .p3)
    #expect(try CoreBridgeClient.priority(from: nil) == nil)
    #expect(try CoreBridgeClient.priority(from: .null) == nil)
    // An out-of-range value is rejected, not silently coerced to .p2.
    #expect(throws: ValidationError.self) { _ = try CoreBridgeClient.priority(from: .int(5)) }
    #expect(throws: ValidationError.self) { _ = try CoreBridgeClient.priority(from: .int(0)) }
    #expect(throws: ValidationError.self) {
      _ = try CoreBridgeClient.priority(from: .string("urgent"))
    }
  }

  @Test("create_task with an unrecognized priority returns a validation error code")
  func createTaskInvalidPriorityValidationCode() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let result = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: ["title": .string("Bad priority task"), "priority": .int(9)])
    #expect(result.isError == true)
    #expect(result.structuredContent?.objectValue?["code"]?.stringValue == "validation")
  }

  // MARK: - Granular dispatch error codes (FIX 2c)

  @Test("the dispatch error-code map covers each stable code with a tool_error fallback")
  func dispatchErrorCodeMapping() {
    #expect(ToolRegistry.errorCode(for: StoreError.notFound(entity: "task", id: "x")) == "not_found")
    #expect(
      ToolRegistry.errorCode(for: StoreError.staleVersion(entity: "task", id: "x")) == "conflict")
    #expect(ToolRegistry.errorCode(for: StoreError.validation("bad")) == "validation")
    #expect(ToolRegistry.errorCode(for: StoreError.serialization("x")) == "tool_error")
    #expect(ToolRegistry.errorCode(for: ValidationError.message("bad")) == "validation")
    #expect(ToolRegistry.errorCode(for: LorvexCoreError.taskNotFound) == "not_found")
    #expect(ToolRegistry.errorCode(for: LorvexCoreError.emptyTitle) == "validation")
    #expect(
      ToolRegistry.errorCode(for: ApplyError.dependencyCycleRejected(taskId: "a", dependsOn: "b"))
        == "dependency_cycle")
    // Unrecognized domain errors fall back to the generic code.
    #expect(ToolRegistry.errorCode(for: LorvexCoreError.unsupportedOperation("x")) == "tool_error")
    // A typed entity not-found maps to `not_found`, joining `taskNotFound` so
    // every lookup miss carries the same machine-readable class.
    #expect(
      ToolRegistry.errorCode(for: LorvexCoreError.notFound(entity: .list, id: "x")) == "not_found")
    #expect(
      ToolRegistry.errorCode(for: LorvexCoreError.notFound(entity: .calendarEvent, id: nil))
        == "not_found")
    // The typed validation case maps to the same `validation` code as `emptyTitle`.
    #expect(
      ToolRegistry.errorCode(for: LorvexCoreError.validation(field: "mood", message: "bad"))
        == "validation")
    // A typed uniqueness collision shares the `conflict` code with `StoreError.staleVersion`.
    #expect(
      ToolRegistry.errorCode(for: LorvexCoreError.conflict(message: "already exists")) == "conflict")
  }

  // MARK: - Validation/error guards route through the unified envelope (AI-3 Part 2)

  @Test("a missing-argument guard now returns a validation-coded envelope")
  func missingArgumentGuardIsEnveloped() async throws {
    let registry = try mcpInMemoryRegistry()
    // complete_habit without an id used to return a raw isError text result.
    let result = try await mcpRegistryCall(registry, tool: "complete_habit", arguments: [:])
    expectMCPStructuredError(result, code: "validation", tool: "complete_habit")
  }

  @Test("batch validation guards route through the unified envelope")
  func batchGuardIsEnveloped() async throws {
    let registry = try mcpInMemoryRegistry()
    let empty = try await mcpRegistryCall(
      registry, tool: "batch_complete_tasks", arguments: ["task_ids": .array([])])
    expectMCPStructuredError(empty, code: "validation", tool: "batch_complete_tasks")

    let noList = try await mcpRegistryCall(
      registry, tool: "batch_cancel_tasks_in_list", arguments: [:])
    expectMCPStructuredError(noList, code: "validation", tool: "batch_cancel_tasks_in_list")
  }

  @Test("checklist and habit-name guards carry validation code + tool name")
  func representativeGuardsAreEnveloped() async throws {
    let registry = try mcpInMemoryRegistry()
    let checklist = try await mcpRegistryCall(
      registry, tool: "add_task_checklist_item", arguments: ["text": .string("no task id")])
    expectMCPStructuredError(checklist, code: "validation", tool: "add_task_checklist_item")

    let habit = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("   ")])
    expectMCPStructuredError(habit, code: "validation", tool: "create_habit")

    let search = try await mcpRegistryCall(registry, tool: "search_tasks", arguments: [:])
    expectMCPStructuredError(search, code: "validation", tool: "search_tasks")
  }

  // MARK: - Read-tool caps + real truncation (AI-3 Part 3a/3b)

  @Test("get_habit_completions caps at limit and reports a real truncated flag")
  func habitCompletionsLimitAndTruncation() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_habit",
      arguments: ["name": .string("Completions cap habit"), "target_count": .int(10)])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // Two completions on distinct dates → two per-day rows.
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "complete_habit",
      arguments: ["id": .string(id), "date": .string("2026-05-24")])
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "complete_habit",
      arguments: ["id": .string(id), "date": .string("2026-05-25")])

    let capped = try await mcpRegistryCall(
      fixture.registry, tool: "get_habit_completions",
      arguments: ["habit_id": .string(id), "limit": .int(1)])
    #expect(capped.isError != true)
    let object = try #require(capped.structuredContent?.objectValue)
    #expect(object["completions"]?.arrayValue?.count == 1)
    #expect(object["returned"]?.intValue == 1)
    #expect(object["limit"]?.intValue == 1)
    #expect(object["truncated"]?.boolValue == true)
    // Truncated pages assert no false total.
    #expect(object["total_matching"] == .null)

    let full = try await mcpRegistryCall(
      fixture.registry, tool: "get_habit_completions",
      arguments: ["habit_id": .string(id), "limit": .int(100)])
    let fullObject = try #require(full.structuredContent?.objectValue)
    #expect(fullObject["truncated"]?.boolValue == false)
    #expect(fullObject["total_matching"]?.intValue == fullObject["returned"]?.intValue)
  }

  @Test("get_habit_completions advertises the limit input in its schema")
  func habitCompletionsSchemaHasLimit() async throws {
    let tool = try #require(
      ToolRegistry.listTools().first { $0.name == "get_habit_completions" })
    let properties = tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
    #expect(properties["limit"] != nil)
  }

  // MARK: - Enum schema (AI-3 Part 3c)

  @Test("search_tasks.status and habit frequency_type advertise real enum arrays")
  func enumSchemasArePresent() async throws {
    let tools = ToolRegistry.listTools()
    let search = try #require(tools.first { $0.name == "search_tasks" })
    let status = search.inputSchema.objectValue?["properties"]?.objectValue?["status"]?.objectValue
    #expect(status?["enum"]?.arrayValue?.contains(.string("someday")) == true)

    let createHabit = try #require(tools.first { $0.name == "create_habit" })
    let freq = createHabit.inputSchema.objectValue?["properties"]?.objectValue?["frequency_type"]?
      .objectValue
    #expect(freq?["enum"]?.arrayValue?.contains(.string("daily")) == true)
  }

  @Test("calendar recurrence patch advertises null and ordinal BYDAY")
  func calendarRecurrencePatchSchemaIsThreeStateAndOrdinalCapable() throws {
    let update = try #require(
      ToolRegistry.listTools().first { $0.name == "update_calendar_event" })
    let recurrence = try #require(
      update.inputSchema.objectValue?["properties"]?.objectValue?["recurrence"]?.objectValue)
    #expect(recurrence["type"]?.arrayValue == [.string("object"), .string("null")])
    #expect(recurrence["description"]?.stringValue?.contains("count must be 1-365") == true)
    let pattern = recurrence["properties"]?.objectValue?["byday"]?.objectValue?["items"]?
      .objectValue?["pattern"]?.stringValue
    #expect(pattern?.contains("5[0-3]") == true)
  }

  @Test("enum constraints hold uniformly across every surface that enforces them")
  func enumConstraintsAreUniform() async throws {
    let tools = ToolRegistry.listTools()

    func properties(of name: String) throws -> [String: Value] {
      let tool = try #require(tools.first { $0.name == name })
      return tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
    }
    func itemProperties(of name: String, arrayField: String) throws -> [String: Value] {
      let field = try #require(try properties(of: name)[arrayField]?.objectValue)
      return field["items"]?.objectValue?["properties"]?.objectValue ?? [:]
    }

    // event_type is enum on create/update/batch AND on the scoped edit surface.
    let scopedEventType = try #require(
      properties(of: "edit_scoped_calendar_event")["event_type"]?.objectValue)
    #expect(scopedEventType["enum"]?.arrayValue == [
      .string("event"), .string("birthday"), .string("anniversary"), .string("memorial"),
    ])

    // priority is enum on create/update/list AND in the batch item schemas.
    let batchCreatePriority = try #require(
      itemProperties(of: "batch_create_tasks", arrayField: "tasks")["priority"]?.objectValue)
    #expect(batchCreatePriority["enum"]?.arrayValue == [.int(1), .int(2), .int(3)])
    let batchUpdatePriority = try #require(
      itemProperties(of: "batch_update_tasks", arrayField: "updates")["priority"]?.objectValue)
    #expect(batchUpdatePriority["enum"]?.arrayValue == [.int(1), .int(2), .int(3)])

    // block_type is a real JSON enum, not enum-by-prose.
    let blockType = try #require(
      itemProperties(of: "save_focus_schedule", arrayField: "blocks")["block_type"]?.objectValue)
    #expect(blockType["enum"]?.arrayValue == [
      .string("task"), .string("buffer"), .string("event"),
    ])
  }
}
