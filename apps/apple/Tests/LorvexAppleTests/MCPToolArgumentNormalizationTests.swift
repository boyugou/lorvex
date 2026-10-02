import Foundation
import LorvexDomain
import MCP
import Testing

@testable import LorvexMCPHost

/// The dispatcher's argument pass (`ToolArgumentNormalization`): fence tokens
/// leave every string, and enum-declared properties accept only their values.
@Suite("MCP tool argument normalization")
struct MCPToolArgumentNormalizationTests {
  private static let schema: Value = .object([
    "type": .string("object"),
    "properties": .object([
      "status": .object(["type": .string("string"), "enum": .array([.string("open"), .string("all")])]),
      "priority": .object(["type": .string("integer"), "enum": .array([.int(1), .int(2), .int(3)])]),
      "fields": .object([
        "type": .string("array"),
        "items": .object(["type": .string("string"), "enum": .array([.string("id"), .string("title")])]),
      ]),
      "tasks": .object([
        "type": .string("array"),
        "items": .object([
          "type": .string("object"),
          "properties": .object([
            "title": .object(["type": .string("string")]),
            "priority": .object(["type": .string("integer"), "enum": .array([.int(1), .int(2), .int(3)])]),
          ]),
        ]),
      ]),
    ]),
  ])

  private static func fenced(_ text: String) -> String { SecurityFencing.fence(text) }

  @Test("fence tokens leave strings at any depth; lone brackets stay")
  func fenceTokensLeaveEveryString() throws {
    let normalized = try ToolArgumentNormalization.normalize(
      [
        "title": .string(Self.fenced("Buy milk")),
        "notes": .string("See \(Self.fenced("Buy milk")) and ⟦e⟧"),
        "tasks": .array([.object(["title": .string(Self.fenced("Call Ana"))])]),
        "tags": .array([.string(Self.fenced("errands"))]),
      ],
      schema: Self.schema)

    #expect(normalized["title"] == .string("Buy milk"))
    #expect(normalized["notes"] == .string("See Buy milk and ⟦e⟧"))
    #expect(normalized["tasks"] == .array([.object(["title": .string("Call Ana")])]))
    #expect(normalized["tags"] == .array([.string("errands")]))
  }

  @Test("an enum string matches case-insensitively and takes the declared spelling")
  func enumStringsTakeTheDeclaredSpelling() throws {
    let normalized = try ToolArgumentNormalization.normalize(
      ["status": .string(" All "), "fields": .array([.string("Title"), .string("id")])],
      schema: Self.schema)

    #expect(normalized["status"] == .string("all"))
    #expect(normalized["fields"] == .array([.string("title"), .string("id")]))
  }

  @Test("a value outside its enum names the path and every allowed value")
  func valuesOutsideTheEnumAreRejected() {
    #expect(
      throws: ValidationError.notOneOf(field: "status", allowed: ["open", "all"], actual: "done")
    ) {
      try ToolArgumentNormalization.normalize(["status": .string("done")], schema: Self.schema)
    }
    #expect(
      throws: ValidationError.notOneOf(field: "fields[1]", allowed: ["id", "title"], actual: "bogus")
    ) {
      try ToolArgumentNormalization.normalize(
        ["fields": .array([.string("id"), .string("bogus")])], schema: Self.schema)
    }
    #expect(
      throws: ValidationError.notOneOf(
        field: "tasks[1].priority", allowed: ["1", "2", "3"], actual: "7")
    ) {
      try ToolArgumentNormalization.normalize(
        ["tasks": .array([.object(["priority": .int(1)]), .object(["priority": .int(7)])])],
        schema: Self.schema)
    }
  }

  /// A string for an integer enum is the handler's to judge: `create_task`
  /// accepts "P1" for priority 1, and strict parsing rejects the rest.
  @Test("a value of another kind than its enum is left for the handler")
  func otherKindsPassThrough() throws {
    let normalized = try ToolArgumentNormalization.normalize(
      ["priority": .string("P1"), "status": .null, "tasks": .array([.object(["priority": .double(1.5)])])],
      schema: Self.schema)

    #expect(normalized["priority"] == .string("P1"))
    #expect(normalized["status"] == .null)
    #expect(normalized["tasks"] == .array([.object(["priority": .double(1.5)])]))
  }

  @Test("list_tasks rejects an unknown status instead of returning open tasks")
  func listTasksRejectsAnUnknownStatus() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["status": .string("done")])

    expectMCPStructuredError(
      result, code: "validation", tool: "list_tasks",
      message:
        "status must be one of open, in_progress, actionable, completed, cancelled, someday, all (got \"done\")"
    )
  }

  @Test("search_tasks accepts the actionable lane it supports")
  func searchTasksAcceptsActionable() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "search_tasks",
      arguments: ["query": .string("anything"), "status": .string("actionable")])

    #expect(result.isError != true)
  }

  @Test("a fenced title copied from a read stores the bare title")
  func fencedTitleStoresTheBareTitle() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string(Self.fenced("Renew passport"))])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let read = try await mcpRegistryCall(registry, tool: "get_task", arguments: ["id": .string(id)])
    let stored = read.structuredContent?.objectValue?["title"]?.stringValue
    // Fenced once by the response, never twice.
    #expect(stored == Self.fenced("Renew passport"))
  }
}
