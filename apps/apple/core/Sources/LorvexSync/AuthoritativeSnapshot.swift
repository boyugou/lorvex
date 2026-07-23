import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Crash-recoverable authoritative snapshot storage and replay.
///
/// Normal sync is LWW. This path is intentionally different: a device that has
/// crossed the offline recovery boundary has chosen a complete CloudKit snapshot
/// as truth. Pages are staged without touching live domain rows, and only a
/// successfully drained snapshot is reconciled. Known records are typed and
/// structural corruption fails closed; validated future records retain their
/// exact bounded raw envelope and participate in inventory without being applied.
/// Finalization is one SQLite transaction: stale queues are isolated, local rows
/// absent remotely are physically pruned child-first without synthesizing local
/// Deletes, tombstones, or outbound work, known rows
/// are force-replayed, future rows are parked, and the session disappears.
public enum AuthoritativeSnapshot {
  private static let singleton: Int64 = 1
  static let maxRecordNameBytes = 512
  static let adoptionFenceReason =
    "authoritative snapshot adoption: pre-adoption outbound state is superseded by the complete iCloud snapshot"

  private struct LocalEntity {
    var kind: EntityKind
    var entityId: String
    var version: String
  }

  // MARK: Session lifecycle

  public static func activeSession(_ db: Database) throws -> AuthoritativeSnapshotSession? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT session_token, account_identifier, zone_name, database_instance_id,
                 generation, generation_identifier, ready_witness, phase,
                 outbox_boundary_id, started_at,
                 (SELECT descriptor.tombstone_compaction_cutoff
                  FROM sync_cloudkit_generation_descriptor descriptor
                  WHERE descriptor.account_identifier = snapshot.account_identifier
                    AND descriptor.generation = snapshot.generation)
                   AS tombstone_compaction_cutoff
          FROM sync_authoritative_snapshot snapshot
          WHERE singleton = ?
          """,
        arguments: [singleton])
    else { return nil }
    let phaseRaw: String = row["phase"]
    guard let phase = AuthoritativeSnapshotPhase(rawValue: phaseRaw) else {
      throw AuthoritativeSnapshotError.noActiveSession
    }
    let boundary = try CloudTraversalBoundary(
      accountIdentifier: row["account_identifier"], zoneIdentifier: row["zone_name"],
      generation: row["generation"], generationIdentifier: row["generation_identifier"],
      readyWitness: row["ready_witness"],
      tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"])
    let sessionToken: String = row["session_token"]
    let databaseInstanceId: String = row["database_instance_id"]
    let outboxBoundaryId: Int64 = row["outbox_boundary_id"]
    let startedAt: String = row["started_at"]
    try CloudTraversalWitness.validateTraversalIdentifier(sessionToken)
    try CloudTraversalWitness.validateDatabaseInstanceIdentifier(databaseInstanceId)
    try CloudTraversalWitness.validateTimestamp(startedAt)
    return AuthoritativeSnapshotSession(
      sessionToken: sessionToken, boundary: boundary,
      databaseInstanceId: databaseInstanceId, phase: phase,
      outboxBoundaryId: outboxBoundaryId, startedAt: startedAt)
  }

  /// Start a durable intent. Repeating the same exact descriptor is idempotent;
  /// any descriptor change replaces the stale session and its inventory.
  @discardableResult
  public static func begin(
    _ db: Database, boundary: CloudTraversalBoundary, databaseInstanceId: String,
    preserveExistingLocalIntents: Bool = false
  ) throws -> AuthoritativeSnapshotSession {
    try CloudTraversalWitness.requireTransaction(db)
    try CloudTraversalWitness.validateDatabaseInstanceIdentifier(databaseInstanceId)
    try requireBoundDatabase(
      db, accountIdentifier: boundary.accountIdentifier,
      databaseInstanceId: databaseInstanceId)
    return try StoreTransactions.withSavepoint(db, "authoritative_snapshot_begin") { db in
      let current = try activeSession(db)
      if let current, current.boundary == boundary,
        current.databaseInstanceId == databaseInstanceId
      {
        return current
      }
      let sessionToken = UUID().uuidString.lowercased()
      let startedAt = SyncTimestampFormat.syncTimestampNow()
      if let current {
        // Replace the session row in place. Both fence ownership and the
        // session-token foreign key use ON UPDATE CASCADE, so only the stale
        // pre-session rows move to the new owner; active in-flight edits remain
        // active. Old staged inventory belongs to the superseded boundary and
        // must be removed before the session identity changes.
        try preserveStagedFutureProvenance(
          db, sessionToken: current.sessionToken)
        try db.execute(
          sql: "DELETE FROM sync_authoritative_snapshot_records WHERE session_id = ?",
          arguments: [current.sessionToken])
        try releaseOrphanedStagingFutureFences(db)
        try db.execute(
          sql: """
            UPDATE sync_authoritative_snapshot
            SET session_token = ?,
                account_identifier = ?, zone_name = ?, generation = ?,
                generation_identifier = ?, ready_witness = ?,
                database_instance_id = ?, phase = ?,
                staged_record_count = 0, staged_encoded_bytes = 0,
                started_at = ?
            WHERE session_token = ?
            """,
          arguments: [
            sessionToken, boundary.accountIdentifier, boundary.zoneIdentifier,
            boundary.generation, boundary.generationIdentifier, boundary.readyWitness,
            databaseInstanceId, AuthoritativeSnapshotPhase.preparing.rawValue,
            startedAt, current.sessionToken,
          ])
        return AuthoritativeSnapshotSession(
          sessionToken: sessionToken, boundary: boundary,
          databaseInstanceId: databaseInstanceId,
          phase: .preparing, outboxBoundaryId: current.outboxBoundaryId,
          startedAt: startedAt)
      }
      let outboxBoundaryId =
        try Int64.fetchOne(
          db, sql: "SELECT COALESCE(MAX(id), 0) FROM sync_outbox") ?? 0
      try db.execute(
        sql: """
          INSERT INTO sync_authoritative_snapshot
              (session_token, singleton, account_identifier, zone_name,
               generation, generation_identifier, ready_witness,
               database_instance_id, phase, outbox_boundary_id, started_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          sessionToken, singleton, boundary.accountIdentifier, boundary.zoneIdentifier,
          boundary.generation, boundary.generationIdentifier, boundary.readyWitness,
          databaseInstanceId,
          AuthoritativeSnapshotPhase.preparing.rawValue, outboxBoundaryId, startedAt,
        ])
      if !preserveExistingLocalIntents {
        // The first remote-authoritative session intent and its stale-queue
        // fence are one SQLite commit. A user/MCP write after this transaction is
        // therefore unambiguously post-session and remains active. An
        // inventory-only session requested by an incremental relational-root
        // deletion deliberately leaves every unrelated local intent active: the
        // complete snapshot supplies graph context, not authority to discard
        // otherwise valid local writes.
        _ = try Outbox.quarantineAllPending(
          db, error: adoptionFenceReason,
          authoritativeSessionToken: sessionToken)
      }
      return AuthoritativeSnapshotSession(
        sessionToken: sessionToken, boundary: boundary, databaseInstanceId: databaseInstanceId,
        phase: .preparing, outboxBoundaryId: outboxBoundaryId, startedAt: startedAt)
    }
  }

  /// Discard all staged pages and return an existing session to `preparing`.
  /// Used when the transport's zone/token is invalidated mid-snapshot.
  @discardableResult
  public static func restart(
    _ db: Database, databaseInstanceId: String
  ) throws -> AuthoritativeSnapshotSession {
    try CloudTraversalWitness.requireTransaction(db)
    try CloudTraversalWitness.validateDatabaseInstanceIdentifier(databaseInstanceId)
    return try StoreTransactions.withSavepoint(db, "authoritative_snapshot_restart") { db in
      guard let session = try activeSession(db) else {
        throw AuthoritativeSnapshotError.noActiveSession
      }
      try requireBoundDatabase(
        db, accountIdentifier: session.accountIdentifier,
        databaseInstanceId: databaseInstanceId)
      try preserveStagedFutureProvenance(
        db, sessionToken: session.sessionToken)
      try db.execute(
        sql: "DELETE FROM sync_authoritative_snapshot_records WHERE session_id = ?",
        arguments: [session.sessionToken])
      try releaseOrphanedStagingFutureFences(db)
      let startedAt = SyncTimestampFormat.syncTimestampNow()
      try db.execute(
        sql: """
          UPDATE sync_authoritative_snapshot
          SET database_instance_id = ?, phase = ?, staged_record_count = 0,
              staged_encoded_bytes = 0, started_at = ?
          WHERE session_token = ?
          """,
        arguments: [
          databaseInstanceId, AuthoritativeSnapshotPhase.preparing.rawValue,
          startedAt, session.sessionToken,
        ])
      return AuthoritativeSnapshotSession(
        sessionToken: session.sessionToken, boundary: session.boundary,
        databaseInstanceId: databaseInstanceId,
        phase: .preparing, outboxBoundaryId: session.outboxBoundaryId,
        startedAt: startedAt)
    }
  }

  public static func markReady(_ db: Database, sessionToken: String) throws {
    try CloudTraversalWitness.requireTransaction(db)
    guard let session = try activeSession(db) else {
      throw AuthoritativeSnapshotError.noActiveSession
    }
    guard session.sessionToken == sessionToken else {
      throw AuthoritativeSnapshotError.sessionTokenMismatch
    }
    if session.phase == .ready { return }
    guard session.phase == .preparing else {
      throw AuthoritativeSnapshotError.wrongPhase(expected: .preparing, actual: session.phase)
    }
    try db.execute(
      sql: "UPDATE sync_authoritative_snapshot SET phase = ? WHERE session_token = ?",
      arguments: [AuthoritativeSnapshotPhase.ready.rawValue, sessionToken])
  }

  public static func cancel(_ db: Database) throws {
    try CloudTraversalWitness.requireTransaction(db)
    try StoreTransactions.withSavepoint(db, "authoritative_snapshot_cancel") { db in
      if let session = try activeSession(db) {
        try preserveStagedFutureProvenance(
          db, sessionToken: session.sessionToken)
        _ = try Outbox.releaseAuthoritativeAdoptionFences(
          db, authoritativeSessionToken: session.sessionToken)
      }
      try db.execute(
        sql: "DELETE FROM sync_authoritative_snapshot WHERE singleton = ?", arguments: [singleton])
      try releaseOrphanedStagingFutureFences(db)
    }
  }

  // MARK: Page staging

  /// Stage one fetched page before its CloudKit token may advance. Re-delivery
  /// replaces the same record name; CloudKit-level physical deletions remove a
  /// record staged by an earlier page/change.
  public static func stagePage(
    _ db: Database, records: [AuthoritativeSnapshotRemoteRecord],
    deletedRecordNames: [String], sessionToken: String
  ) throws {
    try CloudTraversalWitness.requireTransaction(db)
    try StoreTransactions.withSavepoint(db, "authoritative_snapshot_stage_page") { db in
      try stagePageInsideSavepointBounded(
        db, records: records, deletedRecordNames: deletedRecordNames,
        sessionToken: sessionToken)
    }
  }

  // MARK: Atomic reconciliation

  /// Reconcile a completely drained staged snapshot inside the caller's write
  /// transaction. The caller owns queue quarantine and account/epoch checkpoint
  /// updates in the same transaction.
  public static func finalize(
    _ db: Database, registry: EntityApplierRegistry, hlc: HlcSession, deviceId: String,
    sessionToken expectedSessionToken: String,
    databaseInstanceId expectedDatabaseInstanceId: String
  ) throws -> AuthoritativeSnapshotReport {
    try CloudTraversalWitness.requireTransaction(db)
    return try StoreTransactions.withSavepoint(db, "authoritative_snapshot_finalize") { db in
      try finalizeInsideSavepoint(
        db, registry: registry, hlc: hlc, deviceId: deviceId,
        sessionToken: expectedSessionToken,
        databaseInstanceId: expectedDatabaseInstanceId)
    }
  }

  private static func finalizeInsideSavepoint(
    _ db: Database, registry: EntityApplierRegistry, hlc: HlcSession, deviceId: String,
    sessionToken expectedSessionToken: String,
    databaseInstanceId expectedDatabaseInstanceId: String
  ) throws -> AuthoritativeSnapshotReport {
    guard let session = try activeSession(db) else {
      throw AuthoritativeSnapshotError.noActiveSession
    }
    guard session.phase == .pulling else {
      throw AuthoritativeSnapshotError.wrongPhase(expected: .pulling, actual: session.phase)
    }
    if session.sessionToken != expectedSessionToken {
      throw AuthoritativeSnapshotError.sessionTokenMismatch
    }
    if session.databaseInstanceId != expectedDatabaseInstanceId {
      throw AuthoritativeSnapshotError.databaseInstanceMismatch
    }

    let stagedRows = try Row.fetchAll(
      db,
      sql: """
          SELECT record_name, state, envelope, server_modified_at
          FROM sync_authoritative_snapshot_records
          WHERE session_id = ?
          ORDER BY record_name
        """,
      arguments: [session.sessionToken])
    try validateStagingAccounting(db, sessionToken: session.sessionToken, rows: stagedRows)
    var corrupt = 0
    var remoteEnvelopes: [SyncEnvelope] = []
    var remoteFutureRecords: [RawEnvelopeFields] = []
    var remoteTypedFutureRecords: [SyncEnvelope] = []
    var remoteRecordNames = Set<String>()
    var serverModifiedAtByRecordName: [String: String] = [:]
    let decoder = JSONDecoder()
    for row in stagedRows {
      let recordName: String = row["record_name"]
      let stateRaw: String = row["state"]
      guard let state = AuthoritativeSnapshotRecordState(rawValue: stateRaw) else {
        throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: recordName)
      }
      remoteRecordNames.insert(recordName)
      if let serverModifiedAt: String = row["server_modified_at"] {
        guard let parsed = SyncTimestamp.parse(serverModifiedAt),
          parsed.asString == serverModifiedAt
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: recordName)
        }
        serverModifiedAtByRecordName[recordName] = serverModifiedAt
        try Tombstone.observeTrustedServerTime(
          db, accountIdentifier: session.accountIdentifier,
          serverTime: serverModifiedAt)
      }
      switch state {
      case .unknown:
        guard let wireJSON: String = row["envelope"],
          let data = wireJSON.data(using: .utf8),
          let raw = try? decoder.decode(RawEnvelopeFields.self, from: data),
          case .success = raw.validate(),
          SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId) == recordName
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: recordName)
        }
        remoteFutureRecords.append(raw)
      case .corrupt:
        corrupt += 1
      case .decoded:
        guard let raw: String = row["envelope"],
          let data = raw.data(using: .utf8),
          let envelope = try? decoder.decode(SyncEnvelope.self, from: data),
          case .success = envelope.validate(),
          SyncRecordName.opaque(
            entityType: envelope.entityType.asString, entityId: envelope.entityId) == recordName
        else {
          throw AuthoritativeSnapshotError.malformedStagedEnvelope(recordName: recordName)
        }
        if futureDeferralReason(for: envelope) != nil {
          remoteTypedFutureRecords.append(envelope)
        } else {
          remoteEnvelopes.append(envelope)
        }
      }
    }
    guard corrupt == 0 else {
      throw AuthoritativeSnapshotError.unrecognizedRecords(unknown: 0, corrupt: corrupt)
    }

    // `inbox` is a relational invariant and the fallback for every task. A
    // rebuilt Lorvex zone must contain its record identity; complete absence is
    // an incomplete/corrupt snapshot. A crafted peer may nevertheless have
    // replaced that record with a valid Delete envelope. Accept that recognized
    // shape here only so typed replay can reject the deletion and atomically
    // enqueue a dominating canonical upsert — requiring an upsert at validation
    // time would leave the snapshot permanently poisoned with no recovery path.
    let hasRequiredInboxRecord = remoteRecordNames.contains(
      SyncRecordName.opaque(entityType: EntityName.list, entityId: "inbox"))
    guard hasRequiredInboxRecord else {
      throw AuthoritativeSnapshotError.missingRequiredInbox
    }

    var remoteFutureVersions: [String: Hlc] = [:]
    for raw in remoteFutureRecords {
      remoteFutureVersions[
        SyncRecordName.opaque(entityType: raw.entityType, entityId: raw.entityId)
      ] = try Hlc.parseCanonical(raw.version)
    }
    for envelope in remoteTypedFutureRecords {
      remoteFutureVersions[
        SyncRecordName.opaque(
          entityType: envelope.entityType.asString, entityId: envelope.entityId)
      ] = envelope.version
    }
    try FutureRecordHold.prepareForAuthoritativeSnapshot(
      db, remoteFutureVersions: remoteFutureVersions,
      outboxBoundaryId: session.outboxBoundaryId)

    // Session creation atomically fenced only the pre-session queue. Any active
    // rows now present were authored while the remote snapshot was in flight and
    // are genuine user/MCP intent. Capture and temporarily remove their unique
    // outbox slots, discard only the old session fences, adopt the complete
    // remote baseline, then re-stamp/replay those intents on top below.
    let capturedLocalIntents = try capturePostSessionLocalIntents(
      db, accountIdentifier: session.accountIdentifier,
      outboxBoundaryId: session.outboxBoundaryId)
    let remoteLiveRecordNames = Set(
      remoteEnvelopes.lazy
        .filter { $0.operation == .upsert }
        .map {
          SyncRecordName.opaque(
            entityType: $0.entityType.asString, entityId: $0.entityId)
        })
    let localIntents = try includingAbsentAuthoritativeDependencies(
      db, intents: capturedLocalIntents,
      authoritativeLiveRecordNames: remoteLiveRecordNames,
      authoritativeUnresolvedRecordNames: Set(remoteFutureVersions.keys),
      deviceId: deviceId)
    let remoteInventory = try AuthoritativeSnapshotInventory(
      remoteEnvelopes: remoteEnvelopes, allRecordNames: remoteRecordNames,
      localIntents: localIntents)
    let protectedRecordNames = Set(localIntents.map(\.recordName))
    try discardCapturedIntentQueueRows(db, intents: localIntents)
    _ = try Outbox.releaseAuthoritativeAdoptionFences(
      db, authoritativeSessionToken: session.sessionToken)

    let localBefore = try liveEntities(db)
    let missing = localBefore.filter {
      let recordName = SyncRecordName.opaque(
        entityType: $0.kind.asString, entityId: $0.entityId)
      return !remoteRecordNames.contains(recordName)
        && !protectedRecordNames.contains(recordName)
    }
    // `ai_changelog` is synced but intentionally has no LWW `version` column, so
    // it cannot participate in `liveEntities`. It is still part of the complete
    // remote inventory: a canonical local audit row absent from CloudKit belongs
    // to the superseded history and must not survive adoption. Delete it locally
    // without authoring a new barrier because the authoritative zone already has
    // no record to overwrite. Staged audit records are handled by the typed replay
    // (including the local retention horizon) below.
    let missingAuditIds = try auditIDsInWorkingSet(
      db, accountIdentifier: session.accountIdentifier
    ).filter {
      let recordName = SyncRecordName.opaque(
        entityType: EntityName.aiChangelog, entityId: $0)
      return !remoteRecordNames.contains(recordName)
        && !protectedRecordNames.contains(recordName)
    }

    // A complete remote inventory supersedes the old local death ledger just as
    // it supersedes old live rows. Rebuild only the barriers still justified by
    // remote Delete envelopes, synthetic remote-absence deletes, and the
    // post-session local Delete intents replayed below. Otherwise a later full
    // resync could publish an absent-remote stale tombstone back into the zone.
    let futureHeldLocalTombstones = try futureHeldPostSessionTombstones(
      db, intents: localIntents)
    try db.execute(sql: "DELETE FROM sync_tombstones")
    try restoreFutureHeldPostSessionTombstones(
      db, tombstones: futureHeldLocalTombstones)
    // Permanent aliases are authoritative zone state too. Rebuild the ledger
    // only from independent remote `entity_redirect` records plus post-session
    // local alias intents captured above. Keeping a pre-session local-only alias
    // would silently remap future writes despite the adopted zone never having
    // agreed to that identity merge.
    try db.execute(sql: "DELETE FROM sync_entity_redirects")

    // Deferred envelopes and forward-compat shadows describe the pre-adoption
    // history. Every understood current record is staged above and replayed
    // below, so retaining those old retry lanes could resurrect state after the
    // snapshot commits. Replaying the staged snapshot rebuilds any shadow still
    // required by a newer payload generation.
    try db.execute(sql: "DELETE FROM sync_pending_inbox")
    try db.execute(sql: "DELETE FROM sync_quarantine_blocklist")
    try db.execute(sql: "DELETE FROM sync_payload_shadow")
    // List-fallback re-emit claims belong to the superseded local history. They
    // must not suppress a repair that the newly adopted remote snapshot needs.
    try db.execute(sql: "DELETE FROM sync_list_fallback_reemit_claims")

    var report = AuthoritativeSnapshotReport()
    for raw in remoteFutureRecords {
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)
      report.deferredUnknownTypeRecords += 1
    }
    for envelope in remoteTypedFutureRecords {
      guard let reason = futureDeferralReason(for: envelope) else {
        throw AuthoritativeSnapshotError.malformedStagedEnvelope(
          recordName: SyncRecordName.opaque(
            entityType: envelope.entityType.asString, entityId: envelope.entityId))
      }
      try PendingInboxDrain.enqueueDeferred(db, envelope: envelope, reason: reason)
      report.deferredUnknownTypeRecords += 1
    }
    let topoIndex = Dictionary(
      uniqueKeysWithValues: EntityKind.topologicalEntityOrder.enumerated().map { ($1, $0) })

    for entityId in missingAuditIds {
      try db.execute(sql: "DELETE FROM ai_changelog WHERE id = ?", arguments: [entityId])
      if db.changesCount > 0 {
        report.removedLocalEntities += 1
        report.changedEntityTypes.insert(.aiChangelog)
      }
    }

    // Children/edges before roots. Remote absence is already the complete
    // authoritative fact, so prune the superseded local copy without inventing
    // a new Delete envelope or tombstone. A synthetic dominating Delete could
    // race with a legitimate low-HLC upsert created after the snapshot's
    // terminal token and erase it fleet-wide. Explicit remote Delete envelopes
    // are replayed below and still rebuild their real tombstone barriers.
    for local in missing.sorted(by: { lhs, rhs in
      let li = topoIndex[lhs.kind.asString] ?? Int.max
      let ri = topoIndex[rhs.kind.asString] ?? Int.max
      if li != ri { return li > ri }
      return lhs.entityId < rhs.entityId
    }) {
      switch try reconcileLocalEntityForAuthoritativeAbsence(db, local: local) {
      case .removed:
        report.removedLocalEntities += 1
        report.changedEntityTypes.insert(local.kind)
      case .unchanged:
        break
      case .requiredTimezoneNeedsReassertion:
        try enqueueConvergenceReemit(
          db,
          target: AbsenceReemitTarget(
            entityType: local.kind.asString, entityId: local.entityId),
          hlc: hlc, deviceId: deviceId)
        report.changedEntityTypes.insert(.preference)
      case .requiredInboxNeedsReassertion:
        throw AuthoritativeSnapshotError.missingRequiredInbox
      }
    }

    // Force the staged current records through the normal typed appliers. The
    // temporary version reset and exact-identity tombstone removal are scoped to
    // this authoritative path only; ordinary inbound sync remains strict LWW.
    var delayedHardFkUpserts: [SyncEnvelope] = []
    for envelope in remoteEnvelopes.sorted(by: { lhs, rhs in
      let lhsPhase = lhs.entityType == .entityRedirect ? 2 : (lhs.operation == .delete ? 1 : 0)
      let rhsPhase = rhs.entityType == .entityRedirect ? 2 : (rhs.operation == .delete ? 1 : 0)
      if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }
      let li = topoIndex[lhs.entityType.asString] ?? Int.max
      let ri = topoIndex[rhs.entityType.asString] ?? Int.max
      if li != ri { return lhsPhase == 1 ? li > ri : li < ri }
      return lhs.entityId < rhs.entityId
    }) {
      let effectiveEnvelope = try effectiveAuthoritativeEnvelope(
        envelope, inventory: remoteInventory,
        authoritativeLiveRecordNames: remoteLiveRecordNames)
      if try stageDelayedHardFkUpsertIfNeeded(
        db, envelope: effectiveEnvelope, inventory: remoteInventory,
        delayed: &delayedHardFkUpserts)
      {
        continue
      }
      let rehomeCandidates = try ListDeleteRehome.captureRehomeCandidates(
        db, envelope: effectiveEnvelope)
      if effectiveEnvelope.entityType == .aiChangelog,
        effectiveEnvelope.operation == .upsert
      {
        // Append-only apply uses INSERT OR IGNORE. Remove the same-id local row
        // and its exact death barrier so the staged remote bytes, not a divergent
        // pre-adoption copy, reach the typed retention decision. Leaving the
        // tombstone in place would make `Apply` skip the upsert before
        // `ChangelogApplier` can reject an out-of-window row and queue its exact
        // zone CloudKit physical delete.
        try db.execute(
          sql: "DELETE FROM ai_changelog WHERE id = ?",
          arguments: [effectiveEnvelope.entityId])
        _ = try Tombstone.removeTombstone(
          db, entityType: effectiveEnvelope.entityType.asString,
          entityId: effectiveEnvelope.entityId)
      } else {
        _ = try Tombstone.removeTombstone(
          db, entityType: effectiveEnvelope.entityType.asString,
          entityId: effectiveEnvelope.entityId)
        _ = try ApplyLww.resetVersionForAuthoritativeSnapshot(
          db, entityType: effectiveEnvelope.entityType.asString,
          entityId: effectiveEnvelope.entityId)
      }
      let outcome = try Apply.applyEnvelope(
        db, registry: registry, envelope: effectiveEnvelope)
      switch outcome {
      case .applied:
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: outcome)
        report.replayedRemoteRecords += 1
        report.changedEntityTypes.insert(envelope.entityType)
        try ListDeleteRehome.reenqueueRehomed(
          db, taskIds: rehomeCandidates,
          mintVersion: { floor in
            hlc.nextVersionString(
              dominating: floor.map { max($0, envelope.version) } ?? envelope.version)
          },
          deviceId: deviceId)
        let target = try AbsencePreserveReemit.convergenceReemitTarget(
          db, envelope: envelope)
          ?? authoritativeNormalizationReemitTarget(
            original: envelope, effective: effectiveEnvelope)
        if let target
        {
          try enqueueConvergenceReemit(
            db, target: target, hlc: hlc, deviceId: deviceId)
        }
      case .remapped(_, let toEntityId):
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: outcome)
        report.replayedRemoteRecords += 1
        report.changedEntityTypes.insert(envelope.entityType)
        if let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
          db, envelope: envelope, toEntityId: toEntityId)
        {
          try enqueueConvergenceReemit(
            db, target: target, hlc: hlc, deviceId: deviceId)
        }
      case .upsertRejectedByRetention:
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: outcome)
        // The applier atomically queued the account-scoped CloudKit physical
        // delete and removed every local full-content copy.
        report.replayedRemoteRecords += 1
      case .repairRequired(let obligation):
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: envelope, outcome: outcome)
        try ApplyRepair.fulfill(
          db, obligation: obligation,
          mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
          deviceId: deviceId)
        report.replayedRemoteRecords += 1
        report.changedEntityTypes.insert(envelope.entityType)
        report.changedEntityTypes.formUnion(obligation.affectedEntityTypes)
      case .skipped(let reason, _):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: envelope.entityType.asString, entityId: envelope.entityId, reason: reason)
      case .deferred(let reason):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: envelope.entityType.asString, entityId: envelope.entityId,
          reason: reason.message)
      }
      if effectiveEnvelope.operation == .delete,
        let serverModifiedAt = serverModifiedAtByRecordName[
          SyncRecordName.opaque(
            entityType: envelope.entityType.asString, entityId: envelope.entityId)]
      {
        _ = try Tombstone.confirmCloudPresence(
          db,
          confirmation: Tombstone.CloudConfirmation(
            entityType: effectiveEnvelope.entityType.asString,
            entityId: effectiveEnvelope.entityId,
            version: effectiveEnvelope.version.description,
            confirmedAt: serverModifiedAt))
      }
    }

    try replayPostSessionLocalIntents(
      db, intents: localIntents, registry: registry, hlc: hlc,
      deviceId: deviceId, report: &report)

    for envelope in delayedHardFkUpserts {
      try reconcileDelayedHardFkUpsert(
        db, envelope: envelope, inventory: remoteInventory,
        registry: registry, hlc: hlc, deviceId: deviceId,
        report: &report)
    }

    ErrorLog.appendBestEffort(
      db, source: "sync.authoritative_snapshot.finalized",
      message:
        "authoritative CloudKit snapshot finalized: removed \(report.removedLocalEntities) "
        + "local-only stale synced row(s), replayed \(report.replayedRemoteRecords) current "
        + "remote record(s)",
      details: "account=\(session.accountIdentifier), zone=\(session.zoneName)", level: "warn")
    try cancel(db)
    return report
  }

  // MARK: Local inventory

  static func enqueueConvergenceReemit(
    _ db: Database, target: AbsenceReemitTarget, hlc: HlcSession,
    deviceId: String
  ) throws {
    let outcome = try ConvergenceEmitter.enqueueCurrentSnapshot(
      db, entityType: target.entityType, entityId: target.entityId,
      mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
      deviceId: deviceId)
    if outcome == .enqueued {
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target)
    }
  }

  private static func liveEntities(_ db: Database) throws -> [LocalEntity] {
    var result: [LocalEntity] = []
    for entityType in EntityKind.topologicalEntityOrder {
      guard let kind = EntityKind.parse(entityType) else { continue }
      if let (table, pk) = kind.tablePk {
        ValidationSQL.assertSafeSQLIdentifier(table)
        ValidationSQL.assertSafeSQLIdentifier(pk)
        let rows = try Row.fetchAll(
          db, sql: "SELECT \(pk) AS entity_id, version FROM \(table)")
        for row in rows {
          let entityId: String = row["entity_id"]
          if kind == .preference,
            PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
          {
            continue
          }
          result.append(
            LocalEntity(kind: kind, entityId: entityId, version: row["version"]))
        }
        continue
      }
      switch kind {
      case .taskTag:
        try appendEdges(
          db, kind: kind,
          sql: "SELECT task_id AS left_id, tag_id AS right_id, version FROM task_tags",
          into: &result)
      case .taskDependency:
        try appendEdges(
          db, kind: kind,
          sql:
            "SELECT task_id AS left_id, depends_on_task_id AS right_id, version FROM task_dependencies",
          into: &result)
      case .taskCalendarEventLink:
        try appendEdges(
          db, kind: kind,
          sql:
            "SELECT task_id AS left_id, calendar_event_id AS right_id, version FROM task_calendar_event_links",
          into: &result)
      case .habitCompletion:
        try appendEdges(
          db, kind: kind,
          sql:
            "SELECT habit_id AS left_id, completed_date AS right_id, version FROM habit_completions",
          into: &result)
      default:
        break
      }
    }
    return result
  }

  /// Remove one canonical row known absent from the complete authoritative
  /// inventory. This is deliberately lower-level than the ordinary Delete
  /// applier: authoritative absence must not mint local death state or outbound
  /// work. The caller orders children before roots so FK cascades cannot hide a
  /// count or leave an edge half-removed.
  private static func reconcileLocalEntityForAuthoritativeAbsence(
    _ db: Database, local: LocalEntity
  ) throws -> AuthoritativeAbsence.PruneResult {
    try AuthoritativeAbsence.prune(
      db, entityType: local.kind.asString, entityId: local.entityId)
  }

  private static func appendEdges(
    _ db: Database, kind: EntityKind, sql: String, into result: inout [LocalEntity]
  ) throws {
    for row in try Row.fetchAll(db, sql: sql) {
      let left: String = row["left_id"]
      let right: String = row["right_id"]
      result.append(
        LocalEntity(kind: kind, entityId: "\(left):\(right)", version: row["version"]))
    }
  }

  static func validateRecordName(_ recordName: String) throws {
    let count = recordName.utf8.count
    guard count > 0, count <= maxRecordNameBytes else {
      throw AuthoritativeSnapshotError.invalidRecordName
    }
  }
}
