import Foundation
import LorvexDomain

/// Durable phase of an over-window authoritative CloudKit snapshot.
public enum AuthoritativeSnapshotPhase: String, Codable, Sendable, Equatable {
  /// The session and pre-session outbox fence are durable, but its immutable
  /// remote traversal witness has not yet been published. A relaunch repeats
  /// that witness publication without re-fencing post-session writes.
  case preparing
  /// The remote witness is published and the next SQLite traversal starts from
  /// a nil token. No page has been staged yet, so relaunch may safely repeat
  /// that first fetch.
  case ready
  /// At least one page was staged. Every continuation cursor must now bind to
  /// this session token and physical database instance.
  case pulling
}

/// Exact ready-generation snapshot session stored in the local database.
public struct AuthoritativeSnapshotSession: Sendable, Equatable {
  public var sessionToken: String
  public var boundary: CloudTraversalBoundary
  public var databaseInstanceId: String
  public var phase: AuthoritativeSnapshotPhase
  public var outboxBoundaryId: Int64
  public var startedAt: String

  public init(
    sessionToken: String, boundary: CloudTraversalBoundary, databaseInstanceId: String,
    phase: AuthoritativeSnapshotPhase, outboxBoundaryId: Int64, startedAt: String
  ) {
    self.sessionToken = sessionToken
    self.boundary = boundary
    self.databaseInstanceId = databaseInstanceId
    self.phase = phase
    self.outboxBoundaryId = outboxBoundaryId
    self.startedAt = startedAt
  }

  public var accountIdentifier: String { boundary.accountIdentifier }
  public var zoneName: String { boundary.zoneIdentifier }
}

/// How much of a fetched `LorvexEntity` record this build understood while
/// staging an authoritative snapshot.
public enum AuthoritativeSnapshotRecordState: String, Codable, Sendable, Equatable {
  case decoded
  case unknown
  case corrupt
}

/// One current CloudKit record staged before the final authoritative replay.
public struct AuthoritativeSnapshotRemoteRecord: Sendable, Equatable {
  public var recordName: String
  public var state: AuthoritativeSnapshotRecordState
  public var envelope: SyncEnvelope?
  /// Exact validated wire fields for a well-formed future entity/operation.
  /// Stored durably with the snapshot inventory and parked only when the
  /// terminal page commits, so a cursor can never advance past bytes we lost.
  public var rawEnvelope: RawEnvelopeFields?
  /// CloudKit server-assigned modification time for this exact staged record.
  public var serverModifiedAt: String?

  public init(
    recordName: String, state: AuthoritativeSnapshotRecordState, envelope: SyncEnvelope?,
    rawEnvelope: RawEnvelopeFields? = nil, serverModifiedAt: String? = nil
  ) {
    self.recordName = recordName
    self.state = state
    self.envelope = envelope
    self.rawEnvelope = rawEnvelope
    self.serverModifiedAt = serverModifiedAt
  }
}

/// Atomic reconciliation outcome surfaced to the transport/UI reload scope.
public struct AuthoritativeSnapshotReport: Sendable, Equatable {
  public var removedLocalEntities: Int
  public var replayedRemoteRecords: Int
  public var deferredUnknownTypeRecords: Int
  public var changedEntityTypes: Set<EntityKind>

  public init(
    removedLocalEntities: Int = 0, replayedRemoteRecords: Int = 0,
    deferredUnknownTypeRecords: Int = 0,
    changedEntityTypes: Set<EntityKind> = []
  ) {
    self.removedLocalEntities = removedLocalEntities
    self.replayedRemoteRecords = replayedRemoteRecords
    self.deferredUnknownTypeRecords = deferredUnknownTypeRecords
    self.changedEntityTypes = changedEntityTypes
  }
}

public enum AuthoritativeSnapshotError: Error, Sendable, Equatable, CustomStringConvertible {
  case noActiveSession
  case sessionBoundaryMismatch
  case sessionTokenMismatch
  case databaseInstanceMismatch
  case wrongPhase(expected: AuthoritativeSnapshotPhase, actual: AuthoritativeSnapshotPhase)
  case invalidRecordName
  case recordLimitExceeded(limit: Int, observedAtLeast: Int)
  case byteLimitExceeded(limit: Int64, observedAtLeast: Int64)
  case malformedStagingAccounting
  case malformedStagedEnvelope(recordName: String)
  case unrecognizedRecords(unknown: Int, corrupt: Int)
  case missingRequiredInbox
  case applyRejected(entityType: String, entityId: String, reason: String)

  public var description: String {
    switch self {
    case .noActiveSession:
      return "no authoritative snapshot session is active"
    case .sessionBoundaryMismatch:
      return "authoritative snapshot no longer matches the exact active generation descriptor"
    case .sessionTokenMismatch:
      return "authoritative snapshot operation belongs to a different durable session"
    case .databaseInstanceMismatch:
      return "authoritative snapshot belongs to a different physical database instance"
    case .wrongPhase(let expected, let actual):
      return "authoritative snapshot phase is \(actual.rawValue), expected \(expected.rawValue)"
    case .invalidRecordName:
      return "authoritative snapshot record name is empty or over the bounded storage limit"
    case .recordLimitExceeded(let limit, let observedAtLeast):
      return "authoritative snapshot exceeds \(limit) records (observed at least \(observedAtLeast))"
    case .byteLimitExceeded(let limit, let observedAtLeast):
      return
        "authoritative snapshot exceeds \(limit) encoded bytes "
        + "(observed at least \(observedAtLeast))"
    case .malformedStagingAccounting:
      return "authoritative snapshot staging counters do not match the durable inventory"
    case .malformedStagedEnvelope(let recordName):
      return "authoritative snapshot contains a malformed staged envelope for \(recordName)"
    case .unrecognizedRecords(let unknown, let corrupt):
      return
        "authoritative snapshot cannot finalize with \(unknown) unknown and \(corrupt) corrupt record(s)"
    case .missingRequiredInbox:
      return "authoritative snapshot is missing the required inbox list record"
    case .applyRejected(let entityType, let entityId, let reason):
      return "authoritative snapshot rejected \(entityType)/\(entityId): \(reason)"
    }
  }
}
