import LorvexDomain

public struct RecentLogsSnapshot: Equatable, Sendable {
  public var entries: [RecentLogEntry]
  public var redactionApplied: Bool
  public var sourceCounts: [String: Int]

  public init(entries: [RecentLogEntry], redactionApplied: Bool, sourceCounts: [String: Int]) {
    self.entries = entries
    self.redactionApplied = redactionApplied
    self.sourceCounts = sourceCounts
  }
}

public struct RecentLogEntry: Identifiable, Equatable, Sendable {
  public var id: String
  public var timestamp: String?
  /// The stream this row came from: `error_log`, `ai_changelog`, or
  /// `sync_outbox`. Drives the MCP `get_recent_logs` `sources` filter and the
  /// per-stream `sourceCounts`.
  public var source: String
  /// Severity as the closed `DiagnosticLogLevel` set; `rawValue` is the exact
  /// DB/MCP-wire string (the `error_logs.level` value, or the synthesized level
  /// for `ai_changelog` / `sync_outbox` rows).
  public var level: DiagnosticLogLevel
  public var summary: String
  /// Optional sanitized side-channel (e.g. `tool=…` for a changelog row,
  /// `retry_count=…` for an outbox row, or an error_log's `details` column).
  public var details: String?
  /// The row's own fine-grained provenance — the `error_logs.source` column for
  /// `error_log` rows (e.g. `metrickit.crash`, `sync.pending_inbox`), which the
  /// stream-level ``source`` collapses to `error_log`. `nil` for the changelog /
  /// outbox streams, whose ``source`` already names their table.
  public var origin: String?

  public init(
    id: String, timestamp: String?, source: String, level: DiagnosticLogLevel, summary: String,
    details: String? = nil, origin: String? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.source = source
    self.level = level
    self.summary = summary
    self.details = details
    self.origin = origin
  }
}

/// A paginated, filtered slice of the merged diagnostic log stream
/// (`error_logs` + `ai_changelog` + `sync_outbox`).
public struct RecentLogsPage: Equatable, Sendable {
  /// The page of entries, already offset+limited and newest-first.
  public var entries: [RecentLogEntry]
  /// Count of entries matching the filters before pagination (bounded by the
  /// per-query scan cap), used to derive `truncated` / `next_offset`.
  public var totalMatching: Int
  /// Per-source counts over the full matching set (before pagination).
  public var sourceCounts: [String: Int]
  public var redactionApplied: Bool

  public init(
    entries: [RecentLogEntry], totalMatching: Int, sourceCounts: [String: Int],
    redactionApplied: Bool
  ) {
    self.entries = entries
    self.totalMatching = totalMatching
    self.sourceCounts = sourceCounts
    self.redactionApplied = redactionApplied
  }
}
