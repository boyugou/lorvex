import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-cycle sync retention: the post-apply garbage-collection sweep over the
/// sync bookkeeping tables.
///
/// ``runPostApplyGC(_:syncedAt:)`` runs the GC steps in a fixed order with
/// fixed retention windows. Every step is best-effort: a GC failure is logged to
/// `error_logs` and never aborts the apply of real inbound data.
public enum SyncRetention {
  /// Outbox retention window (days). Synced rows older than this are reaped.
  static let outboxRetentionDays: UInt32 = 7
  /// Conflict-log retention window (days).
  static let conflictLogRetentionDays: UInt32 = 30
  /// Diagnostics (`error_logs`) retention window (days) and absolute row cap.
  /// A persistent failure breadcrumbs on every sweep, so the table is bounded by
  /// both age and a hard most-recent-rows ceiling.
  static let errorLogRetentionDays: UInt32 = 30
  static let errorLogMaxRows: Int = 2000
  /// Absolute cap on never-pushed `sync_outbox` rows enforced by the sync-off
  /// maintenance sweep
  /// (``runLocalMaintenanceGC(_:syncedAt:includeActiveOutboxCap:)``). On a sync-off
  /// install every local mutation enqueues an outbox row with nothing draining
  /// it, and the synced-row GC never reaps a row that was never pushed, so the
  /// queue is otherwise unbounded. Deliberately generous: a user who enables
  /// sync later re-drains a realistic backlog in full; only a permanently
  /// sync-off install past the cap sheds its oldest queued changes (oldest
  /// first). Not applied on the live path — see
  /// ``LorvexSync/Outbox/gcUnsyncedBeyondCap(_:maxRows:)``.
  static let maintenanceOutboxUnsyncedRowCap: Int = 50_000

  // MARK: - Post-apply GC sweep (best-effort)

  /// Run the per-cycle retention GC sweep in the sync runtime's finalizer order.
  ///
  /// Steps, in order: outbox synced-row GC, tombstone GC, conflict-log GC,
  /// pending-inbox horizon GC, changelog retention GC, and the diagnostics
  /// (`error_logs`) age + row-cap GC. The ordinary tombstone step is deliberately
  /// a no-op: physical reclamation requires an exact CloudKit-confirmed cutoff
  /// bound into a successfully published immutable generation, never a local
  /// maintenance clock. The call remains in fixed order for call-site stability.
  ///
  /// Each step is best-effort: a failure is appended to `error_logs` at warn
  /// level and the remaining steps continue. This never throws — a GC error must
  /// not abort the apply of real inbound data nor trip the sync circuit breaker.
  ///
  /// Audit pruning advances the account frontier and enqueues CloudKit physical
  /// deletes; it never creates sync tombstones/delete envelopes.
  public static func runPostApplyGC(_ db: Database, syncedAt: String) {
    runStep(db, source: "sync.retention.outbox_gc") {
      try Outbox.gcSynced(db, retentionDays: outboxRetentionDays)
    }
    runStep(db, source: "sync.retention.tombstone_gc") {
      try Tombstone.gcTombstonesWatermark(db)
    }
    runStep(db, source: "sync.retention.conflict_log_gc") {
      try ConflictLog.gcConflicts(db, retentionDays: conflictLogRetentionDays)
    }
    // Drop pending-inbox envelopes whose FK parent never arrived within the
    // full-resync horizon (a device resyncs from scratch by then, so the orphan
    // can never apply incrementally) plus the quarantine blocklist on the same
    // horizon. Without this they accumulate unbounded — the GC was defined and
    // tested but never wired into the production sweep. Before the hard delete,
    // flag the loss (`reseed_required`) so a device more than the horizon behind
    // does not silently lose newer-peer records.
    //
    // Budget-exempt HOLD rows (schema-too-new / future-record / standing
    // aggregate refusal) are EXEMPT from the reap: the change token advanced
    // past those records at park time, so each row is the only local copy —
    // reaping it would silently lose the newer peer's state until the next
    // local edit overwrites it cluster-wide with a dominating HLC. They stay
    // until the build catches up or the invariant relaxes; growth is bounded by
    // coalescing superseded parked versions and observable via the retained-hold
    // breadcrumb below.
    if !hasGenerationSnapshotStaging(db) {
      runStep(db, source: "sync.retention.pending_inbox_gc") {
        try flagReseedRequiredIfExpiredPresent(
          db, horizonDays: SyncNaming.fullResyncHorizonDays, syncedAt: syncedAt)
        try coalesceSupersededHoldsPastHorizon(
          db, horizonDays: SyncNaming.fullResyncHorizonDays)
        let reaped = try PendingInbox.gcExpiredEntries(
          db, horizonDays: SyncNaming.fullResyncHorizonDays,
          exemptReasonSQL: PendingInboxDrain.budgetExemptHoldReasonSQL)
        try logRetainedHoldsPastHorizon(
          db, horizonDays: SyncNaming.fullResyncHorizonDays)
        return reaped
      }
    }

    // The changelog GC honours the user's `ai_changelog_retention_policy`. A
    // Missing/malformed preference means "maximum": the changelog keeps
    // everything under its absolute row-count safeguard.
    runStep(db, source: "sync.retention.changelog_gc") {
      try AuditRetention.gcChangelog(db)
    }
    // Bound the diagnostics table last (after the steps above may have logged
    // their own failures): age-trim plus a hard most-recent-rows cap so a
    // persistent error can't grow `error_logs` without limit.
    runStep(db, source: "sync.retention.error_logs_gc") {
      try ErrorLog.gc(db, retentionDays: errorLogRetentionDays, maxRows: errorLogMaxRows)
    }
    // Refresh planner statistics over the tables this connection has touched.
    // Plain `PRAGMA optimize` is self-throttling — it re-runs ANALYZE only when
    // a table's row count has drifted far from its recorded statistics — so a
    // per-sweep invocation stays cheap. The store-open path seeds the initial
    // statistics with `PRAGMA optimize=0x10002`; without either, the partial
    // and composite index fleet is costed from compiled-in defaults forever.
    runStep(db, source: "sync.retention.planner_optimize") {
      try db.execute(sql: "PRAGMA optimize")
      return 0
    }
  }

  // MARK: - Local maintenance sweep (best-effort, apply-independent)

  /// Run the retention GC on a local trigger, independent of an inbound apply.
  ///
  /// The post-apply sweep is not a sufficient production driver by itself: no
  /// inbound apply runs while sync is off, while iCloud is unavailable, while a
  /// durable pause is standing, or while cycle pacing suppresses a retry. This
  /// entry runs the same always-safe sweep from an app foreground / publish
  /// trigger so the changelog safeguard, diagnostics cap, synced-outbox age GC,
  /// and pending/conflict maintenance still run in every mode. Idempotent and
  /// best-effort; safe to call on every foreground.
  ///
  /// Expired audit rows produce durable account-scoped physical-delete work;
  /// sync inactivity never turns a privacy deletion into a local-only delete.
  ///
  /// When `includeActiveOutboxCap` is true it also bounds the never-pushed
  /// `sync_outbox` backlog
  /// (``LorvexSync/Outbox/gcUnsyncedBeyondCap(_:maxRows:)``), which the outbox's
  /// synced-row GC never touches. That cap is applied here and NOT in
  /// ``runPostApplyGC(_:syncedAt:)`` on purpose: the live sweep runs right
  /// after a full-resync backfill has legitimately filled the outbox with every
  /// live entity, so a count cap there could delete a just-enqueued row before it
  /// pushes. Callers MUST pass `false` whenever the configured mode is live,
  /// even if the current cycle is unavailable or paused: a full-resync backfill
  /// can legitimately exceed the cap and must survive until transport resumes.
  public static func runLocalMaintenanceGC(
    _ db: Database, syncedAt: String, includeActiveOutboxCap: Bool
  ) {
    runAlwaysSafeLocalMaintenanceGC(db, syncedAt: syncedAt)
    guard includeActiveOutboxCap else { return }
    runStep(db, source: "sync.retention.outbox_unsynced_cap") {
      try gcActiveOutboxAndFlagReseed(
        db, maxRows: maintenanceOutboxUnsyncedRowCap, syncedAt: syncedAt)
    }
  }

  /// Apply the intentionally lossy sync-off backlog cap without ever making the
  /// loss silent. Deleting an active outbox row means incremental transport no
  /// longer contains a complete history, so the reseed marker is committed in
  /// the same savepoint. The next live cycle then enumerates canonical live rows
  /// and every tombstone not covered by an authoritative generation cutoff
  /// before advancing its traversal.
  @discardableResult
  static func gcActiveOutboxAndFlagReseed(
    _ db: Database, maxRows: Int, syncedAt: String
  ) throws -> UInt64 {
    try StoreTransactions.withSavepoint(db, "outbox_cap_reseed") { db in
      guard !hasGenerationSnapshotStaging(db) else { return 0 }
      let deleted = try Outbox.gcUnsyncedBeyondCap(db, maxRows: maxRows)
      guard deleted > 0 else { return 0 }
      try SyncCheckpoints.set(
        db, key: SyncNaming.reseedRequiredCheckpointKey, value: "true")
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: "sync", entityId: SyncNaming.reseedRequiredCheckpointKey,
          winnerVersion: "", loserVersion: "", loserDeviceId: "",
          loserPayload: "capped_active_outbox_rows=\(deleted)",
          resolvedAt: syncedAt, resolutionType: ResolutionName.reseedRequired))
      return deleted
    }
  }

  /// Lossy maintenance cannot run while an immutable generation capture is in
  /// flight. That capture's final completeness proof and ready publication must
  /// observe one continuous transport-debt set. Safe age-based diagnostics and
  /// synced-row cleanup still run; pending/quarantine shedding and the active
  /// outbox cap resume after the staging singleton is finalized or discarded.
  private static func hasGenerationSnapshotStaging(_ db: Database) -> Bool {
    (try? Int.fetchOne(
      db, sql: "SELECT 1 FROM sync_generation_snapshot_staging LIMIT 1")) == 1
  }

  /// The local maintenance subset that is safe in every configured sync mode.
  /// In particular, this never sheds an active unsynced row merely because the
  /// queue is large; it only runs the same policy/age-based steps as the
  /// post-apply finalizer.
  public static func runAlwaysSafeLocalMaintenanceGC(
    _ db: Database, syncedAt: String
  ) {
    runPostApplyGC(db, syncedAt: syncedAt)
  }

  /// Detect pending-inbox or quarantine rows about to be reaped by the horizon
  /// GC and, when any exist, record the loss as a single `reseed_required`
  /// conflict-log row plus a `sync_checkpoints` marker the host can surface.
  /// Shares the timestamp boundaries
  /// ``PendingInbox/gcExpiredEntries(_:horizonDays:exemptReasonSQL:)`` deletes
  /// on, and counts OUT the by-design budget-exempt HOLD rows
  /// (``PendingInboxDrain/budgetExemptHoldReasonSQL``) exactly as the reap
  /// exempts them: a correct standing refusal or a not-yet-understood future
  /// record is retained, not lost, and it is not an orphan a full reseed could
  /// resolve — flagging it would only loop a futile reseed. Must run
  /// BEFORE the delete (afterward there is nothing to detect). A device this far
  /// behind on genuine orphan records cannot apply them incrementally, so the
  /// signal makes the sync transport run a full reseed at its next cycle start
  /// (and the host surface the state) instead of dropping newer-peer records
  /// silently.
  static func flagReseedRequiredIfExpiredPresent(
    _ db: Database, horizonDays: UInt32, syncedAt: String
  ) throws {
    let expiredPendingCount =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_pending_inbox
          WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
            AND NOT (\(PendingInboxDrain.budgetExemptHoldReasonSQL))
          """,
        arguments: ["-\(horizonDays) days"]) ?? 0
    let expiredQuarantineCount =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_quarantine_blocklist
          WHERE quarantined_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
          """,
        arguments: ["-\(horizonDays) days"]) ?? 0
    guard expiredPendingCount > 0 || expiredQuarantineCount > 0 else { return }

    try ConflictLog.logConflict(
      db,
      ConflictLog.Entry(
        entityType: "sync", entityId: SyncNaming.reseedRequiredCheckpointKey,
        winnerVersion: "", loserVersion: "", loserDeviceId: "",
        loserPayload:
          "expired_pending_inbox_rows=\(expiredPendingCount);"
          + "expired_quarantine_rows=\(expiredQuarantineCount)",
        resolvedAt: syncedAt, resolutionType: ResolutionName.reseedRequired))
    try SyncCheckpoints.set(db, key: SyncNaming.reseedRequiredCheckpointKey, value: "true")
  }

  /// Coalesce budget-exempt HOLD rows past the horizon down to the newest
  /// parked version per `(entity_type, entity_id)`.
  ///
  /// A hold is exempt from the horizon reap (its row is the only local copy of
  /// the record), so a future-build peer that keeps editing the same entity
  /// would otherwise accumulate one retained row per authored version forever.
  /// Under LWW the newest parked version dominates every older one of the same
  /// entity, so an expired hold with a strictly newer parked version is safe to
  /// drop. The superseding row must itself be a budget-exempt hold — an
  /// ordinary deferral of the same entity is reapable/quarantinable, so it
  /// cannot stand in as the durable copy. `envelope_version` stores canonical
  /// fixed-width HLC strings, so lexical `>` matches typed HLC order.
  static func coalesceSupersededHoldsPastHorizon(
    _ db: Database, horizonDays: UInt32
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_pending_inbox
        WHERE id IN (
          SELECT older.id FROM sync_pending_inbox AS older
          WHERE older.first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
            AND (\(PendingInboxDrain.budgetExemptHoldReasonSQL(column: "older.reason")))
            AND EXISTS (
              SELECT 1 FROM sync_pending_inbox AS newer
              WHERE newer.envelope_entity_type = older.envelope_entity_type
                AND newer.envelope_entity_id = older.envelope_entity_id
                AND newer.envelope_version > older.envelope_version
                AND (\(PendingInboxDrain.budgetExemptHoldReasonSQL(column: "newer.reason")))
            )
        )
        """,
      arguments: ["-\(horizonDays) days"])
  }

  /// `sync_checkpoints` key holding the retained-hold count last surfaced by
  /// ``logRetainedHoldsPastHorizon(_:horizonDays:)``, so the standing condition
  /// breadcrumbs `error_logs` once per count change instead of once per sweep.
  private static let retainedHoldCountCheckpointKey = "pending_inbox_hold_retained_count"

  /// Surface budget-exempt HOLD rows retained past the horizon as an
  /// error-level `error_logs` breadcrumb.
  ///
  /// A hold this old means the device has been running a build too old for a
  /// peer's records (or refusing an invariant-blocked envelope) for the whole
  /// retention window — user-actionable (update the app), and otherwise
  /// invisible since the hold neither raises `reseed_required` nor quarantines.
  /// Deduped on the retained count via ``retainedHoldCountCheckpointKey``: an
  /// unchanged count logs nothing, a changed non-zero count logs once.
  static func logRetainedHoldsPastHorizon(_ db: Database, horizonDays: UInt32) throws {
    let retained =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_pending_inbox
          WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
            AND (\(PendingInboxDrain.budgetExemptHoldReasonSQL))
          """,
        arguments: ["-\(horizonDays) days"]) ?? 0
    let prior = try SyncCheckpoints.get(db, key: retainedHoldCountCheckpointKey)
    let current = "\(retained)"
    guard current != (prior ?? "0") else { return }
    try SyncCheckpoints.set(db, key: retainedHoldCountCheckpointKey, value: current)
    guard retained > 0 else { return }
    ErrorLog.appendBestEffort(
      db, source: "sync.retention.pending_inbox_hold_retained",
      message:
        "\(retained) forward-compat/invariant HOLD row(s) retained past the "
        + "\(horizonDays)-day horizon — each is the only local copy of a newer "
        + "peer's record, awaiting an app update or invariant relaxation",
      details: nil, level: "error")
  }

  /// Run one best-effort GC step, logging any thrown error to `error_logs`.
  private static func runStep(
    _ db: Database, source: String, _ body: () throws -> Any
  ) {
    do {
      _ = try body()
    } catch {
      ErrorLog.appendBestEffort(
        db, source: source, message: "\(error)", details: nil, level: "warn")
    }
  }
}
