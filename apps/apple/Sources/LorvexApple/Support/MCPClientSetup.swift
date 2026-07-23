import Foundation
import LorvexCore

/// The connection details an external AI client needs to launch Lorvex's bundled
/// MCP host over stdio, plus ready-to-paste artifacts built from them.
///
/// Every MCP client reads its *own* config file — none reads a file Lorvex
/// writes — so the useful thing to hand the user is exactly what to paste into
/// their client (a JSON `mcpServers` entry), or a natural-language prompt their
/// assistant can apply to its own config. Both are derived from the bundled
/// helper's absolute path; the helper opens the single Lorvex-managed App Group
/// store on its own, so no environment override is advertised.
struct MCPClientSetup: Equatable, Sendable {
  /// The key the server entry is filed under in the client's config.
  let serverName: String
  /// Absolute path to the bundled `LorvexMCPHost` the client launches over stdio.
  let commandPath: String

  /// Resolves the live connection details from the bundled helper. The helper
  /// always opens the Lorvex-managed App Group store, so no environment is needed.
  static func current() -> MCPClientSetup {
    MCPClientSetup(
      serverName: LorvexProductMetadata.mcpServerName,
      commandPath: MCPHelperProbe.helperURL().path
    )
  }

  /// A JSON `mcpServers` entry for common JSON-config clients. Deterministic
  /// and valid JSON so it can be both displayed and pasted verbatim. `type:
  /// stdio` is included explicitly for clients that require transport selection.
  var jsonSnippet: String {
    let entry: [String: Any] = ["type": "stdio", "command": commandPath, "args": [String]()]
    let root: [String: Any] = ["mcpServers": [serverName: entry]]
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: root,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      ),
      let string = String(data: data, encoding: .utf8)
    else { return "" }
    return string
  }

  /// A prompt the user can paste into any AI assistant to have it add the server
  /// to its own configuration and verify the connection — the AI-native happy
  /// path that sidesteps per-client config formats.
  var setupPrompt: String {
    [
      "Please connect my Lorvex task manager to you as a local MCP server so you can read and manage my tasks.",
      "",
      "Add a stdio MCP server to your configuration:",
      "- name: \(serverName)",
      "- command: \(commandPath)",
      "- args: none",
      "",
      "After adding it and reloading your MCP servers, call the get_overview tool to confirm the connection works.",
    ].joined(separator: "\n")
  }
}
