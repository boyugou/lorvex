import Foundation
import LorvexDomain
import LorvexStore

/// Caller-supplied context bundle threaded through every outbox enqueue.
///
/// Carries the canonical transport HLC, authoring `device_id`, and optional
/// device-local grouped-register provenance.
public struct OutboxWriteContext: Sendable, Equatable {
  public var version: String
  public var deviceId: String
  public var registerIntent: EntityRegisterIntent

  public init(
    version: String, deviceId: String,
    registerIntent: EntityRegisterIntent = .none
  ) {
    self.version = version
    self.deviceId = deviceId
    self.registerIntent = registerIntent
  }
}

/// Typed error surface for the outbox-enqueue path.
public enum EnqueueError: Error {
  /// The entity type is not recognized or not supported for snapshot reading.
  case unknownEntityType(String)
  /// The current payload contract declares no outbound shape for this operation.
  case unsupportedOperation(entityType: String, operation: String)
  /// The entity was not found in the database.
  case entityNotFound(entityType: String, entityId: String)
  /// A store-layer invariant / validation / serialization failure occurred.
  case store(StoreError)
  /// A SQLite error occurred (lifts GRDB's `DatabaseError`).
  case sqlite(Error)
  /// Version stamping failed before the envelope could be queued (any
  /// `VersionStampError` variant other than `superseded`, which lifts into
  /// ``versionSuperseded``).
  case versionStamp(VersionStamp.VersionStampError)
  /// Payload canonicalization failed (e.g. nesting exceeds the JSON-depth cap).
  case canonicalization(SyncCanonicalize.SyncCanonError)
  /// A stored envelope blob or payload could not be parsed structurally: the
  /// payload string is not well-formed JSON, or the envelope JSON is not valid
  /// UTF-8. Distinct from ``canonicalization(_:)``, which is a depth/size cap on
  /// *well-formed* JSON — a caller must not mistake a parse failure for an
  /// over-deep-but-valid payload. The associated string is a diagnostic detail.
  case malformedPayload(String)
  /// A concurrent writer stamped a strictly newer version than the one this
  /// enqueue attempt brought; the caller must re-read + re-enqueue.
  case versionSuperseded(
    entityType: String, entityId: String, attemptedVersion: String, existingVersion: String)
  /// The outbox coalesce surface refused the envelope because the incoming
  /// `version` failed `Hlc.parse`; the caller must re-stamp.
  case taintedVersion(entityType: EntityKind, entityId: String, version: String)
  /// A canonical HLC exceeded the shared operational wire ceiling. The entire
  /// local mutation must roll back; emitting it would poison every peer.
  case operationalHlcCeilingExceeded(
    entityType: String, entityId: String, version: String)
  /// A future-authored CloudKit record currently owns this record identity.
  /// The caller must leave the entire local mutation transaction unchanged and
  /// retry only after an upgraded build has reconciled the held record.
  case futureRecordRequiresNewerApp(
    entityType: String, entityId: String, heldVersion: String)
  /// The coalesced-enqueue retry loop exhausted its retry budget against the
  /// `(entity_type, entity_id)` UNIQUE-partial-index race.
  case contentionExhausted(entityType: EntityKind, entityId: String, attempts: UInt32)

  /// Lift an ``Outbox/OutboxError`` into the enqueue-path error surface.
  public init(_ error: Outbox.OutboxError) {
    switch error {
    case .invalidPayloadContract(let detail):
      self = .store(.validation("sync payload contract rejected outbound envelope: \(detail)"))
    case .payloadContractUnavailable(let detail):
      self = .store(.invariant("sync payload contract unavailable: \(detail)"))
    case .sql(let message):
      self = .store(.invariant("outbox sql error: \(message)"))
    case .taintedVersion(let entityType, let entityId, let version):
      self = .taintedVersion(entityType: entityType, entityId: entityId, version: version)
    case .operationalHlcCeilingExceeded(let entityType, let entityId, let version):
      self = .operationalHlcCeilingExceeded(
        entityType: entityType.asString, entityId: entityId, version: version)
    case .futureRecordRequiresNewerApp(let entityType, let entityId, let heldVersion):
      self = .futureRecordRequiresNewerApp(
        entityType: entityType.asString, entityId: entityId, heldVersion: heldVersion)
    case .contentionExhausted(let entityType, let entityId, let attempts):
      self = .contentionExhausted(entityType: entityType, entityId: entityId, attempts: attempts)
    }
  }
}

extension EnqueueError: CustomStringConvertible {
  /// Human-readable description of this enqueue error.
  public var description: String {
    switch self {
    case .unknownEntityType(let t):
      return "unknown entity type for snapshot: \(t)"
    case .unsupportedOperation(let entityType, let operation):
      return "unsupported outbound sync operation \(operation) for \(entityType)"
    case .entityNotFound(let entityType, let entityId):
      return "entity not found: \(entityType)/\(entityId)"
    case .store(let e):
      return "store error: \(e)"
    case .sqlite(let e):
      return "sqlite error: \(e)"
    case .versionStamp(let e):
      return "version stamp error: \(e.message)"
    case .canonicalization(let e):
      return "canonicalization error: \(e)"
    case .malformedPayload(let detail):
      return "malformed payload: \(detail)"
    case .versionSuperseded(let entityType, let entityId, let attempted, let existing):
      return
        "enqueue superseded for \(entityType):\(entityId) "
        + "(attempted \(attempted), existing \(existing))"
    case .taintedVersion(let entityType, let entityId, let version):
      return
        "outbox refused tainted incoming version for \(entityType.asString)/\(entityId): "
        + "version=\"\(version)\" failed Hlc::parse — caller must re-stamp"
    case .operationalHlcCeilingExceeded(let entityType, let entityId, let version):
      return
        "cannot write \(entityType)/\(entityId): version \(version) exceeds the "
        + "operational sync wire ceiling; the transaction was rolled back"
    case .futureRecordRequiresNewerApp(let entityType, let entityId, let heldVersion):
      return
        "cannot write \(entityType)/\(entityId): CloudKit holds future-authored data at "
        + "\(heldVersion); upgrade Lorvex before editing this item"
    case .contentionExhausted(let entityType, let entityId, let attempts):
      return
        "outbox coalesce retry budget exhausted for \(entityType.asString)/\(entityId) "
        + "after \(attempts) attempts; the write was rolled back and must be retried"
    }
  }
}

extension EnqueueError: LocalizedError {
  /// Preserve the typed enqueue diagnostic across importer/UI boundaries that
  /// consume `localizedDescription`; the default NSError bridge would otherwise
  /// collapse every associated-value case to an opaque "error N" message.
  public var errorDescription: String? { description }
}

/// Wire-shape helpers for `task_dependencies` edge tombstones — the canonical
/// `{task_id}:{depends_on_task_id}` composite-PK encoder and the canonical-row
/// delete payload builder. A single source of truth so every caller stays in
/// lock-step with the apply-side decoder.
public enum DependencyEdge {
  /// Build the canonical delete payload for a removed `task_dependencies` edge
  /// (`task_id`, `depends_on_task_id`, `created_at`, `version`), identical to
  /// the upsert payload of the live edge so peers that missed the upsert can
  /// reconstruct the row for restore-from-trash. Delegates to the shared
  /// `PayloadLoaders.taskDependencyPayload` primitive.
  public static func buildDeletePayload(
    taskId: String, dependsOnTaskId: String, version: String, createdAt: String
  ) -> JSONValue {
    PayloadLoaders.taskDependencyPayload(
      taskId: taskId, dependsOnTaskId: dependsOnTaskId, version: version, createdAt: createdAt)
  }

  /// Composite primary-key encoding for a `task_dependencies` edge:
  /// `{task_id}:{depends_on_task_id}`. Matches the `EDGE_TASK_DEPENDENCY`
  /// apply-side `entity_id` shape.
  public static func encodeEntityId(taskId: String, dependsOnTaskId: String) -> String {
    "\(taskId):\(dependsOnTaskId)"
  }
}

/// Shared outbox-enqueue core — the canonical write path callers invoke after
/// any entity mutation. The pipeline lives in `OutboxEnqueuePayload.swift`
/// (version stamping → stale-tombstone clear → payload-shadow merge →
/// version injection → envelope build → coalesced outbox insert → tombstone
/// mint) and the snapshot reader (`read_entity_payload_snapshot`).
/// `ChildTombstones.swift` holds the delete-cascade helpers. Pending-inbox replay
/// belongs to the host's top-level transaction funnel, where a real HLC session
/// can fulfill every resulting convergence obligation; enqueue itself never
/// recursively drains pending work.
public enum OutboxEnqueue {}
