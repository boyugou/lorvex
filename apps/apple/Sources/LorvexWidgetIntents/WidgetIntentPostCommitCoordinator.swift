import LorvexCore

/// Finishes the derived work that follows a committed interactive-widget
/// mutation without changing that mutation's outcome.
///
/// The database commit is the application result. Snapshot publication and
/// timeline reload are derived, retryable projections; a failure there must not
/// turn an already-applied habit increment into a failed App Intent that invites
/// the user to apply it again.
public struct WidgetIntentPostCommitCoordinator: Sendable {
  private let refresh: @Sendable (any LorvexCoreServicing) async throws -> Void
  private let broadcast: @Sendable () -> Void

  public init(
    refresh: @escaping @Sendable (any LorvexCoreServicing) async throws -> Void,
    broadcast: @escaping @Sendable () -> Void = {
      DatabaseChangeSignal.broadcastCommittedChange()
    }
  ) {
    self.refresh = refresh
    self.broadcast = broadcast
  }

  public static func live() -> WidgetIntentPostCommitCoordinator {
    WidgetIntentPostCommitCoordinator(
      refresh: { core in
        _ = try await WidgetIntentSnapshotRefresher.live().refresh(core: core)
      })
  }

  public func finish(core: any LorvexCoreServicing) async {
    // Signal immediately after the canonical commit. If this extension is
    // terminated while rebuilding the snapshot, an open app still converges by
    // re-reading the shared database.
    broadcast()
    do {
      try await refresh(core)
    } catch {
      // Preserve the committed mutation's success while retaining a local
      // diagnostic for the next app-side support read. The diagnostics writer is
      // itself best-effort and never becomes a second failure surface.
      try? await core.appendDiagnosticLog(
        source: "widget.intent.snapshot_refresh",
        level: "error",
        message: "Widget snapshot refresh failed after a committed mutation.",
        details: String(describing: error))
    }
  }
}
