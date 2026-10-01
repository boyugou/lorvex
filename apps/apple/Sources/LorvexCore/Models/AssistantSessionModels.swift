import Foundation

/// An MCP client that has used this Mac's Lorvex helper, as Settings shows it.
///
/// The helper records the identity each client sends in its `initialize`
/// request and refreshes the time while the client works, so this answers
/// "is my assistant actually connected?" rather than only "can the helper run?".
public struct AssistantSessionRecord: Equatable, Sendable, Identifiable {
  /// `clientInfo.name`, the client's stable identifier, such as `claude-code`.
  public var clientName: String
  /// `clientInfo.title`, when the client sends one.
  public var clientTitle: String?
  /// `clientInfo.version`, when known.
  public var clientVersion: String?
  /// When the client last started a session or called a tool.
  public var lastActiveAt: Date

  public var id: String { clientName }

  public init(clientName: String, clientTitle: String?, clientVersion: String?, lastActiveAt: Date) {
    self.clientName = clientName
    self.clientTitle = clientTitle
    self.clientVersion = clientVersion
    self.lastActiveAt = lastActiveAt
  }

  /// The product name to show: a curated name for common clients (Claude
  /// Desktop identifies itself only as `claude-ai`), otherwise the client's own
  /// title, otherwise its identifier.
  public var displayName: String {
    Self.knownClientNames[clientName] ?? clientTitle ?? clientName
  }

  /// Display names for clients whose identifier is not a product name.
  static let knownClientNames: [String: String] = [
    "claude-ai": "Claude Desktop",
    "claude-code": "Claude Code",
    "codex-mcp-client": "Codex",
    "cursor-vscode": "Cursor",
  ]
}
