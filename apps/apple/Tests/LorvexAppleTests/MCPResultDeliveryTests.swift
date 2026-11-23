import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// Clients differ in what they hand the model: some pass only a result's
/// `structuredContent`, some only the text in `content`. Every result
/// therefore ends its text with the structured payload as JSON, and anything
/// meant for the model is in the structured payload.
@Suite("MCP result delivery")
struct MCPResultDeliveryTests {
  @Test("a read's text ends with its structured payload")
  func readTextCarriesThePayload() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(registry, tool: "get_session_context")

    let structured = try #require(result.structuredContent)
    #expect(structured.objectValue?["date"]?.stringValue != nil)
    #expect(try mcpPayloadInText(result) == structured)
    #expect(mcpTextBlocks(result).count == 2)
  }

  @Test("a write's text keeps its summary and ends with the record it returns")
  func writeTextCarriesTheRecord() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Book the venue")])

    let summary: String = SecurityFencing.fence("Created task: Book the venue")
    #expect(mcpTextBlocks(result).first == summary)
    let record = try mcpPayloadInText(result)
    #expect(record == result.structuredContent)
    #expect(record.objectValue?["id"]?.stringValue?.isEmpty == false)
  }

  @Test("an error's text ends with its code")
  func errorTextCarriesTheCode() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string("no-such-task")])

    #expect(result.isError == true)
    let payload = try mcpPayloadInText(result)
    #expect(payload == result.structuredContent)
    #expect(payload.objectValue?["code"]?.stringValue == "not_found")
  }

  @Test("a note about an ignored argument is in the payload, once, wherever it is read")
  func ignoredArgumentNoteIsInThePayload() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "get_session_context", arguments: ["foo": .int(1)])

    let warnings = try #require(result.structuredContent?.objectValue?["warnings"]?.arrayValue)
    #expect(warnings.count == 1)
    #expect(warnings.first?.stringValue?.contains("foo") == true)
    #expect(try mcpPayloadInText(result) == result.structuredContent)
    // The note is not repeated as a text block of its own.
    #expect(mcpTextBlocks(result).count == 2)
  }

  /// `GMT` is stored as `UTC` on every system, so the answer differs from the
  /// input whatever names this system's time zone list holds.
  @Test("set_preference answers with the value stored, not the value sent")
  func setPreferenceAnswersWithTheStoredValue() async throws {
    let registry = try mcpInMemoryRegistry()

    let set = try await mcpRegistryCall(
      registry, tool: "set_preference",
      arguments: ["key": .string("timezone"), "value": .string("GMT")])
    let read = try await mcpRegistryCall(
      registry, tool: "get_preference", arguments: ["key": .string("timezone")])

    #expect(set.isError != true)
    let answered = try #require(set.structuredContent?.objectValue?["value"])
    #expect(answered == read.structuredContent?.objectValue?["value"])
    #expect(answered.stringValue?.contains("UTC") == true)
    #expect(answered.stringValue?.contains("GMT") == false)
  }

  @Test("a replayed write has the same text and payload as the first answer")
  func replayedWriteIsDeliveredTheSameWay() async throws {
    let registry = try mcpInMemoryRegistry()
    let arguments: [String: Value] = [
      "title": .string("Send the invoice"), "idempotency_key": .string("delivery-replay-1"),
    ]

    let first = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)
    let replay = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)

    #expect(replay.structuredContent == first.structuredContent)
    #expect(mcpTextBlocks(replay) == mcpTextBlocks(first))
    #expect(mcpTextBlocks(replay).count == 2)
  }
}
