/// LorvexWorkflow — the cross-surface mutation executor and per-entity
/// workflow operations (task lifecycle, calendar event create/update, daily
/// review, habit operations, etc.) that compose LorvexStore
/// repositories + the LorvexDomain validators into the canonical mutations
/// every consumer surface (MCP host, app shell, CLI, sync apply) drives.
public enum LorvexWorkflow {
  /// Placeholder constant giving the target a single concrete public symbol.
  public static let version: UInt32 = 1
}
