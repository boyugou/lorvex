import Foundation

/// Closed set of diagnostic-log severities: the `error_logs.level` CHECK
/// constraint, the MCP `get_recent_logs` tool's `level`/`levels` filter
/// schema, and every level-driven write-normalization or read-display
/// switch all agree on these four values. Raw values are the exact wire/DB
/// strings, so `rawValue` round-trips through storage and the MCP surface
/// unchanged.
public enum DiagnosticLogLevel: String, Sendable, CaseIterable {
  case debug
  case info
  case warn
  case error

  /// Case-insensitive parse that also accepts the `warning` alias for
  /// `.warn`, matching the caller input `LorvexStore.ErrorLog` has always
  /// tolerated on the write path. Returns `nil` for anything outside the
  /// closed set — the caller picks its own fallback rather than this
  /// initializer defaulting silently.
  public init?(lenient raw: String) {
    switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
    case "debug": self = .debug
    case "info": self = .info
    case "warn", "warning": self = .warn
    case "error": self = .error
    default: return nil
    }
  }
}
