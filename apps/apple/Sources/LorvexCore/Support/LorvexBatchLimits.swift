/// Shared cap on the number of items a single batch mutation accepts, applied
/// uniformly across the AI (MCP) and system-intent (Shortcuts/Siri) surfaces.
///
/// Each batch path runs its whole payload inside one `BEGIN IMMEDIATE` write
/// transaction, so an unbounded set would hold the write lock long enough to
/// starve CloudKit sync writes and the UI's change-signal refreshes. Clients
/// split larger sets across calls. This is the single source of truth for that
/// cap; surface-specific limit types re-export it so the two entry paths cannot
/// drift apart.
public enum LorvexBatchLimits {
  public static let maxItems = 100
}
