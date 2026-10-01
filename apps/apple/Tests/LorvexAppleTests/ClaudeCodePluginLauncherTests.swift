import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The Claude Code plugin (`plugins/lorvex`) starts the MCP helper inside the
/// installed app through its launcher script, which hard-codes the app's name,
/// bundle identifier, and helper layout. These tests hold that script to what
/// the app actually ships.
@Suite("Claude Code plugin launcher")
struct ClaudeCodePluginLauncherTests {
  private static let pluginRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // LorvexAppleTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // apps/apple
    .deletingLastPathComponent()  // apps
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("plugins/lorvex")

  @Test("the plugin's MCP config starts an executable launcher under the app's server name")
  func mcpConfigStartsTheLauncher() throws {
    let data = try Data(contentsOf: Self.pluginRoot.appendingPathComponent(".mcp.json"))
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let servers = try #require(root["mcpServers"] as? [String: Any])
    #expect(Array(servers.keys) == [LorvexProductMetadata.mcpServerName])
    let server = try #require(servers[LorvexProductMetadata.mcpServerName] as? [String: Any])
    let command = try #require(server["command"] as? String)
    let prefix = "${CLAUDE_PLUGIN_ROOT}/"
    #expect(command.hasPrefix(prefix))
    // A plugin's top-level `bin/` is put on the Bash tool's PATH, and the
    // launcher starts the production helper, so it must live elsewhere.
    #expect(!command.hasPrefix(prefix + "bin/"))
    let launcher = Self.pluginRoot.appendingPathComponent(String(command.dropFirst(prefix.count)))
    #expect(FileManager.default.isExecutableFile(atPath: launcher.path))
  }

  @Test("the launcher looks for the helper where and as the app bundles it")
  func launcherMatchesTheAppBundle() throws {
    let script = try String(
      contentsOf: Self.pluginRoot.appendingPathComponent("scripts/lorvex-mcp"), encoding: .utf8)
    let app = URL(fileURLWithPath: "/Applications/\(LorvexProductMetadata.appName).app")
    let helper = MCPHelperProbe.helperURL(bundleURL: app).path
    let relativeHelper = String(helper.dropFirst(app.path.count + 1))

    #expect(script.contains("helper=\"\(relativeHelper)\""))
    #expect(script.contains("\"\(app.path)\""))
    #expect(script.contains("\"$HOME/Applications/\(LorvexProductMetadata.appName).app\""))
    #expect(
      script.contains("kMDItemCFBundleIdentifier == '\(LorvexProductMetadata.bundleIdentifier)'"))
  }
}
