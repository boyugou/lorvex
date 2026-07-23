import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — list tools")
struct ListToolTests {

  @Test("get_lists returns non-error result")
  func getLists() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_lists")
    #expect(result.isError != true)
  }

  @Test("list tools create update get health and delete")
  func listToolsRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry,
      tool: "create_list",
      arguments: [
        "name": .string("Native Planning"),
        "description": .string("Apple native planning surface"),
      ]
    )
    #expect(created.isError != true)
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let updated = try await mcpRegistryCall(
      registry,
      tool: "update_list",
      arguments: [
        "id": .string(listID),
        "name": .string("Native Planning Updated"),
        "description": .string("Updated planning surface"),
      ]
    )
    #expect(updated.isError != true)
    let fencedUpdatedName: String = SecurityFencing.fence("Native Planning Updated")
    #expect(
      updated.structuredContent?.objectValue?["name"]?.stringValue == fencedUpdatedName)

    let loaded = try await mcpRegistryCall(
      registry,
      tool: "get_list",
      arguments: ["id": .string(listID)]
    )
    #expect(loaded.isError != true)
    let fencedDescription: String = SecurityFencing.fence("Updated planning surface")
    #expect(
      loaded.structuredContent?.objectValue?["description"]?.stringValue
        == fencedDescription)

    let health = try await mcpRegistryCall(registry, tool: "get_list_health_snapshot")
    #expect(health.isError != true)
    let healthLists = health.structuredContent?.objectValue?["lists"]?.arrayValue ?? []
    #expect(healthLists.contains { $0.objectValue?["id"]?.stringValue == listID })

    let deleted = try await mcpRegistryCall(
      registry,
      tool: "delete_list",
      arguments: ["id": .string(listID)]
    )
    #expect(deleted.isError != true)
    // Uniform delete-return shape: {deleted, id, previous}.
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)
    #expect(deleted.structuredContent?.objectValue?["id"]?.stringValue == listID)
    #expect(deleted.structuredContent?.objectValue?["deleted_list_id"] == nil)
    #expect(
      deleted.structuredContent?.objectValue?["previous"]?.objectValue?["id"]?.stringValue == listID)
  }

  /// `ai_notes` is reachable end-to-end: writable via create_list/set_list_ai_notes and
  /// returned by get_list, fenced as AI-facing user text.
  @Test("create_list + set_list_ai_notes round-trip ai_notes; get_list returns it fenced")
  func listAiNotesRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_list",
      arguments: ["name": .string("Scoped"), "ai_notes": .string("Work projects only")])
    #expect(created.isError != true)
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let loaded = try await mcpRegistryCall(
      registry, tool: "get_list", arguments: ["id": .string(listID)])
    let fencedCreate: String = SecurityFencing.fence("Work projects only")
    #expect(
      loaded.structuredContent?.objectValue?["ai_notes"]?.stringValue == fencedCreate)

    let updated = try await mcpRegistryCall(
      registry, tool: "set_list_ai_notes",
      arguments: ["list_id": .string(listID), "notes": .string("Now includes personal")])
    #expect(updated.isError != true)

    let reloaded = try await mcpRegistryCall(
      registry, tool: "get_list", arguments: ["id": .string(listID)])
    let fencedUpdate: String = SecurityFencing.fence("Now includes personal")
    #expect(
      reloaded.structuredContent?.objectValue?["ai_notes"]?.stringValue == fencedUpdate)

    let cleared = try await mcpRegistryCall(
      registry, tool: "set_list_ai_notes",
      arguments: ["list_id": .string(listID), "notes": .string("")])
    #expect(cleared.isError != true)
    #expect(cleared.structuredContent?.objectValue?["ai_notes"] == .null)
  }

  /// Idempotency must be all-or-nothing per tool: a tool that advertises
  /// `idempotency_key` in its schema must also be enforced (in
  /// `idempotentWriteTools`), or a client-supplied key is silently ignored and a
  /// checksum mismatch is never rejected (violating the idempotency contract);
  /// and an enforced tool must advertise the key so clients can discover it.
  @Test("idempotency_key advertisement matches enforcement")
  func idempotencyAdvertisementMatchesEnforcement() async {
    let advertised = Set(
      ToolRegistry.listTools()
        .filter { $0.inputSchema.objectValue?["properties"]?.objectValue?["idempotency_key"] != nil }
        .map(\.name)
    )
    let advertisedEnforceable = advertised
    let enforced = ToolRegistry.idempotentWriteTools
    #expect(
      advertisedEnforceable == enforced,
      """
      idempotency_key advertise/enforce mismatch.
      Advertised but not enforced: \(advertisedEnforceable.subtracting(enforced).sorted())
      Enforced but not advertised: \(enforced.subtracting(advertisedEnforceable).sorted())
      """)
  }

  /// Every destructive write must be idempotency-enforced: a retry after a
  /// transport timeout has to replay the original response, not re-run and (for
  /// a delete) report `deleted: false` with no before-snapshot. This catches the
  /// gap the advertise/enforce test cannot — a destructive tool that exposes
  /// neither the `idempotency_key` schema nor enforcement passes that test by
  /// being absent from both sides, yet is still unsafe to retry.
  @Test("destructive write tools are idempotency-enforced")
  func destructiveWritesAreIdempotencyEnforced() async {
    let destructive = Set(
      ToolRegistry.listTools()
        .filter { $0.annotations.destructiveHint == true }
        .map(\.name)
    )
    let unenforced = destructive.subtracting(ToolRegistry.idempotentWriteTools)
    #expect(
      unenforced.isEmpty,
      "Destructive tools missing from idempotentWriteTools: \(unenforced.sorted())")
  }

  @Test("archive_list and unarchive_list mutate archived state and get_lists visibility")
  func archiveUnarchiveRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry,
      tool: "create_list",
      arguments: ["name": .string("Company A")]
    )
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let archived = try await mcpRegistryCall(
      registry,
      tool: "archive_list",
      arguments: ["id": .string(listID)]
    )
    #expect(archived.isError != true)
    #expect(archived.structuredContent?.objectValue?["id"]?.stringValue == listID)
    #expect(archived.structuredContent?.objectValue?["archived"]?.boolValue == true)

    // The archived list leaves the default listing and appears only with
    // include_archived.
    func listedIDs(includeArchived: Bool) async throws -> [String] {
      let result = try await mcpRegistryCall(
        registry, tool: "get_lists",
        arguments: includeArchived ? ["include_archived": .bool(true)] : [:])
      #expect(result.isError != true)
      return result.structuredContent?.objectValue?["lists"]?.arrayValue?
        .compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    }
    #expect(try await !listedIDs(includeArchived: false).contains(listID))
    #expect(try await listedIDs(includeArchived: true).contains(listID))

    let unarchived = try await mcpRegistryCall(
      registry,
      tool: "unarchive_list",
      arguments: ["id": .string(listID)]
    )
    #expect(unarchived.isError != true)
    #expect(unarchived.structuredContent?.objectValue?["id"]?.stringValue == listID)
    #expect(unarchived.structuredContent?.objectValue?["archived"]?.boolValue == false)
    #expect(try await listedIDs(includeArchived: false).contains(listID))
  }

  @Test("delete_list of a missing id reports deleted:false, not a spurious success")
  func deleteListOfMissingIdReportsDeletedFalse() async throws {
    let registry = try mcpInMemoryRegistry()
    // A second list so the core's "can't delete the last list" guard doesn't fire
    // — this exercises the missing-id no-op path, not the last-list refusal.
    _ = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string("Scratch")])
    let result = try await mcpRegistryCall(
      registry, tool: "delete_list", arguments: ["id": .string("does-not-exist")])
    #expect(result.isError != true)
    #expect(
      result.structuredContent?.objectValue?["deleted"]?.boolValue == false,
      "deleting a nonexistent list is a no-op and must not report deleted:true")
    #expect(result.structuredContent?.objectValue?["previous"] == .null)
  }

  @Test("delete_list rejects lists with assigned tasks")
  func deleteListRejectsAssignedTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string("Occupied")])
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Occupant"), "list_id": .string(listID)])

    let result = try await mcpRegistryCall(
      registry, tool: "delete_list", arguments: ["id": .string(listID)])
    #expect(result.isError == true)
    #expect(
      mcpTextContent(result)
        == SecurityFencing.fence("Cannot delete list while 1 task(s) are assigned."))
  }

  @Test("delete_list rejects the sentinel inbox list")
  func deleteListRejectsInbox() async throws {
    let result = try await mcpRegistryCall(
      try mcpInMemoryRegistry(),
      tool: "delete_list",
      arguments: ["id": .string("inbox")]
    )
    #expect(result.isError == true)
    #expect(
      mcpTextContent(result)
        == SecurityFencing.fence(
          "Cannot delete the inbox list: it is the canonical fallback for tasks and must always exist."))
  }

  @Test("reorder_lists sets the manual order and returns the refreshed catalog")
  func reorderListsRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string("Alpha")])
    _ = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string("Beta")])

    func listedIDs(_ result: CallTool.Result) -> [String] {
      result.structuredContent?.objectValue?["lists"]?.arrayValue?
        .compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    }

    let before = try await mcpRegistryCall(registry, tool: "get_lists")
    let original = listedIDs(before)
    #expect(original.count >= 3)  // sentinel inbox + the two created lists
    let reversed = Array(original.reversed())
    #expect(reversed != original)

    let reordered = try await mcpRegistryCall(
      registry, tool: "reorder_lists",
      arguments: ["list_ids": .array(reversed.map(Value.string))])
    #expect(reordered.isError != true)
    // Rich return per Core Design Rule 7: the full refreshed catalog in the new order.
    #expect(listedIDs(reordered) == reversed)

    let after = try await mcpRegistryCall(registry, tool: "get_lists")
    #expect(listedIDs(after) == reversed)
  }

  @Test("reorder_lists with an empty list_ids array is a validation error")
  func reorderListsRejectsEmpty() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "reorder_lists", arguments: ["list_ids": .array([])])
    expectMCPStructuredError(result, code: "validation", tool: "reorder_lists")
  }
}
