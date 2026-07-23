/// Canonical `provider_kind` allowlist for calendar provider links.
///
/// Centralizing the allowlist here keeps every surface that touches provider
/// links (IPC, MCP, platform writers, sync apply) on a single set. Only
/// `eventkit` has a shipping writer/refresh path, so it is the only kind a
/// caller may link — offering an unimplemented source (Google, Outlook, an ICS
/// feed) would strand the task on a link that can never resolve. The schema
/// CHECK constraints mirror this single-value allowlist (last-line defense for
/// direct SQL writers / future migrations); a real adapter is re-added here
/// deliberately — with its auth/refresh/error/deletion contract — alongside an
/// explicit numbered migration that widens the CHECK.
public enum ProviderKind {
  public static let eventkit = "eventkit"

  /// The kinds a caller may link to. Only `eventkit` ships a writer today.
  public static let allowlist: [String] = [
    eventkit
  ]

  /// Returns `true` if `kind` is in the canonical ``allowlist``. Matches
  /// case-sensitively; every kind is ASCII-lowercase by convention.
  public static func isAllowedProviderKind(_ kind: String) -> Bool {
    allowlist.contains(kind)
  }

  /// Stable comma-joined rendering of the allowlist for use in validation
  /// error messages. Same ordering as ``allowlist``.
  public static func allowlistDisplay() -> String {
    allowlist.joined(separator: ", ")
  }
}
