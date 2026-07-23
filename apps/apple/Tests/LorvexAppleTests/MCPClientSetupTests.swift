import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

@Test
func mcpClientSetupSnippetOmitsEnvForManagedDatabase() throws {
  let setup = MCPClientSetup(
    serverName: "lorvex-apple",
    commandPath: "/Applications/Lorvex.app/Contents/Helpers/LorvexMCPHost"
  )

  let root = try JSONSerialization.jsonObject(with: Data(setup.jsonSnippet.utf8)) as? [String: Any]
  let entry = (root?["mcpServers"] as? [String: Any])?["lorvex-apple"] as? [String: Any]
  #expect(entry?["command"] as? String == "/Applications/Lorvex.app/Contents/Helpers/LorvexMCPHost")
  #expect(entry?["type"] as? String == "stdio")
  #expect((entry?["args"] as? [Any])?.isEmpty == true)
  // The managed App Group store needs no override, so the config never carries env.
  #expect(entry?["env"] == nil)

  #expect(setup.setupPrompt.contains("/Applications/Lorvex.app/Contents/Helpers/LorvexMCPHost"))
  #expect(setup.setupPrompt.contains("lorvex-apple"))
  #expect(!setup.setupPrompt.contains("LORVEX_APPLE_DB_PATH"))
  #expect(!setup.setupPrompt.contains("Copy Config"))
}

@Test
func mcpClientSetupCurrentTargetsBundledHelperWithNoEnv() throws {
  let setup = MCPClientSetup.current()

  #expect(setup.serverName == LorvexProductMetadata.mcpServerName)
  #expect(setup.commandPath == MCPHelperProbe.helperURL().path)

  let root = try JSONSerialization.jsonObject(with: Data(setup.jsonSnippet.utf8)) as? [String: Any]
  let entry = (root?["mcpServers"] as? [String: Any])?[LorvexProductMetadata.mcpServerName]
    as? [String: Any]
  #expect(entry?["env"] == nil)
}
