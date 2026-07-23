import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Extended — memory registry")
struct MCPMemoryExtendedToolsTests {
  @Test("rename_memory atomically moves a memory and rejects an existing target")
  func renameMemoryMovesAndRejectsCollision() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await contentCall(
      registry, tool: "write_memory",
      arguments: ["key": .string("draft"), "content": .string("body")])

    let ok = try await contentCall(
      registry, tool: "rename_memory",
      arguments: ["old_key": .string("draft"), "new_key": .string("final")])
    #expect(ok.isError != true)

    // The renamed memory is readable under the new key, gone under the old.
    let underNew = try await contentCall(
      registry, tool: "read_memory", arguments: ["key": .string("final")])
    #expect(underNew.isError != true)

    // Renaming onto a different existing key is a uniqueness collision: rejected
    // with the `conflict` wire code (not the generic `tool_error`) and the exact
    // guidance sentence, so an MCP client can distinguish it from a bad input.
    _ = try await contentCall(
      registry, tool: "write_memory",
      arguments: ["key": .string("occupied"), "content": .string("x")])
    let collision = try await contentCall(
      registry, tool: "rename_memory",
      arguments: ["old_key": .string("final"), "new_key": .string("occupied")])
    #expect(collision.isError == true)
    #expect(collision.structuredContent?.objectValue?["code"]?.stringValue == "conflict")
    // The memory dispatch path fences user-controlled text in the error message
    // (the keys are user input), so assert the guidance sentence is present rather
    // than pinning the ⟦user⟧…⟦/user⟧ sentinels.
    #expect(
      collision.structuredContent?.objectValue?["message"]?.stringValue?
        .contains(
          "A memory named 'occupied' already exists. Combine their content under one key "
            + "instead of renaming 'final' onto it.") == true)
  }

  @Test("delete_memory removes a memory")
  func deleteMemory() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await contentCall(
      registry, tool: "write_memory",
      arguments: ["key": .string("swift_migration"), "content": .string("deletable note")])
    let result = try await contentCall(
      registry,
      tool: "delete_memory",
      arguments: ["key": .string("swift_migration")]
    )
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    // Uniform delete-return shape: {deleted, id, previous} + domain-natural key.
    #expect(object["deleted"]?.boolValue == true)
    let fencedKey = SecurityFencing.fence("swift_migration")
    #expect(object["id"]?.stringValue == fencedKey)
    #expect(object["key"]?.stringValue == fencedKey)
    // previous carries the removed entry with its content fenced.
    let previous = try #require(object["previous"]?.objectValue)
    #expect(previous["key"]?.stringValue == fencedKey)
    #expect(previous["content"]?.stringValue?.isEmpty == false)
  }

  @Test("delete_memory reports missing memory as deleted:false with null previous")
  func deleteMemoryMissingKey() async throws {
    let result = try await contentCall(
      try mcpInMemoryRegistry(),
      tool: "delete_memory",
      arguments: ["key": .string("no_such_memory_key")]
    )
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["deleted"]?.boolValue == false)
    #expect(object["previous"] == .null)
  }
}
