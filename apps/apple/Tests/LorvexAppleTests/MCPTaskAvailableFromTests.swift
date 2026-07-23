import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// MCP surface coverage for `available_from` (defer-until): create/update
/// set + clear round-trips, that the value is NOT prompt-injection fenced
/// (it is a system date, not user free-text), and that the new `list_tasks`
/// availability / window params are accepted.
@Suite("MCP — available_from")
struct MCPTaskAvailableFromTests {
  private func call(
    _ registry: ToolRegistry, tool: String, arguments: [String: Value] = [:]
  ) async throws -> CallTool.Result {
    try await registry.call(CallTool.Parameters(name: tool, arguments: arguments))
  }

  private func availableFrom(_ result: CallTool.Result) -> Value? {
    result.structuredContent?.objectValue?["available_from"]
  }

  @Test("create_task carries available_from into the response")
  func createCarriesAvailableFrom() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Deferred capture"),
        "available_from": .string("2026-08-01"),
      ])
    #expect(result.isError != true)
    #expect(availableFrom(result) == .string("2026-08-01"))
  }

  @Test("update_task sets and clears available_from")
  func updateSetsAndClears() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await call(
      registry, tool: "create_task", arguments: ["title": .string("Snooze me")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let set = try await call(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "available_from": .string("2026-08-10")])
    #expect(availableFrom(set) == .string("2026-08-10"))

    // Explicit null clears the defer-until date.
    let cleared = try await call(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "available_from": .null])
    #expect(availableFrom(cleared) == .null)
  }

  @Test("update_task omitting available_from preserves it")
  func updatePreservesOnOmission() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await call(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep snooze"), "available_from": .string("2026-08-15")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let renamed = try await call(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "title": .string("Renamed only")])
    #expect(availableFrom(renamed) == .string("2026-08-15"))
  }

  @Test("available_from is a system date and is never fenced")
  func availableFromNotFenced() async throws {
    // The fencing allowlist must not include the system date column.
    #expect(!SecurityFencing.userContentKeys.contains("available_from"))

    // On the fenced list surface the value round-trips as a bare date.
    let registry = try mcpInMemoryRegistry()
    let title = "Fence-check-\(Int.random(in: 10000...99999))"
    _ = try await call(
      registry, tool: "create_task",
      arguments: ["title": .string(title), "available_from": .string("2026-09-05")])
    let listed = try await call(
      registry, tool: "list_tasks",
      arguments: ["text": .string(title), "shape": .string("full"), "limit": .int(5)])
    let task = try #require(
      listed.structuredContent?.objectValue?["tasks"]?.arrayValue?.first?.objectValue)
    #expect(task["available_from"]?.stringValue == "2026-09-05")
    // A fenced value would be wrapped in ⟦user⟧…⟦/user⟧ sentinels.
    let raw = try #require(task["available_from"]?.stringValue)
    #expect(!raw.contains("\u{27E6}"))
  }

  @Test("list_tasks accepts availability and available_from window params")
  func listAcceptsAvailabilityParams() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(
      registry, tool: "list_tasks",
      arguments: [
        "availability": .string("hidden"),
        "available_from_from": .string("2026-01-01"),
        "available_from_to": .string("2026-12-31"),
      ])
    #expect(result.isError != true)
  }
}
