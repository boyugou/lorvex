import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// S-2 full-resync backfill.
///
/// Re-enqueues both halves of this device's state into `sync_outbox` at their
/// EXISTING stored versions, through the normal coalesced outbox path, so a
/// freshly (re-)created CloudKit zone — or the empty zone of a newly signed-in
/// iCloud account — is repopulated with everything this device already holds:
///
/// - every live (non-tombstoned) entity, as an `upsert` envelope;
/// - every permanent alias in `sync_entity_redirects`, as its independent
///   absorbing `entity_redirect` upsert;
/// - every unconfirmed, still-within-window, or permanent-redirect-target
///   tombstone in `sync_tombstones`, as a `delete` envelope at the stored death
///   version.
///
/// The bug this closes: on zone re-create (`zoneNotFound` / `userDeletedZone`)
/// or account change, only the *inbound* checkpoint is reset, while the outbox
/// has GC'd every row older than its 7-day retention window — so every entity
/// last written more than 7 days ago is silently never re-pushed to the new
/// zone, and multi-device users lose data.
///
/// Re-pushing tombstones closes the mirror-image hole: a re-created zone holds
/// only live state, so a device that was offline and still holds a since-deleted
/// entity live would re-upload it as an `upsert`, and once the zone no longer
/// carries the `delete` barrier the gate no longer blocks it — the entity
/// RESURRECTS (a stale merge loser can likewise reappear). Re-pushing
/// each surviving tombstone as a `delete` re-asserts the death version so those
/// peers converge on the delete instead. An ordinary rebuild carries every
/// retained tombstone. A compaction transition may omit only an exact delete
/// whose CloudKit receipt is at or before the server-derived cutoff published in
/// that generation's seal and control record. Peers without a strictly later
/// completed-baseline server witness adopt that generation authoritatively, so an
/// omitted death marker cannot be defeated by stale local state.

/// Outcome of one full-resync backfill pass.
///
/// `emitted` counts fresh rows (live entities and tombstones) actually inserted
/// into `sync_outbox`. A row already represented by an equal/newer coalesced
/// entry is a successful no-op and counts as neither emitted nor skipped.
/// `skipped` counts the rows that SHOULD have been re-enqueued
/// but failed (each isolated in a SAVEPOINT and logged), with one entry in
/// `errors` per skipped row. A pass with `skipped > 0` re-asserted only part of
/// this device's state, so it SETS the durable `reseed_required` marker (and
/// leaves any already set) rather than clearing it — every recovery path that
/// runs the backfill then keeps an identity-gated retry trigger even when it
/// never pre-set the marker itself.
public struct FullResyncBackfillReport: Sendable, Equatable {
  /// Fresh rows inserted into `sync_outbox` (live upserts plus tombstone deletes).
  public var emitted: Int
  /// Rows that failed to re-enqueue and were skipped after SAVEPOINT rollback.
  public var skipped: Int
  /// One diagnostic message per skipped row (also appended to `error_logs`).
  public var errors: [String]

  public init(emitted: Int = 0, skipped: Int = 0, errors: [String] = []) {
    self.emitted = emitted
    self.skipped = skipped
    self.errors = errors
  }
}

extension Outbox {

  /// Re-enqueue every live entity across all synced entity types at its stored
  /// version. Returns a ``FullResyncBackfillReport`` with the emitted and
  /// skipped row counts. Requires an open transaction — the coalesced enqueue's
  /// SAVEPOINT contract assumes the connection is not in autocommit mode.
  ///
  /// Correctness invariants (a reviewer checks each):
  /// - **Stored version, not a fresh HLC.** Each entity is re-emitted at the
  ///   version currently on its row. A fresh HLC would LWW-inflate the row and
  ///   clobber a concurrent peer edit. The pipeline's version-stamp step is a
  ///   benign no-op here: the stamp equals the stored version, so the
  ///   `?1 > version` gate refuses the UPDATE and the row's version is unchanged.
  /// - **Coalesced path, never `synced_at = NULL`.** Routing through
  ///   ``OutboxEnqueue/enqueuePayloadUpsert(_:entityType:entityId:payload:context:)``
  ///   creates/coalesces a fresh unsynced row that `pendingOutbound` will pick
  ///   up. Resetting `synced_at` on an existing row would violate the partial
  ///   UNIQUE index and lose any entity whose outbox row was already GC'd.
  /// - **Idempotent.** A second pass re-enqueues at the same version, which the
  ///   coalesce LWW gate treats as stale and discards — no duplicate divergent
  ///   row, no stored-version change.
  ///
  /// `ai_changelog` is intentionally excluded: the append-only audit stream is
  /// not part of an ordinary union/reseed backfill, which could resurrect rows
  /// peers retired under their frontier. Unique candidate-zone construction is
  /// the separate exception: `AuditRetentionFrontier.generationSnapshotComponent`
  /// stages exactly the retained account/frontier set before the prior zone is
  /// retired. Audit has no `version` column and remains version-stamp-exempt.
  ///
  /// Per-entity failures are isolated in a SAVEPOINT and logged best-effort, so a
  /// single poison row (e.g. a tainted stored version) never blocks recovery of
  /// the rest — but every such skip is counted and reported, never silently
  /// absorbed into a "completed" result.
  @discardableResult
  public static func enqueueAllLiveForFullResync(
    _ db: Database, tombstoneCompactionCutoff: String? = nil
  ) throws -> FullResyncBackfillReport {
    if let tombstoneCompactionCutoff {
      guard let parsed = SyncTimestamp.parse(tombstoneCompactionCutoff),
        parsed.asString == tombstoneCompactionCutoff
      else { throw TombstoneConfirmationError.invalidCutoff }
    }
    let deviceId = try SyncCheckpoints.getOrCreateDeviceId(db)
    var report = FullResyncBackfillReport()
    // Topological order (lists before tasks, aggregate roots before edges and
    // children) so a backfill-repopulated zone delivers each row after the parent
    // it references — a peer applies without deferring the whole set into the
    // pending inbox. `allSyncableTypes` puts task before list, which would deliver
    // tasks before their list. `ai_changelog` is not in the topological order
    // (ordinary full-resync never re-pushes it); the guard below stays as defense.
    for entityType in EntityKind.topologicalEntityOrder {
      guard let kind = EntityKind.parse(entityType) else { continue }
      if kind == .aiChangelog { continue }
      if kind == .entityRedirect {
        try backfillRedirects(db, deviceId: deviceId, into: &report)
      } else if kind.isEdge {
        try backfillEdges(db, kind: kind, deviceId: deviceId, into: &report)
      } else {
        try backfillSimplePk(db, kind: kind, deviceId: deviceId, into: &report)
      }
    }
    // Live rows and independent alias upserts were enqueued above; ordinary
    // tombstone deletes are reconstructed last. CloudKit delivery order is not
    // semantic: the inbound driver establishes ordinary upserts, then ordinary
    // deaths, then explicit aliases. A page split remains safe because a missing
    // alias target defers durably until its live row or tombstone arrives.
    try backfillTombstones(
      db, deviceId: deviceId,
      tombstoneCompactionCutoff: tombstoneCompactionCutoff, into: &report)

    // The reseed marker is resolved last, in the caller's write transaction, so a
    // thrown backfill rolls back and leaves the prior marker state for a later
    // trigger to retry.
    //
    // Complete pass (nothing skipped): CLEAR the marker. A completed backfill IS
    // the reseed of last resort — this device re-asserted its full state and the
    // surrounding zone-recovery / account-adopt flow re-pulls the zone from a
    // reset checkpoint — so the `reseed_required` marker `SyncRetention` sets
    // before a horizon GC (which never clears on its own) is satisfied.
    //
    // Partial pass (skipped ≥ 1 row): SET the marker. This device re-asserted
    // only part of its state, so clearing would freeze a permanent partial
    // recovery as "done". SETTING it — not merely leaving a pre-existing one — is
    // what makes recovery durable for the paths that reach a backfill WITHOUT
    // `SyncRetention` having pre-set the marker: DB replacement, `zoneNotFound`
    // zone recreate, account first-run, and explicit account adoption all commit
    // their recovery (clear the checkpoint / lift the pause) once the enqueue
    // returns. Absent the marker a poison row's data would be silently dropped
    // from the (re-)created zone and never retried; with it, the identity-gated
    // `reseed_required` recovery arm re-runs this backfill each cycle until a
    // clean pass clears it. A persistent diagnostic records the partial pass.
    if report.skipped == 0 {
      try db.execute(
        sql: "DELETE FROM sync_checkpoints WHERE key = ?",
        arguments: [SyncNaming.reseedRequiredCheckpointKey])
    } else {
      try SyncCheckpoints.set(db, key: SyncNaming.reseedRequiredCheckpointKey, value: "true")
      ErrorLog.appendBestEffort(
        db, source: "sync.full_resync_backfill",
        message:
          "full-resync backfill emitted \(report.emitted) row(s) but skipped "
          + "\(report.skipped); the reseed_required marker is set so a later pass "
          + "retries the skipped rows",
        details: report.errors.joined(separator: "\n"), level: "error")
    }
    return report
  }

  // MARK: - Tombstones

  /// Re-enqueue every unconfirmed, still-within-window, or permanent-alias
  /// target delete. A cutoff is accepted only from the caller's ready-control
  /// CKRecord server timestamp; local `deleted_at` never participates. With no
  /// trusted cutoff, all rows are retained and emitted conservatively.
  ///
  /// Non-syncable / append-only tombstone rows (there should be none) are skipped
  /// defensively. If the dead identity also has a permanent alias, the narrow
  /// alias-source bypass emits its domain delete without remapping it onto the
  /// winner; the independent alias upsert was emitted immediately before this
  /// tombstone sweep.
  private static func backfillTombstones(
    _ db: Database, deviceId: String, tombstoneCompactionCutoff: String?,
    into report: inout FullResyncBackfillReport
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT tombstone.entity_type, tombstone.entity_id, tombstone.version
        FROM sync_tombstones AS tombstone
        WHERE ? IS NULL
          OR tombstone.cloud_confirmed_at IS NULL
          OR tombstone.cloud_confirmed_at > ?
          OR \(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL)
        """,
      arguments: [tombstoneCompactionCutoff, tombstoneCompactionCutoff])
    for row in rows {
      let entityType: String = row["entity_type"]
      let entityId: String = row["entity_id"]
      let version: String = row["version"]
      guard let kind = EntityKind.parse(entityType), kind.isSyncableKind,
        kind != .aiChangelog, kind != .entityRedirect,
        kind != .calendarSeriesCutover
      else { continue }
      if kind == .preference,
        PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
      {
        continue
      }
      try reenqueueTombstoneOne(
        db, kind: kind, entityId: entityId, version: version, deviceId: deviceId, into: &report)
    }
  }

  /// Re-enqueue one tombstone as a `delete` envelope, isolated in a SAVEPOINT so
  /// a single poison row can't abort the whole backfill. The entity row is gone,
  /// so a `delete` envelope needs only `entity_type` + `entity_id` + `version`;
  /// the minimal `{}` payload carries just the injected death version, which is
  /// all a peer's LWW-gated delete reads. The enqueue's own tombstone-mint step
  /// is a benign no-op — it re-asserts the same stored version, so the
  /// monotonicity gate refuses to overwrite. A thrown error is rolled back,
  /// logged best-effort, and counted
  /// as a skip in `report`.
  private static func reenqueueTombstoneOne(
    _ db: Database, kind: EntityKind, entityId: String, version: String, deviceId: String,
    into report: inout FullResyncBackfillReport
  ) throws {
    do {
      let emitted = try StoreTransactions.withSavepoint(
        db, "full_resync_tombstone"
      ) { db in
        if try EntityRedirect.get(
          db, sourceType: kind.asString, sourceId: entityId) != nil
        {
          return try OutboxEnqueue.enqueueAliasSourceDelete(
            db, entityType: kind.asString, entityId: entityId,
            version: version, deviceId: deviceId)
        }
        return try OutboxEnqueue.enqueuePayloadDeleteReportingInsertion(
          db, entityType: kind.asString, entityId: entityId, payload: .object([:]),
          context: OutboxWriteContext(version: version, deviceId: deviceId))
      }
      if emitted { report.emitted += 1 }
    } catch {
      let message =
        "skipped tombstone \(kind.asString)/\(entityId) at version \(version): \(error)"
      ErrorLog.appendBestEffort(
        db, source: "sync.full_resync_backfill", message: message, details: nil, level: "error")
      report.skipped += 1
      report.errors.append(message)
    }
  }

  // MARK: - Permanent aliases

  /// Re-enqueue every absorbing alias before loser-domain deletes. Aliases use
  /// their own opaque record namespace and never pass through the generic
  /// version-stamp pipeline because their source row is intentionally absent.
  private static func backfillRedirects(
    _ db: Database, deviceId: String, into report: inout FullResyncBackfillReport
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT source_type, source_id, target_id, version, created_at
        FROM sync_entity_redirects
        ORDER BY source_type, source_id COLLATE BINARY
        """)
    for row in rows {
      let sourceTypeRaw: String = row["source_type"]
      guard let sourceType = EntityKind.parse(sourceTypeRaw) else { continue }
      let record = EntityRedirect.Record(
        sourceType: sourceType, sourceId: row["source_id"], targetId: row["target_id"],
        version: row["version"], createdAt: row["created_at"])
      do {
        let emitted = try StoreTransactions.withSavepoint(
          db, "full_resync_entity_redirect"
        ) { db in
          try EntityRedirect.enqueue(db, record: record, deviceId: deviceId)
        }
        if emitted { report.emitted += 1 }
      } catch {
        let message =
          "skipped entity_redirect \(sourceTypeRaw)/\(record.sourceId) at version "
          + "\(record.version): \(error)"
        ErrorLog.appendBestEffort(
          db, source: "sync.full_resync_backfill", message: message,
          details: nil, level: "error")
        report.skipped += 1
        report.errors.append(message)
      }
    }
  }

  // MARK: - Simple-PK kinds

  /// Re-enqueue every row of a simple-PK syncable kind (aggregate roots,
  /// preference, task, independent children)
  /// at its stored `version`, reading the canonical payload through the same
  /// snapshot reader the normal write path uses. Every row in the table is a
  /// live entity — a delete removes the row and writes a tombstone, so no
  /// separate tombstone filter is needed.
  private static func backfillSimplePk(
    _ db: Database, kind: EntityKind, deviceId: String,
    into report: inout FullResyncBackfillReport
  ) throws {
    guard let (table, pk) = kind.tablePk else { return }
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(pk)
    let rows = try Row.fetchAll(db, sql: "SELECT \(pk) AS entity_id, version FROM \(table)")
    for row in rows {
      let entityId: String = row["entity_id"]
      if kind == .preference,
        PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
      {
        continue
      }
      let version: String = row["version"]
      try reenqueueOne(
        db, kind: kind, entityId: entityId, version: version, deviceId: deviceId, into: &report
      ) {
        try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: kind.asString, entityId: entityId)
      }
    }
  }

  // MARK: - Composite-PK edges

  /// Re-enqueue every row of a composite-PK edge kind at its stored `version`.
  /// Edges have no `tablePk`, so the snapshot reader cannot read them; each edge
  /// builds its canonical payload through the dedicated `PayloadLoaders` shape,
  /// exactly as the normal edge-enqueue path does.
  private static func backfillEdges(
    _ db: Database, kind: EntityKind, deviceId: String,
    into report: inout FullResyncBackfillReport
  ) throws {
    switch kind {
    case .taskTag:
      try backfillEdgeRows(
        db, kind: kind, deviceId: deviceId, into: &report,
        sql: "SELECT task_id AS a, tag_id AS b, version FROM task_tags"
      ) { db, a, b, _ in
        try PayloadLoaders.loadTaskTagSyncPayload(db, taskId: a, tagId: b)
      }
    case .taskDependency:
      try backfillEdgeRows(
        db, kind: kind, deviceId: deviceId, into: &report,
        sql: "SELECT task_id AS a, depends_on_task_id AS b, version, created_at FROM task_dependencies"
      ) { _, a, b, row in
        PayloadLoaders.taskDependencyPayload(
          taskId: a, dependsOnTaskId: b, version: row["version"], createdAt: row["created_at"])
      }
    case .taskCalendarEventLink:
      try backfillEdgeRows(
        db, kind: kind, deviceId: deviceId, into: &report,
        sql: "SELECT task_id AS a, calendar_event_id AS b, version FROM task_calendar_event_links"
      ) { db, a, b, _ in
        try PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(db, taskId: a, calendarEventId: b)
      }
    case .habitCompletion:
      try backfillEdgeRows(
        db, kind: kind, deviceId: deviceId, into: &report,
        sql: "SELECT habit_id AS a, completed_date AS b, version FROM habit_completions"
      ) { db, a, b, _ in
        try PayloadLoaders.loadHabitCompletionSyncPayload(db, habitId: a, completedDate: b)
      }
    default:
      return
    }
  }

  /// Enumerate an edge table (each row aliased to `a`, `b`, plus its raw columns)
  /// and re-enqueue each `{a}:{b}` edge at its stored `version`. `buildPayload`
  /// receives the connection, the two key halves, and the raw row.
  private static func backfillEdgeRows(
    _ db: Database, kind: EntityKind, deviceId: String,
    into report: inout FullResyncBackfillReport, sql: String,
    buildPayload: (Database, String, String, Row) throws -> JSONValue?
  ) throws {
    let rows = try Row.fetchAll(db, sql: sql)
    for row in rows {
      let a: String = row["a"]
      let b: String = row["b"]
      let version: String = row["version"]
      try reenqueueOne(
        db, kind: kind, entityId: "\(a):\(b)", version: version, deviceId: deviceId, into: &report
      ) {
        try buildPayload(db, a, b, row)
      }
    }
  }

  // MARK: - Per-entity isolation

  /// Re-enqueue one entity at `version`, isolated in a SAVEPOINT so a single
  /// poison row can't abort the whole backfill. A thrown error is rolled back to
  /// the savepoint and logged best-effort; it and a `nil` payload (the enumerated
  /// row exists but its loader produced nothing to re-push — a can't-happen
  /// inside the backfill's own transaction) are both counted as skips in
  /// `report`, so a partial pass is never mistaken for a completed reseed.
  private static func reenqueueOne(
    _ db: Database, kind: EntityKind, entityId: String, version: String, deviceId: String,
    into report: inout FullResyncBackfillReport,
    buildPayload: () throws -> JSONValue?
  ) throws {
    enum ReenqueueResult {
      case enqueued
      case alreadyPending
      case missingPayload
    }
    do {
      let result = try StoreTransactions.withSavepoint(
        db, "full_resync_entity"
      ) { db -> ReenqueueResult in
        guard let payload = try buildPayload() else { return .missingPayload }
        let inserted = try OutboxEnqueue.enqueuePayloadUpsertReportingInsertion(
          db, entityType: kind.asString, entityId: entityId, payload: payload,
          context: OutboxWriteContext(
            version: version, deviceId: deviceId))
        return inserted ? .enqueued : .alreadyPending
      }
      switch result {
      case .enqueued:
        report.emitted += 1
      case .alreadyPending:
        break
      case .missingPayload:
        let message =
          "skipped \(kind.asString)/\(entityId) at version \(version): payload loader "
          + "returned no payload for an enumerated row"
        ErrorLog.appendBestEffort(
          db, source: "sync.full_resync_backfill", message: message, details: nil, level: "error")
        report.skipped += 1
        report.errors.append(message)
      }
    } catch {
      let message = "skipped \(kind.asString)/\(entityId) at version \(version): \(error)"
      ErrorLog.appendBestEffort(
        db, source: "sync.full_resync_backfill", message: message, details: nil, level: "error")
      report.skipped += 1
      report.errors.append(message)
    }
  }
}
