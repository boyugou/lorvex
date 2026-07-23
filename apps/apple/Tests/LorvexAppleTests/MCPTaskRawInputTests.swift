import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// MCP surface coverage for `raw_input`: the user's verbatim original capture
/// text, stored alongside the AI-parsed task fields to back the "show the
/// mapping" transparent-reasoning product principle.
///
/// Runs against the on-disk Swift core bridge (`mcpOnDiskRegistry`) so the
/// coverage exercises the full write path — MCP tool → `CoreBridgeClient` →
/// `SwiftLorvexCoreService` → `LorvexWorkflow` — not just the in-memory
/// preview fallback.
@Suite("MCP — raw_input")
struct MCPTaskRawInputTests {
  private func rawInput(_ result: CallTool.Result) -> Value? {
    result.structuredContent?.objectValue?["raw_input"]
  }

  @Test("create_task stores raw_input and get_task returns it, fenced")
  func createStoresRawInputAndGetTaskReturnsIt() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: [
        "title": .string("Call mom"),
        "raw_input": .string("remind me to call mom next week"),
      ])
    #expect(created.isError != true)
    let fencedRawInput = SecurityFencing.fence("remind me to call mom next week")
    #expect(rawInput(created) == .string(fencedRawInput))

    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let fetched = try await mcpRegistryCall(
      fixture.registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(fetched.isError != true)
    #expect(rawInput(fetched) == .string(fencedRawInput))
  }

  @Test("create_task without raw_input leaves it null")
  func createWithoutRawInputLeavesItNull() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("No capture text")])
    #expect(created.isError != true)
    #expect(rawInput(created) == .null)
  }

  @Test("update_task sets raw_input")
  func updateSetsRawInput() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Capture later")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let updated = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "raw_input": .string("book the dentist for sometime in march"),
      ])
    #expect(updated.isError != true)
    let fencedRawInput = SecurityFencing.fence("book the dentist for sometime in march")
    #expect(rawInput(updated) == .string(fencedRawInput))
  }

  @Test("update_task omitting raw_input preserves the existing value")
  func updatePreservesRawInputOnOmission() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: [
        "title": .string("Preserve capture"),
        "raw_input": .string("ping the team about the release next monday"),
      ])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // Update only the title: raw_input was not supplied, so it must survive
    // rather than be wiped/cleared — mirroring how an omitted `notes` value
    // is preserved by `update_task`.
    let renamed = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "title": .string("Preserve capture (renamed)")])
    #expect(renamed.isError != true)
    let fencedRawInput = SecurityFencing.fence("ping the team about the release next monday")
    #expect(rawInput(renamed) == .string(fencedRawInput))
  }

  @Test("update_task with explicit null clears raw_input")
  func updateExplicitNullClearsRawInput() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: [
        "title": .string("Clear capture"),
        "raw_input": .string("some verbatim capture text"),
      ])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let cleared = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "raw_input": .null])
    #expect(cleared.isError != true)
    #expect(rawInput(cleared) == .null)
  }

  @Test("raw_input is user content and is fenced")
  func rawInputIsFenced() {
    #expect(SecurityFencing.userContentKeys.contains("raw_input"))
  }
}
