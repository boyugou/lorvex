import LorvexCore

/// Hard cap on items per batch MCP tool call. Each batch tool runs its entire
/// payload inside one `BEGIN IMMEDIATE` write transaction, so an unbounded array
/// would hold the write lock long enough to starve CloudKit sync writes and the
/// UI's change-signal refreshes. Clients split larger sets across calls. The cap
/// is advertised in each batch tool's input schema (`maxItems`) and enforced in
/// the handler before the service is touched.
///
/// Re-exports ``LorvexBatchLimits/maxItems`` so the MCP and system-intent batch
/// paths share one cap.
enum MCPBatchLimits {
  static let maxItems = LorvexBatchLimits.maxItems
}
