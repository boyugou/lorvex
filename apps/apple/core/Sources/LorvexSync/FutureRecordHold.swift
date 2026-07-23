import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Fail-closed ownership of a CloudKit identity occupied by data this build
/// cannot yet interpret.
///
/// The remote envelope remains durable in the pending inbox or an active
/// authoritative-snapshot staging row. Any already-queued local intent is kept
/// byte-for-byte in `sync_outbox`, but fenced from transport until a later build
/// fully understands a terminal envelope at the held version or above.
public enum FutureRecordHold {
  static let fenceError =
    "local intent fenced: the CloudKit identity contains a future-authored record"

  /// Durable resolution policy for the local mutation preserved behind an
  /// opaque CloudKit record.
  public enum Resolution: String, Sendable, Equatable {
    /// Ordinary inbound observation: resolve by the normal LWW result.
    case lww
    /// A complete authoritative snapshot proved this was stale pre-session
    /// state. The understood remote record must replace it regardless of HLC.
    case remoteAuthoritative = "remote_authoritative"
    /// The mutation was authored after authoritative adoption began. It must be
    /// replayed above the remote record once a build can understand that record.
    case localAfterFuture = "local_after_future"
  }

  enum PhysicalCloudDeletionOutcome: Sendable, Equatable {
    case unchanged
    case removedRemoteAuthoritative(EntityKind)
    case requiredInvariantNeedsReassertion(EntityKind, String)
    case requiresAuthoritativeSnapshot(EntityKind)
  }

  /// Exact post-session mutation retained until a later build understands the
  /// occupying CloudKit record and can mint a legal successor above it.
  public struct LocalIntentReplay: Sendable, Equatable {
    public var intent: SyncEnvelope
    public var remoteFloor: Hlc
    public var registerIntent: EntityRegisterIntent

    public init(
      intent: SyncEnvelope, remoteFloor: Hlc,
      registerIntent: EntityRegisterIntent = .none
    ) {
      self.intent = intent
      self.remoteFloor = remoteFloor
      self.registerIntent = registerIntent
    }
  }

  /// Classify a canonical external HLC against the static successor-headroom
  /// boundary. This deliberately does not consult wall time: ordinary bad-RTC
  /// or far-future peers remain accepted and editable via the detached HLC lane.
  public static func clockDeferralReason(for version: Hlc) -> DeferralReason? {
    guard !Hlc.hasOperationalWireSuccessor(after: version) else { return nil }
    return .operationallyUnusableHlc(
      remoteVersion: version,
      maximumOperationalPhysicalMs: Hlc.maxOperationalWirePhysicalMs)
  }

  /// Cheap common-path probe for outbound defense-in-depth. Correct insertion
  /// paths fence the unique outbox row immediately, so an active row needs the
  /// more expensive identity lookup only while future provenance exists in the
  /// pending inbox or any authoritative staging inventory is live. This avoids
  /// an N+1 query on every ordinary outbox flush.
  static func hasPotentialBlockingProvenance(_ db: Database) throws -> Bool {
    try Int.fetchOne(
      db,
      sql: """
        SELECT
          EXISTS(
            SELECT 1 FROM sync_pending_inbox
            WHERE \(PendingInboxDrain.futureRecordReasonSQL(column: "reason"))
          )
          OR EXISTS(SELECT 1 FROM sync_authoritative_snapshot_records)
        """) == 1
  }

  /// Maximum future-authored HLC currently known for this identity, including
  /// durable inbox provenance, active authoritative staging, and a permanent
  /// outbox fence whose staging session may already have ended.
  static func blockingVersion(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Hlc? {
    var maximum: Hlc?
    func observe(_ raw: String) throws {
      let value = try Hlc.parseCanonical(raw)
      maximum = maximum.map { max($0, value) } ?? value
    }

    let pending = try String.fetchAll(
      db,
      sql: """
        SELECT envelope_version
        FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          AND (\(PendingInboxDrain.futureRecordReasonSQL(column: "reason")))
        """,
      arguments: [entityType, entityId])
    for raw in pending { try observe(raw) }

    if let fenced: String = try String.fetchOne(
      db,
      sql: """
        SELECT future_record_version
        FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          AND disposition = ?
        LIMIT 1
        """,
      arguments: [
        entityType, entityId, Outbox.Disposition.futureRecordHold.rawValue,
      ])
    {
      try observe(fenced)
    }

    let recordName = SyncRecordName.opaque(entityType: entityType, entityId: entityId)
    let stagedRows = try Row.fetchAll(
      db,
      sql: """
        SELECT records.state, records.envelope
        FROM sync_authoritative_snapshot_records records
        JOIN sync_authoritative_snapshot snapshot
          ON snapshot.session_token = records.session_id
        WHERE records.record_name = ?
        """,
      arguments: [recordName])
    let decoder = JSONDecoder()
    for row in stagedRows {
      let state: String = row["state"]
      if state == AuthoritativeSnapshotRecordState.corrupt.rawValue { continue }
      guard let json: String = row["envelope"], let data = json.data(using: .utf8),
        let raw = try? decoder.decode(RawEnvelopeFields.self, from: data),
        raw.entityType == entityType, raw.entityId == entityId,
        case .success = raw.validate()
      else {
        throw DatabaseError(
          resultCode: .SQLITE_CORRUPT,
          message: "authoritative staging row for \(entityType)/\(entityId) is malformed")
      }
      let stagedVersion = try Hlc.parseCanonical(raw.version)
      if state == AuthoritativeSnapshotRecordState.unknown.rawValue
        || raw.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion
        || clockDeferralReason(for: stagedVersion) != nil
      {
        try observe(raw.version)
      }
    }
    return maximum
  }

  static func requireWriteAllowed(
    _ db: Database, entityType: String, entityId: String
  ) throws {
    if let held = try blockingVersion(db, entityType: entityType, entityId: entityId) {
      throw EnqueueError.futureRecordRequiresNewerApp(
        entityType: entityType, entityId: entityId, heldVersion: held.description)
    }
  }

  /// Preserve but permanently remove the active transport eligibility of any
  /// local intent for this identity. Repeated future observations monotonically
  /// raise the stored remote floor.
  static func fenceExistingLocalIntent(
    _ db: Database, entityType: String, entityId: String, heldVersion: String,
    replaceFutureFloor: Bool = false
  ) throws {
    let held = try Hlc.parseCanonical(heldVersion)
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, disposition, future_record_version,
                 future_record_resolution
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          LIMIT 1
          """,
        arguments: [entityType, entityId])
    else { return }
    let dispositionRaw: String? = row["disposition"]
    let disposition = dispositionRaw.flatMap(Outbox.Disposition.init(rawValue:))
    if disposition == .authoritativeAdoption { return }
    let priorRaw: String? = row["future_record_version"]
    let floor =
      try replaceFutureFloor
      ? held
      : priorRaw.map(Hlc.parseCanonical).map { max($0, held) } ?? held
    let priorResolutionRaw: String? = row["future_record_resolution"]
    let resolution = priorResolutionRaw.flatMap(Resolution.init(rawValue:)) ?? .lww
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = ?, consecutive_error_count = 0,
            last_error = ?, disposition = ?, next_retry_at = NULL,
            authoritative_session_token = NULL, future_record_version = ?,
            future_record_resolution = ?
        WHERE id = ? AND synced_at IS NULL
          AND (disposition IS NULL OR disposition IN (?, ?))
        """,
      arguments: [
        Outbox.maxRetries, Outbox.truncateOutboxLastError(fenceError),
        Outbox.Disposition.futureRecordHold.rawValue, floor.description,
        resolution.rawValue,
        row["id"] as Int64,
        Outbox.Disposition.retryWait.rawValue,
        Outbox.Disposition.futureRecordHold.rawValue,
      ])
  }

  /// A complete authoritative fetch observes the current value of one exact
  /// CloudKit record, not an append-only history maximum. Replace older parked
  /// versions and the outbox floor with that exact version; otherwise a stale
  /// higher historical hold can survive after the server's current value moved
  /// lower and no future envelope can ever release it.
  static func replaceAuthoritativeFutureProvenance(
    _ db: Database, entityType: String, entityId: String, heldVersion: String
  ) throws {
    _ = try Hlc.parseCanonical(heldVersion)
    try db.execute(
      sql: """
        DELETE FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          AND envelope_version <> ?
          AND (
            \(PendingInboxDrain.futureRecordReasonSQL(column: "reason"))
          )
        """,
      arguments: [entityType, entityId, heldVersion])
    try fenceExistingLocalIntent(
      db, entityType: entityType, entityId: entityId,
      heldVersion: heldVersion, replaceFutureFloor: true)
  }

  /// A terminal, fully-understood envelope proves that same-version and older
  /// future provenance is no longer opaque. Higher holds remain untouched.
  static func removeUnderstoodProvenance(
    _ db: Database, envelope: SyncEnvelope
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, envelope_version
        FROM sync_pending_inbox
        WHERE envelope_entity_type = ? AND envelope_entity_id = ?
          AND (\(PendingInboxDrain.futureRecordReasonSQL(column: "reason")))
        """,
      arguments: [envelope.entityType.asString, envelope.entityId])
    for row in rows {
      let held = try Hlc.parseCanonical(row["envelope_version"] as String)
      if held <= envelope.version {
        try PendingInbox.removePending(db, id: row["id"])
      }
    }
  }

  /// Before ordinary LWW sees a terminal envelope, make a stale pre-session
  /// row yield when an authoritative snapshot had already selected the remote
  /// future record as truth. The mutation is inside Apply's per-envelope
  /// savepoint, so a later validation/deferral rolls this reset back.
  static func prepareTerminalEnvelopeApply(
    _ db: Database, envelope: SyncEnvelope
  ) throws {
    guard
      let fence = try Row.fetchOne(
        db,
        sql: """
          SELECT future_record_version, future_record_resolution
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND disposition = ?
          LIMIT 1
          """,
        arguments: [
          envelope.entityType.asString, envelope.entityId,
          Outbox.Disposition.futureRecordHold.rawValue,
        ])
    else { return }
    let held = try Hlc.parseCanonical(fence["future_record_version"] as String)
    guard envelope.version >= held else { return }
    guard
      let resolution = Resolution(
        rawValue: fence["future_record_resolution"] as String)
    else { throw FutureRecordHoldError.invalidResolution }
    guard resolution == .remoteAuthoritative else { return }

    _ = try Tombstone.removeTombstone(
      db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    if envelope.entityType == .aiChangelog {
      try db.execute(
        sql: "DELETE FROM ai_changelog WHERE id = ?", arguments: [envelope.entityId])
    } else {
      _ = try ApplyLww.resetVersionForAuthoritativeSnapshot(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    }
  }

  /// Reconcile a preserved local intent after a terminal typed envelope catches
  /// up with its remote future floor. Ordinary holds use LWW; authoritative
  /// pre-session state is discarded; a post-session intent is returned as an
  /// explicit replay obligation so the host can mint a legal successor using
  /// its transaction HLC. Returning the obligation (instead of minting while
  /// the record is still operationally unusable) keeps snapshot finalization
  /// available even at the static HLC ceiling.
  @discardableResult
  public static func reconcileTerminalEnvelope(
    _ db: Database, envelope: SyncEnvelope, outcome: ApplyResult
  ) throws -> LocalIntentReplay? {
    try removeUnderstoodProvenance(db, envelope: envelope)
    guard
      let fence = try Row.fetchOne(
        db,
        sql: """
          SELECT id, entity_type, entity_id, operation, version,
                 payload_schema_version, payload, register_intent,
                 device_id, created_at,
                 future_record_version, future_record_resolution
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND disposition = ?
          LIMIT 1
          """,
        arguments: [
          envelope.entityType.asString, envelope.entityId,
          Outbox.Disposition.futureRecordHold.rawValue,
        ])
    else { return nil }
    let heldFloor = try Hlc.parseCanonical(fence["future_record_version"] as String)
    guard envelope.version >= heldFloor else { return nil }
    guard
      let resolution = Resolution(
        rawValue: fence["future_record_resolution"] as String)
    else { throw FutureRecordHoldError.invalidResolution }

    if resolution == .localAfterFuture {
      guard let kind = EntityKind.parse(fence["entity_type"] as String),
        kind == envelope.entityType,
        fence["entity_id"] as String == envelope.entityId,
        let operation = SyncOperation(rawValue: fence["operation"] as String),
        let version = try? Hlc.parseCanonical(fence["version"] as String)
      else { throw FutureRecordHoldError.invalidPreservedIntent }
      let schemaRaw: Int64 = fence["payload_schema_version"]
      guard schemaRaw >= 0, schemaRaw <= Int64(UInt32.max) else {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let intent = SyncEnvelope(
        entityType: kind, entityId: envelope.entityId, operation: operation,
        version: version, payloadSchemaVersion: UInt32(schemaRaw),
        payload: fence["payload"], deviceId: fence["device_id"])
      guard case .success = intent.validate() else {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let rawRegisterIntent: Int64 = fence["register_intent"]
      let registerIntent: EntityRegisterIntent
      do {
        registerIntent = try EntityRegisterIntent.validatedStored(
          rawValue: rawRegisterIntent, entityType: kind,
          operation: operation, payload: intent.payload)
      } catch {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [fence["id"] as Int64])
      return LocalIntentReplay(
        intent: intent, remoteFloor: max(heldFloor, envelope.version),
        registerIntent: registerIntent)
    }

    let localWinner: Hlc?
    if resolution == .lww,
      case .skipped(_, let winner) = outcome, let winner, winner > envelope.version
    {
      localWinner = winner
    } else {
      localWinner = nil
    }
    try db.execute(sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [fence["id"] as Int64])
    if let localWinner {
      _ = try rebuildCurrentCanonicalIntent(
        db, fence: fence, minimumVersion: localWinner,
        requireSurvivingRegisterIntent: false)
    } else if resolution == .lww, fence["register_intent"] as Int64 != 0 {
      switch outcome {
      case .applied, .repairRequired:
        // Both outcomes have materialized the grouped join at the original
        // identity. A repair obligation changes related or derived state after
        // this call, so first re-stage every byte-identical user-authored
        // register; the repair enqueue then coalesces over it and keeps exactly
        // the groups that still survive its fresh-HLC rewrite.
        _ = try rebuildCurrentCanonicalIntent(
          db, fence: fence, minimumVersion: nil,
          requireSurvivingRegisterIntent: true)
      case .remapped:
        // A permanent alias made the fenced source identity terminal. Its
        // register provenance cannot be transferred to the target: the target
        // may have won an aggregate merge with different register bytes. The
        // caller separately emits the canonical target as convergence state.
        break
      case .upsertRejectedByRetention:
        // Retention rejection is a terminal policy decision; no full-content
        // canonical row remains to carry user-authored register provenance.
        break
      case .skipped, .deferred:
        // A dominating local skip was handled by `localWinner` above. Exact or
        // older terminal skips do not prove that any fenced register survived,
        // and a deferral is never reconciled by the inbound callers.
        break
      }
    }
    return nil
  }

  /// CloudKit physically removed the record occupying this identity. There is
  /// no longer an opaque remote floor to fence an ordinary/post-session local
  /// intent behind, so re-arm that preserved outbox row. A pre-session intent
  /// explicitly subordinated to an authoritative snapshot remains discarded:
  /// the now-absent remote inventory is still authoritative for that lane.
  @discardableResult
  static func reconcilePhysicalCloudDeletion(
    _ db: Database, entityType: String, entityId: String
  ) throws -> PhysicalCloudDeletionOutcome {
    guard
      let fence = try Row.fetchOne(
        db,
        sql: """
          SELECT id, future_record_resolution
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND disposition = ?
          LIMIT 1
          """,
        arguments: [
          entityType, entityId,
          Outbox.Disposition.futureRecordHold.rawValue,
        ])
    else { return .unchanged }
    guard
      let resolution = Resolution(
        rawValue: fence["future_record_resolution"] as String)
    else { throw FutureRecordHoldError.invalidResolution }
    let outboxID: Int64 = fence["id"]
    if resolution == .remoteAuthoritative {
      guard let kind = EntityKind.parse(entityType) else {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      if try AuthoritativeAbsence.isPermanentRedirectTarget(
        db, entityType: entityType, entityId: entityId)
      {
        try deleteFence(db, outboxID: outboxID)
        return .requiredInvariantNeedsReassertion(kind, entityId)
      }
      let policy = try AuthoritativeAbsence.incrementalPhysicalDeletionPolicy(
        entityType: entityType, entityId: entityId)
      switch policy {
      case .exactPrune:
        let prune = try AuthoritativeAbsence.prune(
          db, entityType: entityType, entityId: entityId)
        try deleteFence(db, outboxID: outboxID)
        switch prune {
        case .unchanged:
          return .unchanged
        case .removed(let removedKind):
          return .removedRemoteAuthoritative(removedKind)
        case .requiredInboxNeedsReassertion:
          throw FutureRecordHoldError.invalidPreservedIntent
        case .requiredTimezoneNeedsReassertion:
          return .requiredInvariantNeedsReassertion(.preference, entityId)
        }
      case .reassertInvariant:
        try deleteFence(db, outboxID: outboxID)
        return .requiredInvariantNeedsReassertion(kind, entityId)
      case .requireCompleteInventory:
        // The exact stale pre-session intent is still superseded, but a single
        // CloudKit slot deletion cannot safely mutate this relational root. Keep
        // canonical state intact and let the durable complete-inventory session
        // decide every root, child, and edge together.
        try AuthoritativeAbsence.clearIdentityMetadata(
          db, entityType: entityType, entityId: entityId)
        try deleteFence(db, outboxID: outboxID)
        return .requiresAuthoritativeSnapshot(kind)
      }
    }
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = 0, consecutive_error_count = 0,
            last_retry_at = NULL, last_error = NULL,
            disposition = NULL, next_retry_at = NULL,
            authoritative_session_token = NULL,
            future_record_version = NULL, future_record_resolution = NULL,
            recovery_round = 0
        WHERE id = ? AND synced_at IS NULL AND disposition = ?
        """,
      arguments: [outboxID, Outbox.Disposition.futureRecordHold.rawValue])
    guard db.changesCount == 1 else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }
    return .unchanged
  }

  private static func deleteFence(_ db: Database, outboxID: Int64) throws {
    try db.execute(
      sql: "DELETE FROM sync_outbox WHERE id = ? AND synced_at IS NULL",
      arguments: [outboxID])
    guard db.changesCount == 1 else {
      throw FutureRecordHoldError.invalidPreservedIntent
    }
  }

  /// Fulfill a post-session future-held mutation after the terminal remote
  /// envelope has been consumed. The exact preserved payload is re-authored at
  /// a strict successor and sent through normal Apply + outbox paths.
  @discardableResult
  public static func fulfillLocalIntentReplay(
    _ db: Database, replay: LocalIntentReplay,
    registry: EntityApplierRegistry,
    mintVersion: @escaping (_ knownVersionFloor: Hlc?) -> String,
    deviceId: String
  ) throws -> Set<EntityKind> {
    var floor = max(replay.intent.version, replay.remoteFloor)
    if let localRaw = try ApplyLww.getLocalVersion(
      db, entityType: replay.intent.entityType.asString,
      entityId: replay.intent.entityId)
    {
      guard let local = try? Hlc.parseCanonical(localRaw) else {
        throw FutureRecordHoldError.invalidKnownVersion(localRaw)
      }
      floor = max(floor, local)
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: replay.intent.entityType.asString,
      entityId: replay.intent.entityId)
    {
      guard let death = try? Hlc.parseCanonical(tombstone.version) else {
        throw FutureRecordHoldError.invalidKnownVersion(tombstone.version)
      }
      floor = max(floor, death)
    }
    let rawVersion = mintVersion(floor)
    guard let version = try? Hlc.parseCanonical(rawVersion) else {
      throw FutureRecordHoldError.invalidMintedVersion(rawVersion)
    }
    guard version > floor else {
      throw FutureRecordHoldError.nonDominatingMint(
        minted: version.description, floor: floor.description)
    }
    let replayResult = try PostBaselineLocalIntentReplay.applyAndEnqueue(
      db, intent: replay.intent,
      registerIntent: replay.registerIntent,
      version: version, deviceId: deviceId, registry: registry)
    guard case .replayed(let successor, let outcome, let enqueued) = replayResult else {
      return []
    }
    var changedKinds: Set<EntityKind> = [successor.entityType]
    switch outcome {
    case .applied:
      guard enqueued else {
        throw FutureRecordHoldError.replayRejected("successor did not enter the outbox")
      }
    case .repairRequired(let obligation):
      try ApplyRepair.fulfill(
        db, obligation: obligation, mintVersion: mintVersion, deviceId: deviceId)
      changedKinds.formUnion(obligation.affectedEntityTypes)
    case .upsertRejectedByRetention:
      break
    case .skipped(let reason, _):
      throw FutureRecordHoldError.replayRejected(reason)
    case .deferred(let reason):
      throw FutureRecordHoldError.replayRejected(reason.message)
    case .remapped(_, let toEntityId):
      // The permanent alias is a valid terminal identity decision, not a replay
      // rejection. The remapped Apply stamped the canonical target with the
      // preserved intent's successor, but peers that know only the target need
      // that resolved current snapshot at a still-newer HLC. Re-emit through the
      // shared convergence funnel so aggregate merges and payload shadows, not
      // the stale source payload, define the outbound bytes.
      let emitted = try ConvergenceEmitter.enqueueCurrentSnapshot(
        db, entityType: successor.entityType.asString, entityId: toEntityId,
        mintVersion: mintVersion, deviceId: deviceId)
      guard emitted == .enqueued else {
        throw FutureRecordHoldError.replayRejected(
          "remapped replay target disappeared before convergence emission")
      }
    }
    return changedKinds
  }

  /// Resolve permanent fences at a complete authoritative boundary. A current
  /// remote future record keeps its fence. Any older pre-session intent is
  /// superseded by the adopted snapshot; a post-session intent whose opaque
  /// staged record was later replaced/deleted is rebuilt from canonical storage
  /// so it participates in the normal post-session replay.
  static func prepareForAuthoritativeSnapshot(
    _ db: Database, remoteFutureVersions: [String: Hlc], outboxBoundaryId: Int64
  ) throws {
    // A complete current-record inventory supersedes stale change-history holds.
    // Remove every parked future envelope whose CloudKit identity is no longer
    // occupied by a future record before rebuilding a post-session local intent;
    // otherwise `requireWriteAllowed` would correctly see the stale pending row
    // and block the authoritative recovery itself.
    let pendingFutureRows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, envelope_entity_type, envelope_entity_id, envelope_version
        FROM sync_pending_inbox
        WHERE \(PendingInboxDrain.futureRecordReasonSQL(column: "reason"))
        """)
    for row in pendingFutureRows {
      let entityType: String = row["envelope_entity_type"]
      let entityId: String = row["envelope_entity_id"]
      let recordName = SyncRecordName.opaque(entityType: entityType, entityId: entityId)
      let held = try Hlc.parseCanonical(row["envelope_version"] as String)
      if remoteFutureVersions[recordName] != held {
        try PendingInbox.removePending(db, id: row["id"])
      }
    }

    let fences = try Row.fetchAll(
      db,
      sql: """
        SELECT id, entity_type, entity_id, operation, version, device_id,
               created_at, future_record_version, future_record_resolution
        FROM sync_outbox
        WHERE synced_at IS NULL AND disposition = ?
        ORDER BY id
        """,
      arguments: [Outbox.Disposition.futureRecordHold.rawValue])
    for fence in fences {
      let entityType: String = fence["entity_type"]
      let entityId: String = fence["entity_id"]
      let recordName = SyncRecordName.opaque(entityType: entityType, entityId: entityId)
      guard
        let existingResolution = Resolution(
          rawValue: fence["future_record_resolution"] as String)
      else { throw FutureRecordHoldError.invalidPreservedIntent }
      if let currentFutureVersion = remoteFutureVersions[recordName] {
        // Once a snapshot has classified this row as a genuine local intent,
        // that provenance is monotonic across every later snapshot. A new
        // session's outbox boundary necessarily includes the old row; using
        // only its id would incorrectly downgrade it to stale remote-owned
        // state and eventually discard the user's edit.
        let resolution: Resolution =
          existingResolution == .localAfterFuture
            || (fence["id"] as Int64) > outboxBoundaryId
          ? .localAfterFuture : .remoteAuthoritative
        try db.execute(
          sql: """
            UPDATE sync_outbox
            SET future_record_resolution = ?, future_record_version = ?
            WHERE id = ? AND synced_at IS NULL AND disposition = ?
            """,
          arguments: [
            resolution.rawValue, currentFutureVersion.description,
            fence["id"] as Int64,
            Outbox.Disposition.futureRecordHold.rawValue,
          ])
        guard db.changesCount == 1 else {
          throw FutureRecordHoldError.invalidPreservedIntent
        }
        continue
      }
      let fenceId: Int64 = fence["id"]
      if existingResolution == .localAfterFuture || fenceId > outboxBoundaryId {
        // Preserve the exact queued operation/payload bytes. Reconstructing
        // from canonical storage is unsafe: lower understood inbound traffic or
        // aggregate side effects may have changed that row while it was fenced.
        // Clearing only the transport fence lets the normal snapshot capture
        // and replay this exact intent above the newly understood/absent truth.
        try db.execute(
          sql: """
            UPDATE sync_outbox
            SET retry_count = 0, last_retry_at = NULL, last_error = NULL,
                consecutive_error_count = 0, disposition = NULL,
                future_record_version = NULL, future_record_resolution = NULL,
                next_retry_at = NULL, recovery_round = 0
            WHERE id = ? AND synced_at IS NULL AND disposition = ?
            """,
          arguments: [
            fenceId, Outbox.Disposition.futureRecordHold.rawValue,
          ])
        guard db.changesCount == 1 else {
          throw FutureRecordHoldError.invalidPreservedIntent
        }
      } else {
        try db.execute(
          sql: "DELETE FROM sync_outbox WHERE id = ?", arguments: [fenceId])
      }
    }
  }

  /// Rebuild one preserved intent from live canonical state (or its canonical
  /// tombstone). Returns false when the authoritative baseline has already
  /// removed the identity, in which case there is no local intent left to emit.
  @discardableResult
  private static func rebuildCurrentCanonicalIntent(
    _ db: Database, fence: Row, minimumVersion: Hlc?,
    requireSurvivingRegisterIntent: Bool = false
  ) throws -> Bool {
    let entityType: String = fence["entity_type"]
    let entityId: String = fence["entity_id"]
    let deviceId: String = fence["device_id"]
    if let liveRaw = try ApplyLww.getLocalVersion(
      db, entityType: entityType, entityId: entityId),
      let live = try? Hlc.parseCanonical(liveRaw),
      minimumVersion.map({ live >= $0 }) ?? true
    {
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
      guard let kind = EntityKind.parse(entityType),
        let operation = SyncOperation(rawValue: fence["operation"] as String)
      else {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let preservedIntent: EntityRegisterIntent
      do {
        preservedIntent = try EntityRegisterIntent.validatedStored(
          rawValue: fence["register_intent"] as Int64,
          entityType: kind, operation: operation, payload: fence["payload"])
      } catch {
        throw FutureRecordHoldError.invalidPreservedIntent
      }
      let currentPayload = try SyncCanonicalize.canonicalizeJSON(payload)
      let registerIntent = preservedIntent.retainingUnchangedRegisters(
        existingPayload: fence["payload"], replacementPayload: currentPayload)
      if requireSurvivingRegisterIntent, registerIntent.isEmpty {
        return false
      }
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: entityType, entityId: entityId, payload: payload,
        context: OutboxWriteContext(
          version: live.description, deviceId: deviceId,
          registerIntent: registerIntent))
      return true
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: entityType, entityId: entityId),
      let death = try? Hlc.parseCanonical(tombstone.version),
      minimumVersion.map({ death >= $0 }) ?? true
    {
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: entityType, entityId: entityId,
        payload: .object(["version": .string(death.description)]),
        context: OutboxWriteContext(version: death.description, deviceId: deviceId))
      return true
    }

    // The append-only audit stream intentionally has no canonical `version`
    // column. Its preserved outbox HLC remains the ordering key, but payload
    // bytes are still rebuilt from the current row and today's schema.
    if entityType == EntityName.aiChangelog,
      let queued = try? Hlc.parseCanonical(fence["version"] as String),
      minimumVersion.map({ queued >= $0 }) ?? true,
      let payload = try? OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
    {
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: entityType, entityId: entityId, payload: payload,
        context: OutboxWriteContext(version: queued.description, deviceId: deviceId))
      return true
    }
    return false
  }
}

public enum FutureRecordHoldError: Error, Sendable, Equatable {
  case invalidResolution
  case invalidPreservedIntent
  case invalidKnownVersion(String)
  case invalidMintedVersion(String)
  case nonDominatingMint(minted: String, floor: String)
  case replayRejected(String)
}
