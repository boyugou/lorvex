import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

/// Failure raised by ``CloudSyncRecordPushing/ensureZone()`` when the modify
/// operation returned but the sync zone was not actually saved.
public enum CloudSyncZoneEnsureError: Error, Equatable {
  /// `modifyRecordZones` returned no per-zone result for the zone this device
  /// asked to save — the zone cannot be assumed to exist, so ensure fails rather
  /// than caching a false success.
  case zoneSaveResultMissing
}

/// Failure raised by ``CloudSyncRecordPushing/deleteZone()`` when the modify
/// operation returned but reported no per-zone result for the zone it was asked
/// to delete — the deletion cannot be assumed to have happened, so the call
/// fails rather than reporting a false success the caller would durably record.
public enum CloudSyncZoneDeleteError: Error, Equatable {
  case zoneDeleteResultMissing
}

/// Failures raised by the zone-epoch record operations (S-5).
///
/// - ``zoneEpochSaveResultMissing``: a rebuild-state modify operation returned
///   but reported no per-record result for the zone-epoch record it saved — the
///   transition cannot be assumed durable, so the call fails rather than
///   continuing with a fictitious generation the account never published.
/// - ``zoneEpochRecordUndecodable``: ``CloudSyncRecordPushing/currentZoneEpoch()``
///   fetched a zone-epoch record whose `epoch` field does not decode as an
///   integer. The record EXISTS — some device advanced the epoch — so reading
///   it as "no epoch" would hide a possible zone rebuild from the over-window
///   check; the read fails instead so the caller defers fail-closed.
public enum CloudSyncZoneEpochError: Error, Equatable {
  case zoneEpochSaveResultMissing
  case zoneEpochRecordUndecodable
  /// The shared durable generation maximum was reached; incrementing would
  /// publish a control value the local traversal/schema layer cannot represent.
  case zoneEpochExhausted
  /// Every bounded compare-and-swap retry lost to a concurrent writer.
  case zoneEpochCASRetryLimitExceeded
  /// Relaunch recovery could not durably re-enqueue the rebuilt zone snapshot.
  case zoneEpochPendingBackfillFailed
  /// The encrypted-key-reset delete phase has not completed yet.
  case zoneRecreationStillRequired
  /// Another device owns a still-live rebuilding lease. Ordinary sync and
  /// authoritative adoption must wait rather than trust a partial generation.
  case zoneRebuildInProgress
  /// The rebuilding lease no longer matches the remote generation (another
  /// device took over after the stale-owner interval, or the metadata changed).
  case zoneRebuildLeaseLost
  /// CloudKit acknowledged a lease transition but returned a different state.
  case zoneRebuildSavedStateMismatch
  /// The bounded retired-zone ledger cannot safely record another namespace.
  case retiredZoneLimitExceeded
  /// Candidate root/seal content is missing or does not match the active lease.
  case generationMarkerMismatch
}

/// Thrown by the boundary-guarded ``CloudSyncRecordPushing/push(_:boundaryGuard:)``
/// when the live iCloud account no longer matches the one confirmed at sync-cycle
/// start, evaluated immediately before an external CloudKit mutation. Distinct
/// from an ordinary push failure so the coordinator can abort the outbound drain
/// and leave every un-pushed row PENDING and UNFAILED — they re-push idempotently
/// under the original account once the account gate re-opens — rather than
/// advancing them toward delayed retry wait. A `nil` live identity (signed out /
/// unreadable) is read fail-closed as a crossed boundary, so this can never let
/// one account's private records land in a different account's zone.
public struct CloudSyncAccountBoundaryCrossed: Error, Sendable {
  public init() {}
}

/// The retention-metadata record is the compare-and-swap guard for every audit
/// upload. Missing/stale authority asks the coordinator to re-run the metadata
/// merge. Invalid atomic results and transport failures propagate immediately;
/// none of these failures charges an audit outbox row's retry budget.
public enum CloudSyncAuditRetentionGuardError: Error, Sendable, Equatable {
  case missing
  case stale
  case invalidAtomicResult
  case transport(String)
}

/// A record-level conflict that must be resolved by the transactional core,
/// never by re-saving the same ordering key in the transport.
public enum CloudSyncPushCollision: Sendable, Equatable {
  case equalVersion(serverEnvelope: SyncEnvelope)
  /// Two current-schema values occupy a slot whose entity has typed join
  /// semantics. Core joins the server contender with the exact pending local
  /// mutation and authors one strict successor before consuming that capability.
  case semanticMerge(kind: SemanticPushConflictKind, serverEnvelope: SyncEnvelope)
  /// A peer wrote an invalid current-schema Delete to the permanent redirect
  /// ledger. Core reasserts the exact local alias above the remote delete floor.
  case entityRedirectDelete(serverEnvelope: SyncEnvelope)
  /// A valid server contender for an append-only identity whose local table has
  /// no version column. Core still has the exact pending outbox capability and
  /// resolves same-content replay or the version-independent deterministic
  /// content winner before authoring a successor above both transport HLCs.
  case immutableIdentity(serverEnvelope: SyncEnvelope)
  case corruptServerSlot(serverVersionFloor: Hlc?)
}

/// Server system fields captured during a collision. They become safe to cache
/// only after core has durably replaced the old outbox mutation with a strict
/// successor; caching earlier would let a rollback retry overwrite CloudKit
/// under the old HLC without conflict resolution.
public struct CloudSyncSystemFieldsReceipt: Sendable, Equatable {
  public var recordName: String
  public var archivedSystemFields: Data

  public init(recordName: String, archivedSystemFields: Data) {
    self.recordName = recordName
    self.archivedSystemFields = archivedSystemFields
  }
}

/// Outcome of pushing one CKRecord. `recordName` ties the result back to the
/// outbox row that produced it so the coordinator can confirm or fail the
/// matching `sync_outbox` entry.
///
/// When a `serverRecordChanged` conflict resolves to the server's version (the
/// server holds a strictly-newer HLC), `serverEnvelopeToApply` carries the
/// decoded server record so the coordinator can apply it locally — this device
/// lost the push but must still converge on the winning version. If the server
/// winner is a well-formed future record this build cannot decode,
/// `serverRawToDefer` carries the raw fields so the coordinator can park them
/// durably instead of depending on a later retry to see the same conflict.
public struct CloudSyncPushResult: Equatable, Sendable {
  public var recordName: String
  public var succeeded: Bool
  /// Failure detail when `succeeded == false`; `nil` on success.
  public var errorMessage: String?
  /// True when a failure (`succeeded == false`) was a TRANSIENT transport outage
  /// (network down, rate-limited, zone busy) rather than a persistent per-record
  /// rejection. The coordinator records a transient failure without advancing the
  /// outbox row toward delayed retry wait (SY2). Always `false` on success.
  public var isTransient: Bool
  /// Server record to apply locally when our push lost the LWW conflict; `nil`
  /// otherwise.
  public var serverEnvelopeToApply: SyncEnvelope?
  /// Raw future server record to park when our push lost to a forward-compatible
  /// record this build cannot model; `nil` otherwise.
  public var serverRawToDefer: RawEnvelopeFields?
  /// Equal-HLC semantic collision or exact-slot corruption that core must
  /// resolve by minting a successor before this result can be acknowledged.
  public var collision: CloudSyncPushCollision?
  /// Current server change-tag receipt. The coordinator commits it only after
  /// the collision repair transaction succeeds.
  public var systemFieldsReceipt: CloudSyncSystemFieldsReceipt?
  /// CloudKit's server-assigned modification time for the record that this
  /// result confirms or applies. `nil` is conservative: it can never age a
  /// tombstone into compaction eligibility.
  public var serverModificationDate: Date?

  public init(
    recordName: String, succeeded: Bool, errorMessage: String? = nil,
    isTransient: Bool = false,
    serverEnvelopeToApply: SyncEnvelope? = nil,
    serverRawToDefer: RawEnvelopeFields? = nil,
    collision: CloudSyncPushCollision? = nil,
    systemFieldsReceipt: CloudSyncSystemFieldsReceipt? = nil,
    serverModificationDate: Date? = nil
  ) {
    self.recordName = recordName
    self.succeeded = succeeded
    self.errorMessage = errorMessage
    self.isTransient = isTransient
    self.serverEnvelopeToApply = serverEnvelopeToApply
    self.serverRawToDefer = serverRawToDefer
    self.collision = collision
    self.systemFieldsReceipt = systemFieldsReceipt
    self.serverModificationDate = serverModificationDate
  }
}

/// Transport seam for sending CKRecords to CloudKit. Symmetric to
/// ``CloudSyncRemoteChangeFetching`` (the inbound seam): the real
/// implementation talks to `CKDatabase`, while a fake drives the coordinator's
/// outbound orchestration in unit tests with no CloudKit dependency.
///
/// `push` modifies (saves) records; deletes are expressed as `delete`-operation
/// envelopes whose record is saved like any other (the engine carries the
/// tombstone in the payload), so a separate delete entry point is intentionally
/// not part of this seam.
public protocol CloudSyncRecordPushing: Sendable {
  func currentZoneGenerationState() async throws -> CloudSyncZoneGenerationState?

  func beginZoneRebuild(
    atLeast floor: Int, ownerIdentifier: String, allowFromDeleted: Bool,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease

  /// Abandon an exact in-progress candidate and atomically lease a brand-new
  /// generation/zone to the same owner. Used whenever either terminal old-zone
  /// drain proves the local snapshot changed while the candidate was uploading.
  func restartZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease

  func advanceZoneRebuildPhase(
    _ lease: CloudSyncZoneRebuildLease, to phase: CloudSyncZoneRebuildPhase,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func completeZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest: CloudSyncGenerationManifest,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncGenerationDescriptor

  func markCloudDataDeleted(
    atLeast generationFloor: Int,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneGenerationState

  func ensureZone(
    _ zoneID: CKRecordZone.ID, expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func ensureGenerationRoot(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func validateGenerationRoot(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> Bool

  func saveGenerationSeal(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest: CloudSyncGenerationManifest,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func publishTraversalWitness(
    context: CloudSyncGenerationContext, expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func deleteTraversalWitness(
    context: CloudSyncGenerationContext, expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func readAuditRetentionMetadata(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata?

  func mergeAuditRetentionMetadata(
    _ proposed: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata

  func publishGenerationWake(
    descriptor: CloudSyncGenerationDescriptor,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func push(
    _ records: [CKRecord], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult]

  /// Persist conflict-returned server change tags only after the matching core
  /// successor transaction commits.
  func commitReconciledConflictSystemFields(
    _ receipts: [CloudSyncSystemFieldsReceipt], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  /// Save audit envelopes in the same custom-zone atomic transaction as an
  /// unchanged retention-metadata record. The metadata change tag serializes
  /// uploads against frontier advances and physical deletion.
  func pushAuditRecords(
    _ records: [CKRecord], guardedBy metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult]

  func physicallyDelete(
    _ recordIDs: [CKRecord.ID], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecord.ID: Result<Void, any Error>]

  func deleteRetiredZone(
    zoneName: String, accountIdentifier: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  /// CAS-prune one already-deleted namespace from the fleet-visible retired
  /// ledger. This is intentionally separate from the physical zone delete: the
  /// coordinator must first durably acknowledge local audit-retention evidence,
  /// so a crash can always rediscover and retry the cleanup from the ledger.
  func finalizeRetiredZoneDeletion(
    zoneName: String,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws

  func allRecordZones(
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecordZone]

  func clearRecordSystemFieldsCache(accountIdentifier: String, zoneName: String) async
  func clearAllRecordSystemFieldsCache() async
}

extension CloudSyncRecordPushing {
  /// Lightweight fakes have no system-fields cache. Production overrides this
  /// and validates every receipt against the active account/generation.
  public func commitReconciledConflictSystemFields(
    _ receipts: [CloudSyncSystemFieldsReceipt], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {}

  /// Test-double compatibility. Production overrides this with the atomic
  /// metadata-guarded implementation on ``CloudKitRecordPusher``.
  public func pushAuditRecords(
    _ records: [CKRecord], guardedBy _: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    try await push(
      records, context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
  }
}

/// Narrow seam over the two `CKDatabase` mutation calls ``CloudKitRecordPusher``
/// makes (zone-ensure and record-save). Production wraps a live private
/// `CKDatabase`; tests inject a fake returning scripted per-record results so the
/// non-atomic batch contract can be verified without CloudKit. `modifyRecords`
/// exposes `atomically` explicitly because the pusher must opt OUT of CloudKit's
/// atomic default — see ``CloudKitRecordPusher/push(_:)``.
protocol CloudKitDatabaseModifying: Sendable {
  func modifyRecordZones(
    saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID]
  ) async throws -> (
    saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
    deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
  )

  func modifyRecords(
    saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy, atomically: Bool
  ) async throws -> (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
  )

  /// Fetch a single record by id, returning `nil` when it does not exist
  /// (`unknownItem`) or its zone is gone (`zoneNotFound`). Used only to read the
  /// zone-epoch metadata record (S-5). Default `nil` so the many mutation-only
  /// test fakes need no epoch wiring; production ``LiveCloudKitDatabase`` reads
  /// the real record.
  func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord?

  func allRecordZones() async throws -> [CKRecordZone]
}

extension CloudKitDatabaseModifying {
  func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? { nil }
  func allRecordZones() async throws -> [CKRecordZone] { [] }
}

/// Production ``CloudKitDatabaseModifying`` over the container's private
/// `CKDatabase`. The database handle is recomputed per call (matching CloudKit's
/// cheap container lookup) so no long-lived `CKDatabase` reference is retained.
struct LiveCloudKitDatabase: CloudKitDatabaseModifying {
  let containerIdentifier: String

  private var database: CKDatabase {
    CKContainer(identifier: containerIdentifier).privateCloudDatabase
  }

  func modifyRecordZones(
    saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID]
  ) async throws -> (
    saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
    deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
  ) {
    try await database.modifyRecordZones(
      saving: recordZonesToSave, deleting: recordZoneIDsToDelete)
  }

  func modifyRecords(
    saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
    savePolicy: CKModifyRecordsOperation.RecordSavePolicy, atomically: Bool
  ) async throws -> (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
  ) {
    try await database.modifyRecords(
      saving: recordsToSave, deleting: recordIDsToDelete, savePolicy: savePolicy,
      atomically: atomically)
  }

  func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? {
    do {
      return try await database.record(for: recordID)
    } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
      // The epoch record (or its zone) does not exist yet — a fresh / not-yet-
      // created zone. That is "no epoch signal", not a failure.
      return nil
    }
  }

  func allRecordZones() async throws -> [CKRecordZone] {
    try await database.allRecordZones()
  }
}
