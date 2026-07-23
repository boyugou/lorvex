import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Apply-pipeline error and result vocabulary plus the `apply_envelope` entry
/// point — the pipeline that processes a single inbound sync envelope.
///
/// The typed ``ApplyResult`` / ``ApplyError`` enums, the ``DeferralReason`` used
/// by the pending-inbox path, and the redirect-chain cap all live here because
/// they form one result-and-error vocabulary. The per-entity appliers
/// (aggregate / edge / child / tag / day_scoped / changelog) plug into
/// the dispatch seam in ``ApplyDispatch``; see ``EntityApplier`` and
/// ``EntityApplierRegistry``.

/// Typed reason for deferring an envelope to the pending inbox.
public enum DeferralReason: Sendable, Equatable {
  /// The envelope's payload_schema_version is too far ahead of local.
  case schemaTooNew(remoteVersion: UInt32, localVersion: UInt32)
  /// The envelope carries a canonical HLC that cannot safely become canonical
  /// local state yet. A bounded far-future value waits for wall time to enter
  /// the accepted skew window; the absolute HLC ceiling has no local successor
  /// and remains held until a later recovery policy can interpret it safely.
  case operationallyUnusableHlc(
    remoteVersion: Hlc, maximumOperationalPhysicalMs: UInt64)
  /// An audit upsert belongs to an account-relative retention generation whose
  /// frontier/policy has not yet been joined and authorized locally.
  case auditRetentionFrontierRefresh(requiredEpoch: Int64)
  /// A required foreign-key dependency is not yet present locally.
  case missingDependency(entityType: EntityKind, entityId: String)
  /// An aggregate-level invariant guard refused the envelope on the receiving
  /// device. Examples are the at-least-one-list rule and an aggregate merge an
  /// older runtime cannot perform without dropping future payload fields. The
  /// envelope sits in the pending inbox until a future apply pass can satisfy or
  /// understand the invariant.
  case aggregateInvariantBlocked(
    entityType: EntityKind, entityId: String, invariant: String)

  /// Stable substring the retention sweep matches against a stored
  /// `sync_pending_inbox.reason` to recognize a ``schemaTooNew`` HOLD — the head
  /// of its ``message``, so the two cannot drift.
  public static let schemaTooNewReasonMarker = "payload_schema_version"
  public static let operationallyUnusableHlcReasonMarker = "hlc_operational_hold"
  public static let auditRetentionFrontierReasonMarker = "audit_retention_frontier"
  /// Stable substring the retention sweep matches against a stored
  /// `sync_pending_inbox.reason` to recognize an ``aggregateInvariantBlocked``
  /// HOLD — the tail of its ``message``, so the two cannot drift.
  public static let aggregateInvariantBlockedReasonMarker =
    "will retry once the invariant relaxes"

  /// Human-readable description of this deferral reason.
  public var message: String {
    switch self {
    case .schemaTooNew(let remoteVersion, let localVersion):
      return
        "\(Self.schemaTooNewReasonMarker) \(remoteVersion) is too far ahead "
        + "(local max: \(localVersion))"
    case .operationallyUnusableHlc(let remoteVersion, let maximumOperationalPhysicalMs):
      return
        "\(Self.operationallyUnusableHlcReasonMarker) remote version "
        + "\(remoteVersion.description) has no strict successor inside the static "
        + "operational HLC boundary (physical_ms through "
        + "\(maximumOperationalPhysicalMs), counter through \(Hlc.maxCounter))"
    case .auditRetentionFrontierRefresh(let requiredEpoch):
      return
        "\(Self.auditRetentionFrontierReasonMarker) refresh required for epoch "
        + "\(requiredEpoch)"
    case .missingDependency(let entityType, let entityId):
      return "missing dependency: \(entityType.asString)/\(entityId)"
    case .aggregateInvariantBlocked(let entityType, let entityId, let invariant):
      return
        "aggregate invariant '\(invariant)' refused envelope for "
        + "\(entityType.asString)/\(entityId) — \(Self.aggregateInvariantBlockedReasonMarker)"
    }
  }
}

/// Result of applying a single sync envelope.
public enum ApplyResult: Sendable, Equatable {
  /// The envelope was applied successfully.
  case applied
  /// The inbound `ai_changelog` upsert was refused by the local retention
  /// policy/frontier. No audit row was stored; the applier atomically queued an
  /// exact-zone CloudKit physical delete and removed every local full-content
  /// copy.
  case upsertRejectedByRetention
  /// The addressed mutation was rejected to preserve a permanent local
  /// invariant, but merely skipping it would leave the shared record in a shape
  /// that poisons future sync. The host must fulfill this typed repair in the same
  /// transaction before advancing its CloudKit checkpoint.
  case repairRequired(ApplyRepairObligation)
  /// The envelope was skipped (local version is newer or equal).
  ///
  /// `winnerVersion` carries the typed ``Hlc`` that beat the envelope when the
  /// skip was driven by an LWW comparison (local-wins, tombstone-wins,
  /// redirect-target LWW). `nil` for skips that have no programmatic winner,
  /// such as local-only entity filters and already-tombstoned-delete no-ops.
  case skipped(reason: String, winnerVersion: Hlc?)
  /// The envelope was deferred to the pending inbox.
  case deferred(reason: DeferralReason)
  /// The envelope was remapped via a permanent entity redirect.
  case remapped(fromEntityId: String, toEntityId: String)
}

/// A convergence write that the apply engine cannot mint itself because it has
/// no device identity or HLC session. Hosts must fulfill the obligation atomically
/// with consuming the triggering envelope.
/// One concrete mutation needed to propagate calendar-partition cleanup back to
/// the shared CloudKit record set. Targets are canonical live identities; the
/// host mints a strict-successor HLC for each and routes it through the normal
/// outbox funnel.
public struct CalendarCleanupRepairTarget: Sendable, Equatable {
  public let entityType: EntityKind
  public let entityId: String
  public let operation: SyncOperation

  public init(entityType: EntityKind, entityId: String, operation: SyncOperation) {
    self.entityType = entityType
    self.entityId = entityId
    self.operation = operation
  }
}

/// One canonical mutation needed to converge a task lifecycle decision across
/// the task's independently-synced graph.
///
/// Task roots carry their grouped-register intent so repair can advance exactly
/// the derived registers. Related entities use a typed identity/operation plus
/// the highest row HLC observed before local cleanup; delete repairs need that
/// captured floor because the live row is gone by the time the host mints the
/// replacement tombstone.
public enum TaskGraphRepairTarget: Sendable, Equatable {
  case taskUpsert(taskId: String, registerIntent: TaskRegisterIntent)
  case relatedEntity(
    entityType: EntityKind, entityId: String, operation: SyncOperation,
    knownVersionFloor: Hlc?)

  public static func coalesced(_ targets: [TaskGraphRepairTarget]) -> [TaskGraphRepairTarget] {
    var taskIntents: [String: TaskRegisterIntent] = [:]
    struct RelatedIdentity: Hashable {
      let entityType: EntityKind
      let entityId: String
    }
    var related: [RelatedIdentity: (operation: SyncOperation, floor: Hlc?)] = [:]

    for target in targets {
      switch target {
      case .taskUpsert(let taskId, let registerIntent):
        taskIntents[taskId, default: []].formUnion(registerIntent)
      case .relatedEntity(let entityType, let entityId, let operation, let floor):
        let identity = RelatedIdentity(entityType: entityType, entityId: entityId)
        guard let existing = related[identity] else {
          related[identity] = (operation, floor)
          continue
        }
        let joinedOperation: SyncOperation =
          existing.operation == .delete || operation == .delete ? .delete : .upsert
        let joinedFloor: Hlc?
        switch (existing.floor, floor) {
        case (.some(let lhs), .some(let rhs)): joinedFloor = max(lhs, rhs)
        case (.some(let value), .none), (.none, .some(let value)): joinedFloor = value
        case (.none, .none): joinedFloor = nil
        }
        related[identity] = (joinedOperation, joinedFloor)
      }
    }

    let tasks = taskIntents.keys.sorted().map {
      TaskGraphRepairTarget.taskUpsert(
        taskId: $0, registerIntent: taskIntents[$0] ?? [])
    }
    let sortedRelatedIdentities = related.keys.sorted {
      ($0.entityType.asString, $0.entityId) < ($1.entityType.asString, $1.entityId)
    }
    var entities: [TaskGraphRepairTarget] = []
    entities.reserveCapacity(sortedRelatedIdentities.count)
    for identity in sortedRelatedIdentities {
      guard let mutation = related[identity] else { continue }
      entities.append(
        .relatedEntity(
          entityType: identity.entityType, entityId: identity.entityId,
          operation: mutation.operation, knownVersionFloor: mutation.floor))
    }
    return tasks + entities
  }
}

public enum ApplyRepairObligation: Sendable, Equatable {
  /// A peer attempted to delete the canonical inbox. Keep the local row and
  /// replace the peer's shared delete record with an upsert whose HLC dominates
  /// `remoteDeleteVersion`, so subsequent authoritative snapshots remain valid.
  case reassertRequiredInbox(remoteDeleteVersion: Hlc)
  /// A peer attempted to delete the product timezone, which is an upsert-only
  /// authority once setup can sync. Preserve the local value when present;
  /// otherwise recover the last value carried by the delete snapshot (or the
  /// deterministic UTC fallback), then replace the shared delete with a strict
  /// successor upsert.
  case reassertRequiredTimezone(
    fallbackValue: JSONValue, fallbackUpdatedAt: String, remoteDeleteVersion: Hlc)
  /// Reassert an upsert-only recurring-series boundary after an invalid peer
  /// Delete targeted its CloudKit record.
  case reassertCalendarSeriesCutover(entityId: String, remoteDeleteVersion: Hlc)
  /// A durable cutover invalidated materialized calendar payloads or references.
  /// Local cleanup has already happened in the apply savepoint; replace every
  /// affected shared record with a strict-successor Delete/current Upsert before
  /// acknowledging the triggering CloudKit page.
  case propagateCalendarCleanup(
    targets: [CalendarCleanupRepairTarget], additionalFloor: Hlc)
  /// A task lifecycle decision normalized one or more task-graph records.
  /// Re-emit every canonical task/reminder/day-root snapshot and dependency
  /// tombstone before the triggering CloudKit page is acknowledged.
  case propagateTaskRollover(targets: [TaskGraphRepairTarget], additionalFloor: Hlc)
  /// Two different semantic mutations reused one HLC. The contender is the
  /// deterministic join of the local and remote mutations; the host must mint
  /// a strict successor, apply it, and enqueue the resulting canonical state in
  /// the same transaction that consumes the colliding envelope.
  case resolveEqualVersionCollision(contender: SyncEnvelope, additionalFloor: Hlc? = nil)

  /// Entity kinds whose canonical rows/tombstones the repair itself may mutate.
  /// Callers add the triggering envelope kind separately, then union this set
  /// into their reload/report surface so a derived reminder, dependency, or
  /// day-root write is never hidden behind a task-only notification.
  public var affectedEntityTypes: Set<EntityKind> {
    switch self {
    case .reassertRequiredInbox:
      return [.list]
    case .reassertRequiredTimezone:
      return [.preference]
    case .reassertCalendarSeriesCutover:
      return [.calendarSeriesCutover]
    case .propagateCalendarCleanup(let targets, _):
      return Set(targets.map(\.entityType))
    case .propagateTaskRollover(let targets, _):
      return Set(
        targets.map { target in
          switch target {
          case .taskUpsert:
            return .task
          case .relatedEntity(let entityType, _, _, _):
            return entityType
          }
        })
    case .resolveEqualVersionCollision(let contender, _):
      return [contender.entityType]
    }
  }
}

/// Cap on permanent entity-redirect chain hops.
///
/// Both the apply entry and shadow promotion walk the redirect chain
/// (`sync_entity_redirects`) when resolving an inbound envelope to
/// its current target. Bounded so a corrupt redirect cycle cannot spin forever:
/// at depth `> CAP` we surface ``ApplyError/entityRedirectChainTooDeep`` and
/// skip apply.
let redirectChainCap: Int = 8

/// Errors that can occur during envelope application.
public enum ApplyError: Error, Equatable {
  /// The apply boundary was called without the required outer transaction.
  case transactionRequired
  /// HLC parsing failure.
  case invalidVersion(String)
  /// Unknown entity type in envelope.
  case unknownEntityType(String)
  /// JSON payload parsing or field error.
  case invalidPayload(String)
  /// A store-layer error surfaced from a repository write.
  case store(String)
  /// A database error surfaced from raw SQL.
  case db(String)
  /// A database error whose SQLite primary result code is `SQLITE_BUSY` (5) or
  /// `SQLITE_LOCKED` (6) — a transient lock-contention failure. The pending-inbox
  /// drain treats this class as recoverable (re-records `last_attempted_at`
  /// without bumping `attempt_count`) rather than counting it toward the per-row
  /// retry cap. Surfaces the same `description`
  /// as ``db(_:)`` so error wording stays byte-identical.
  case dbBusyOrLocked(String)
  /// A database error whose SQLite primary result code is `SQLITE_CONSTRAINT`
  /// (19) — a DETERMINISTIC constraint trip (CHECK / NOT NULL / FK / UNIQUE),
  /// not a transient failure. Re-running the identical envelope re-fails
  /// identically, so the inbound batch loop treats this class as a
  /// single-envelope DROP (logged, non-fatal) rather than batch-fatal: a
  /// deterministic constraint escaping an applier would otherwise re-abort the
  /// same CloudKit fetch page forever and wedge all inbound sync (the
  /// inbound-apply path has no quarantine of its own). The trust-boundary
  /// validators (`ApplyTask` cross-field CHECKs, `ApplyDayScoped` mood/energy
  /// scale, the calendar / focus enum gates) pre-empt the known cases as
  /// ``invalidPayload(_:)``; this classification is the defense-in-depth net for
  /// any unforeseen deterministic constraint. Genuinely transient / IO failures
  /// stay ``db(_:)`` (batch-fatal, retry the whole page) and lock contention
  /// stays ``dbBusyOrLocked(_:)``; the split is by the SQLite result code in
  /// ``lift(_:)``. Surfaces the same `description` as ``db(_:)`` so error
  /// wording stays byte-identical.
  case dbConstraint(String)
  /// An entity-redirect chain looped back on a previously-visited entity_id
  /// (self-redirect or mutual A→B / B→A).
  case entityRedirectCycle(entityType: String, entityId: String)
  /// An entity-redirect chain exceeded the bounded ``redirectChainCap``.
  case entityRedirectChainTooDeep(
    entityType: String, entityId: String, chainLength: Int, terminalId: String)
  /// The envelope's operation is not legal for the addressed entity type —
  /// e.g. a `Delete` targeting `ai_changelog`, whose wire contract declares no
  /// delete shape (audit rows leave the store only through local retention and
  /// reset paths, never a sync delete envelope).
  case invalidOperation(entityType: String, operation: String)
  /// The redirect chase rewrote payload-FK identity fields across one or more
  /// hops and the canonical re-serialization of the mutated payload exceeded
  /// the maximum raw payload size.
  case redirectPayloadTooLarge(entityType: EntityKind, entityId: String, sizeBytes: Int)

  /// A per-envelope dependency-graph invariant rejected the edge: the incoming
  /// task-dependency edge lost the cycle-break HLC tiebreak (or was a
  /// self-dependency). This is a convergence outcome, not an infrastructure
  /// failure — the edge is correctly dropped and the rest of an inbound batch
  /// must still apply, so it is classified as a drop-and-continue error rather
  /// than a batch-fatal one.
  case dependencyCycleRejected(taskId: String, dependsOn: String)

  /// Forward-compat retention sentinel for a future-authored semantic this
  /// build cannot safely interpret and the numbered payload manifest cannot
  /// fully describe (for example an opaque embedded grammar), plus
  /// defense-in-depth callers that invoke an inner applier directly.
  ///
  /// Production ``Apply/applyEnvelope(_:registry:envelope:)`` first executes the
  /// payload manifest. Drift in a frozen known-field enum or closed nested shape
  /// is therefore rejected as ``invalidPayload(_:)`` before dispatch; this case
  /// must not be used to widen that contract. When a manifest-valid future
  /// semantic does reach an applier, the outer boundary converts this sentinel
  /// to ``ApplyResult/deferred(reason:)`` so the intact envelope remains in the
  /// pending inbox for an upgraded build. Same/older-schema misses remain
  /// corruption and surface as ``invalidPayload(_:)``. The sentinel never
  /// escapes to the batch loop.
  case deferForwardCompat(DeferralReason)

  /// Human-readable description of this apply error.
  public var message: String {
    switch self {
    case .transactionRequired:
      return "apply_envelope must run inside an outer transaction (BEGIN IMMEDIATE)"
    case .invalidVersion(let msg):
      return "invalid version: \(msg)"
    case .unknownEntityType(let t):
      return "unknown entity type: \(t)"
    case .invalidPayload(let msg):
      return "invalid payload: \(msg)"
    case .store(let msg):
      return "store error: \(msg)"
    case .db(let msg):
      return "database error: \(msg)"
    case .dbBusyOrLocked(let msg):
      return "database error: \(msg)"
    case .dbConstraint(let msg):
      return "database error: \(msg)"
    case .entityRedirectCycle(let entityType, let entityId):
      return
        "entity redirect cycle for \(entityType) \(entityId): "
        + "a redirect chain looped back on a previously-visited id"
    case .entityRedirectChainTooDeep(let entityType, let entityId, let chainLength, let terminalId):
      return
        "entity redirect chain too deep for \(entityType) \(entityId): "
        + "chain reached \(chainLength) hops and was still redirecting at "
        + "terminal id \(terminalId)"
    case .invalidOperation(let entityType, let operation):
      return "invalid operation '\(operation)' for entity type '\(entityType)'"
    case .redirectPayloadTooLarge(let entityType, let entityId, let sizeBytes):
      return
        "redirect chase produced an over-sized payload for \(entityType.asString) \(entityId): "
        + "\(sizeBytes) bytes exceeds maximum of \(PayloadShadow.maxRawPayloadJSONBytes) bytes"
    case .dependencyCycleRejected(let taskId, let dependsOn):
      return
        "dependency cycle rejected for \(taskId)->\(dependsOn): "
        + "the incoming edge lost the cycle-break tiebreak"
    case .deferForwardCompat(let reason):
      return "forward-compat defer: \(reason.message)"
    }
  }
}

extension ApplyError {
  /// Lift a thrown error from a store/sync helper into the apply-pipeline error
  /// space: a SQL-level failure carries through as ``ApplyError/db(_:)``;
  /// any other store error lands as ``ApplyError/store(_:)``.
  static func lift(_ error: Error) -> ApplyError {
    if let applyError = error as? ApplyError {
      return applyError
    }
    if case Outbox.OutboxError.invalidPayloadContract(let detail) = error {
      return .invalidPayload("outbound sync payload contract rejected: \(detail)")
    }
    if case Outbox.OutboxError.payloadContractUnavailable(let detail) = error {
      return .store("sync payload contract unavailable: \(detail)")
    }
    if let payloadError = error as? PayloadError {
      switch payloadError {
      case .sql(let underlying):
        // Re-run the DatabaseError classification on the wrapped GRDB error so a
        // shadow-layer SQL failure keeps the same transient/deterministic split
        // as every other applier: transient lock contention aborts-and-retries,
        // a deterministic constraint drops, any other IO failure aborts.
        return lift(underlying)
      case .validation(let m), .invariant(let m), .serialization(let m):
        // A DETERMINISTIC, non-SQL payload-shadow rejection (size cap, malformed
        // HLC, unknown stored entity kind, non-object payload). Re-running the
        // identical envelope re-fails identically, so classify it as a
        // single-envelope drop rather than a batch-fatal `.store` — otherwise a
        // forward-compat shadow that overflows the 256 KiB cap would wedge the
        // whole inbound batch (the change token never advances) instead of
        // dropping the one poison envelope.
        return .invalidPayload("payload shadow rejected: \(m)")
      }
    }
    if let dbError = error as? DatabaseError {
      switch dbError.resultCode {
      case .SQLITE_BUSY, .SQLITE_LOCKED:
        return .dbBusyOrLocked("\(error)")
      case .SQLITE_CONSTRAINT:
        // A deterministic constraint trip (CHECK / NOT NULL / FK / UNIQUE): the
        // same envelope re-fails identically, so classify it distinctly from a
        // transient / IO `.db` failure the batch loop should retry.
        return .dbConstraint("\(error)")
      default:
        return .db("\(error)")
      }
    }
    return .store("\(error)")
  }

  /// Classify an applier-level semantic miss that is not already expressible by
  /// the numbered manifest. A newer schema returns the forward-compatible
  /// retention sentinel; a same/older schema is corruption and returns
  /// ``invalidPayload(_:)``. Production manifest validation has already rejected
  /// any immutable known-field enum or closed nested-shape drift before this
  /// helper can run, so this is not an alternate compatibility policy for those
  /// fields. `invalidMessage` is lazy so the drop diagnostic is built only when
  /// needed.
  static func forwardCompatOrInvalid(
    payloadSchemaVersion: UInt32, _ invalidMessage: @autoclosure () -> String
  ) -> ApplyError {
    if payloadSchemaVersion > LorvexVersion.payloadSchemaVersion {
      return .deferForwardCompat(
        .schemaTooNew(
          remoteVersion: payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }
    return .invalidPayload(invalidMessage())
  }
}

/// `apply_envelope` entry point — the pipeline that processes a single inbound
/// sync envelope.
public enum Apply {
  /// Apply a single sync envelope to the database.
  ///
  /// Redelivering a byte-identical envelope authored by a compliant peer is a
  /// no-op — every gate resolves to the same skip/replay outcome, so
  /// change-token resets can replay pages safely. The one bounded exception is
  /// an envelope whose payload the applier normalizes on first application
  /// (e.g. foreign over-cap memory content): its redelivery no longer matches
  /// the stored row at the same HLC and resolves through one equal-version
  /// repair before quiescing.
  ///
  /// MUST run inside an outer transaction (the writer's `BEGIN IMMEDIATE`). The
  /// pipeline does many writes (version stamping, tombstone creation, shadow
  /// preparation, FK preflight, conflict-log inserts) that must commit or roll
  /// back atomically. The autocommit guard trips immediately when a caller
  /// forgets the wrapper.
  ///
  /// `registry` supplies the per-entity appliers. In the foundation slice it is
  /// empty, so any envelope that reaches the dispatch seam resolves to
  /// ``ApplyError/unknownEntityType(_:)``; the per-entity slices populate it.
  public static func applyEnvelope(
    _ db: Database, registry: EntityApplierRegistry, envelope: SyncEnvelope
  ) throws -> ApplyResult {
    // The apply boundary requires an outer transaction. GRDB's `write` block
    // always runs inside one, so reaching here without a transaction is a
    // programming error; assert the contract BEFORE opening the per-envelope
    // savepoint below (a SAVEPOINT would itself start a transaction and mask the
    // missing-wrapper violation).
    guard db.isInsideTransaction else {
      throw ApplyError.transactionRequired
    }

    // Run the pipeline inside a per-envelope savepoint so EVERY deferral is
    // side-effect-free. A `.deferred` outcome parks the envelope in the pending
    // inbox for a later replay, so the DB must be left byte-identical to before
    // the envelope was attempted — otherwise inbound convergence becomes
    // order-dependent. An earlier gate can mutate before a later gate defers: the
    // upsert-wins-over-delete tombstone removal + conflict-log write runs before
    // the FK gate defers on a missing parent (on both the direct tombstone gate
    // and the redirect-target tombstone gate), which persisted a tombstone removal
    // for an upsert that never applied and could resurrect a deleted row. Threading
    // a `.deferred` return out of the savepoint as ``DeferRollback`` (and the
    // deep-applier ``ApplyError/deferForwardCompat(_:)`` sentinel) rolls those
    // partial writes back; each re-materializes as a normal `.deferred`. Any other
    // throw propagates (the savepoint still rolls back) as before.
    do {
      return try StoreTransactions.withSavepoint(db, "apply_envelope") { db in
        let result = try applyEnvelopeInner(db, registry: registry, envelope: envelope)
        if case .deferred(let reason) = result {
          throw DeferRollback(reason: reason)
        }
        return result
      }
    } catch let rollback as DeferRollback {
      return .deferred(reason: rollback.reason)
    } catch ApplyError.deferForwardCompat(let reason) {
      return .deferred(reason: reason)
    }
  }

  /// Internal sentinel carrying a ``DeferralReason`` out of the per-envelope
  /// savepoint in ``applyEnvelope(_:registry:envelope:)`` so the savepoint rolls
  /// back any partial mutation an earlier gate performed before a later gate
  /// deferred. A deferred envelope must leave zero net side effects on the DB.
  private struct DeferRollback: Error {
    let reason: DeferralReason
  }

  /// The apply pipeline body, run inside the per-envelope guard savepoint opened
  /// by ``applyEnvelope(_:registry:envelope:)`` (which also enforces the
  /// outer-transaction contract). Kept private so every caller goes through the
  /// forward-compat retention boundary.
  private static func applyEnvelopeInner(
    _ db: Database, registry: EntityApplierRegistry, envelope originalEnvelope: SyncEnvelope
  ) throws -> ApplyResult {
    var envelope = originalEnvelope
    // Capture the apply timestamp ONCE and thread it through every helper.
    let applyTs = SyncTimestampFormat.syncTimestampNow()

    // Execute the numbered payload manifest as the first typed trust boundary.
    // Historical/current schemas are exact. A future schema may add unknown
    // top-level fields for payload shadow, but every currently-known required
    // key, type, format, enum, range, and closed nested object remains strict.
    // Validate before ANY clock/schema/control hold, collision breadcrumb,
    // LWW/FK gate, tombstone mutation, or shadow write so an impossible future
    // payload can neither park forever nor leave partial state.
    if envelope.entityType.isSyncableKind {
      do {
        try SyncPayloadContractRegistry.validate(envelope)
      } catch SyncPayloadContractError.violations(let violations) {
        throw ApplyError.invalidPayload(
          "sync payload contract rejected envelope: \(violations.joined(separator: "; "))")
      } catch let error as SyncPayloadContractError {
        // A missing/corrupt bundled manifest is local infrastructure failure,
        // not proof that the peer payload is invalid. Abort the batch so the
        // checkpoint cannot advance past data this build failed to validate.
        throw ApplyError.store("sync payload contract unavailable: \(error)")
      }
    }

    // A syntactically valid but operationally unusable remote HLC must never
    // become canonical local state. In particular, the absolute HLC ceiling has
    // no successor for an explicit local edit; a far-future physical component
    // would otherwise force this identity onto the detached writer lane for an
    // unbounded period. Defer before collision diagnostics or any apply mutation.
    if let reason = FutureRecordHold.clockDeferralReason(for: envelope.version) {
      return .deferred(reason: reason)
    }

    // Layer-1 device-identity collision detection (best-effort, never throws).
    ApplyCollision.checkDeviceIdentityCollision(db, envelope: envelope)

    // 1. Check envelope payload_schema_version.
    let acceptance = Capability.checkEnvelopeVersion(
      envelopePayloadVersion: envelope.payloadSchemaVersion,
      localMaxVersion: LorvexVersion.payloadSchemaVersion)
    switch acceptance {
    case .parseFully, .parseForwardCompat:
      break
    case .rejectInvalid:
      throw ApplyError.invalidPayload(
        "payload_schema_version \(envelope.payloadSchemaVersion) is unsupported; versions start at 1"
      )
    case .deferToPendingInbox:
      return .deferred(
        reason: .schemaTooNew(
          remoteVersion: envelope.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }

    // The append-only audit stream and permanent alias ledger have no safe
    // partial-promotion seam. Applying a next-generation control record while
    // truncating an unknown semantic field could make retention or identity
    // resolution irreversible, so hold both kinds intact until an upgraded
    // build understands the complete payload.
    if acceptance == .parseForwardCompat,
      envelope.entityType == .aiChangelog || envelope.entityType == .entityRedirect
    {
      return .deferred(
        reason: .schemaTooNew(
          remoteVersion: envelope.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }

    // A prior complete snapshot may have classified a preserved future-held
    // row as stale pre-session state. Once this build understands the terminal
    // remote envelope, make that row yield before ordinary LWW compares it.
    // This runs inside the per-envelope savepoint, so any later deferral or
    // validation failure restores the local row and its fence atomically.
    try FutureRecordHold.prepareTerminalEnvelopeApply(db, envelope: envelope)

    // The absorbing alias kind has its own apply semantics: upsert only, exact
    // source digest validation, durable target deferral, and min-target join.
    if envelope.entityType == .entityRedirect {
      return try EntityRedirect.applyInbound(
        db, registry: registry, envelope: envelope, applyTs: applyTs)
    }

    // Filter local-only kinds that must never round-trip through sync.
    if !envelope.entityType.isSyncableKind {
      return .skipped(
        reason: "non-syncable entity_type \(envelope.entityType.asString) — ignored "
          + "(local-only kind)",
        winnerVersion: nil)
    }

    // Audit retention is preference-shaped at the product API only. Its value
    // is account-scoped control-plane metadata, so even a valid, hand-crafted
    // legacy `.preference` record must not create a second authority, shadow,
    // or tombstone locally.
    if envelope.entityType == .preference,
      PreferenceKeys.isControlPlanePreference(envelope.entityId)
    {
      return .skipped(
        reason:
          "control-plane preference \(envelope.entityId) is excluded from ordinary preference sync",
        winnerVersion: nil)
    }

    try validateApplyEntityId(envelope)

    // Composite-edge parent-redirect remap. A merged tag or habit parent
    // carries a permanent alias, but the edge id targeting it does
    // NOT, so the exact-id tombstone gate below is blind to it. Chase each half's
    // parent redirect and operate on the surviving edge id — for BOTH upsert and
    // delete, symmetrically — so an edge upsert lands on the winner edge and an
    // edge delete removes it (rather than no-op'ing on the vanished loser id and
    // leaving the remapped edge to resurrect a deleted relationship). Running it
    // here, ahead of the tombstone/LWW gate, makes the two arrival orders
    // (delete-before-upsert / upsert-before-delete) converge identically.
    if CompositeEdge.isCompositeEdgeEntityType(envelope.entityType.asString) {
      if let remapped = try ApplyRedirect.remapCompositeEdgeThroughParentRedirects(
        db, envelope: envelope)
      {
        envelope = remapped
      }
    }

    // 2. Permanent identity-alias gate. It precedes ordinary delete state so an
    // alias remains absorbing even if a stale higher-HLC loser upsert arrives.
    let redirect = try EntityRedirect.get(
      db, sourceType: envelope.entityType.asString, sourceId: envelope.entityId)
    if let redirect {
      return try ApplyRedirectFlow.applyRedirectedEnvelope(
        db, registry: registry, envelope: envelope, redirect: redirect,
        acceptance: acceptance, applyTs: applyTs)
    }

    // A future-schema base calendar snapshot cannot be safely decomposed while
    // another base snapshot already exists: an unknown field may belong to the
    // content register or the topology register. Hold it intact until this
    // runtime knows that field's group instead of attaching its shadow to the
    // wrong winner during a mixed merge. First materialization remains safe and
    // follows the ordinary forward-compatible shadow path.
    if envelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion,
      try ApplyCalendarEvent.isBaseMergePair(db, envelope: envelope)
    {
      return .deferred(
        reason: .schemaTooNew(
          remoteVersion: envelope.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }
    // Unknown future task fields cannot be assigned to one of the four
    // independent registers safely once a local row already exists. Preserve
    // the whole envelope until this runtime knows the field ownership.
    if envelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion,
      try ApplyTask.isGroupedMergePair(db, envelope: envelope)
    {
      return .deferred(
        reason: .schemaTooNew(
          remoteVersion: envelope.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }

    if let result = try ApplyLwwGate.requiredTimezoneDeleteRepair(
      db, envelope: envelope, applyTs: applyTs)
    {
      return result
    }

    if let result = try ApplyLwwGate.requiredCutoverDeleteRepair(
      db, envelope: envelope)
    {
      return result
    }

    if let obligation = try ApplyCalendarEvent.cutoverCleanupRepairIfResolved(
      db, envelope: envelope, applyTs: applyTs)
    {
      return .repairRequired(obligation)
    }

    if let obligation = try CalendarSeriesCutoverCleanup.lateReferenceRepairIfResolved(
      db, envelope: envelope, applyTs: applyTs)
    {
      return .repairRequired(obligation)
    }

    // A reused HLC with different semantic content cannot be resolved by the
    // ordinary `>=` local-wins gate: two clones would each keep their own bytes
    // forever. Detect it before the tombstone/live-row split and surface one
    // deterministic contender for successor re-authoring by the host.
    if let result = try ApplyLwwGate.gateEqualVersionMutation(db, envelope: envelope) {
      return result
    }

    // 3. Ordinary tombstone gate.
    let tombstone: Tombstone.Record?
    do {
      tombstone = try Tombstone.getTombstone(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    } catch { throw ApplyError.lift(error) }

    if let ts = tombstone {
      if let result = try ApplyTombstoneGate.gateExistingTombstone(
        db, envelope: envelope, ts: ts, applyTs: applyTs)
      {
        return result
      }
    }

    // 4. LWW + FK gate (both upsert and delete).
    if let result = try ApplyLwwGate.gateLwwAndFk(db, envelope: envelope, applyTs: applyTs) {
      return result
    }
    if let reason = try TaskRolloverReconciliation.deferralReason(
      db, envelope: envelope)
    {
      return .deferred(reason: reason)
    }

    // 5. Prepare the shadow before dispatch. An aggregate collision merge inside an
    // applier may delete/redirect this identity and emit the winner immediately;
    // pre-stashing lets that same transaction move the future fields with the
    // selected content instead of stranding them on the loser.
    if envelope.operation == .upsert {
      try ApplyPayloadShadow.prepareForUpsertDispatch(
        db, acceptance: acceptance, envelope: envelope)
    }

    // 6. Delegate to the per-entity applier via the dispatch seam.
    let outcome = try ApplyDispatch.dispatch(
      db, registry: registry, envelope: envelope, tieBreak: .rejectEqual, applyTs: applyTs)

    return try ApplyDeleteFlow.finalizeEntityOutcome(
      db, envelope: envelope, outcome: outcome, applyTs: applyTs)
  }

  static func validateApplyEntityId(_ envelope: SyncEnvelope) throws {
    switch SyncEntityId.validateForKind(envelope.entityType, envelope.entityId) {
    case .success:
      return
    case .failure(let error):
      throw ApplyError.invalidPayload(
        "sync envelope entity_id for \(envelope.entityType.asString) must be canonical: \(error)")
    }
  }
}
