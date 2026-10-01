import Testing

@testable import LorvexMCPHost

@Suite("MCP host instructions")
struct MCPHostInstructionsTests {
  /// Every snake_case identifier the instructions mention must be something a
  /// client can use (see ``MCPToolVocabulary``), so a renamed tool or parameter
  /// fails here instead of leaving every assistant session with guidance that
  /// points at nothing.
  @Test("every identifier the instructions mention exists in the tool surface")
  func mentionedIdentifiersExist() throws {
    let mentioned = MCPToolVocabulary.snakeCaseIdentifiers(in: MCPHostInstructions.text)
    let unknown = mentioned.subtracting(MCPToolVocabulary.identifiers())
    #expect(mentioned.count > 10)
    #expect(unknown.isEmpty, "Unknown identifiers: \(unknown.sorted())")
  }

  @Test("the instructions stay short enough to ride in every session's context")
  func instructionsStayShort() {
    #expect(MCPHostInstructions.text.count < 3_000)
  }
}
