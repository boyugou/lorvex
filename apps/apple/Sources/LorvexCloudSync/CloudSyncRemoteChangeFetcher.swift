@preconcurrency import CloudKit
import CryptoKit
import Foundation
import LorvexCore
import LorvexSync

/// A CloudKit zone-changes page that could not materialize every record.
/// Advancing the page token would permanently skip the missing record, while
/// retrying the same unadvanced page inside one trigger would spin. Coordinators
/// therefore throw this typed result to the app-level pacing layer and retry the
/// exact page on a later trigger.
public struct CloudSyncPerRecordFetchFailure: Error, LocalizedError, Sendable, Equatable {
  public enum Kind: String, Sendable, Equatable {
    case transient
    case persistent
  }

  public let failedRecordCount: Int
  public let failedRecordNames: [String]
  public let cloudKitErrorCodes: [Int]
  public let kind: Kind
  public let retryAfter: TimeInterval?
  public let checkpointFingerprint: String

  public init(
    failedRecordCount: Int,
    failedRecordNames: [String] = [],
    cloudKitErrorCodes: [Int] = [],
    kind: Kind = .persistent,
    retryAfter: TimeInterval? = nil,
    checkpointFingerprint: String = "unknown"
  ) {
    self.failedRecordCount = failedRecordCount
    self.failedRecordNames = failedRecordNames
    self.cloudKitErrorCodes = cloudKitErrorCodes
    self.kind = kind
    self.retryAfter = retryAfter
    self.checkpointFingerprint = checkpointFingerprint
  }

  public var errorDescription: String? {
    "CloudKit could not fetch \(failedRecordCount) record(s); the page will retry."
  }

  func bound(to checkpointFingerprint: String) -> Self {
    Self(
      failedRecordCount: failedRecordCount,
      failedRecordNames: failedRecordNames,
      cloudKitErrorCodes: cloudKitErrorCodes,
      kind: kind,
      retryAfter: retryAfter,
      checkpointFingerprint: checkpointFingerprint)
  }

  /// A candidate record that CloudKit reports as absent makes that immutable
  /// namespace unverifiable; a fresh candidate is meaningful recovery. Other
  /// persistent codes (entitlement, permission, malformed request, internal
  /// fault) are global/configuration failures that namespace churn cannot fix.
  var requiresCandidateNamespaceRestart: Bool {
    cloudKitErrorCodes.contains(CKError.Code.unknownItem.rawValue)
  }
}

public struct CloudSyncRemoteChangeBatch: @unchecked Sendable {
  public var records: [CKRecord]
  /// CloudKit-level physical deletions in this page, by opaque record name.
  /// Ordinary Lorvex deletes use marked `delete` envelopes, but an
  /// authoritative nil-token snapshot also consumes these so a record staged on
  /// an earlier page cannot remain falsely present after a concurrent physical
  /// deletion.
  public var deletedRecordNames: [String]
  public var serverChangeTokenData: Data?
  public var perRecordFailure: CloudSyncPerRecordFetchFailure?
  public var moreComing: Bool
  /// Marker observations from this exact page. Baseline traversal accumulates
  /// them and refuses terminal enrollment unless both match the descriptor.
  public var observedGenerationRoot: Bool
  public var observedReadyWitness: String?
  /// Fully validated traversal-witness ids observed in this page. The
  /// coordinator selects the exact id it created for this traversal.
  public var observedTraversalWitnessIdentifiers: [String]
  /// CloudKit-owned modificationDate for each validated traversal witness.
  /// Core promotes the exact selected timestamp to recovery authority only
  /// when the same traversal commits its terminal page.
  public var traversalWitnessServerModificationDates: [String: Date]
  /// The supplied cursor carried an undecodable archived CloudKit token. The
  /// fetch therefore started from nil; the coordinator must atomically restart
  /// the exact staged traversal before consuming this page.
  public var discardedInvalidCheckpointToken: Bool

  public init(
    records: [CKRecord],
    deletedRecordNames: [String] = [],
    serverChangeTokenData: Data?,
    perRecordFailure: CloudSyncPerRecordFetchFailure? = nil,
    moreComing: Bool,
    observedGenerationRoot: Bool = false,
    observedReadyWitness: String? = nil,
    observedTraversalWitnessIdentifiers: [String] = [],
    traversalWitnessServerModificationDates: [String: Date] = [:],
    discardedInvalidCheckpointToken: Bool = false
  ) {
    self.records = records
    self.deletedRecordNames = deletedRecordNames
    self.serverChangeTokenData = serverChangeTokenData
    self.perRecordFailure = perRecordFailure
    self.moreComing = moreComing
    self.observedGenerationRoot = observedGenerationRoot
    self.observedReadyWitness = observedReadyWitness
    self.observedTraversalWitnessIdentifiers = observedTraversalWitnessIdentifiers
    self.traversalWitnessServerModificationDates =
      traversalWitnessServerModificationDates
    self.discardedInvalidCheckpointToken = discardedInvalidCheckpointToken
  }

  /// A physical delete of an active generation marker invalidates the page's
  /// authority even when the default-zone control record still names the same
  /// descriptor. Without this check a terminal baseline could destructively
  /// reconcile local rows after the custom-zone root or seal disappeared in the
  /// gap between the cycle's direct marker validation and this page fetch.
  func assertPreservesGenerationMarkers(
    context: CloudSyncGenerationContext
  ) throws {
    let deleted = Set(deletedRecordNames)
    guard !deleted.contains(CloudSyncGenerationRootRecord.recordName) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    if context.readyWitness != nil,
      deleted.contains(CloudSyncGenerationSealRecord.recordName)
    {
      throw CloudSyncGenerationBoundaryCrossed()
    }
  }
}

public protocol CloudSyncRemoteChangeFetching: Sendable {
  func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier: String?,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch
}

public actor CloudKitRemoteChangeFetcher: CloudSyncRemoteChangeFetching {
  private let containerIdentifier: String

  public init(
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier
  ) {
    self.containerIdentifier = containerIdentifier
  }

  public func fetchChanges(
    after checkpoint: CloudSyncChangeCursor?,
    context: CloudSyncGenerationContext,
    traversalWitnessIdentifier _: String?,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncRemoteChangeBatch {
    guard await boundaryGuard?() ?? true else {
      throw CloudSyncAccountBoundaryCrossed()
    }
    let checkpointMatchesContext = checkpoint.map {
      return $0.accountIdentifier == context.accountIdentifier
        && $0.zoneName == context.zoneName
        && $0.generationEpoch == context.epoch
        && $0.generationID == context.generationID
        && $0.readyWitness == context.checkpointWitness
    } ?? true
    let acceptedCheckpoint = checkpointMatchesContext ? checkpoint : nil
    let token = acceptedCheckpoint.flatMap(Self.serverChangeToken(from:))
    let discardedInvalidCheckpointToken = checkpoint != nil
      && (!checkpointMatchesContext || token == nil)
    let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    let changes = try await database.recordZoneChanges(
      inZoneWith: context.zoneID,
      since: token,
      desiredKeys: nil,
      // Keep every CloudKit page within the durable readback contract. Leaving
      // this nil lets the service choose a dynamic size that may exceed the
      // bounded page accepted by GenerationSnapshot.recordReadbackPage.
      resultsLimit: GenerationSnapshot.maximumPageSize
    )
    guard await boundaryGuard?() ?? true else {
      throw CloudSyncAccountBoundaryCrossed()
    }
    // Peer deletes normally ride as marked tombstone envelopes. Physical
    // CloudKit deletions still matter to an authoritative snapshot inventory:
    // remove a record staged on an earlier page rather than finalizing against a
    // stale union. Normal incremental apply otherwise ignores these identities.
    let (records, unboundPerRecordFailure) = Self.partitionModifications(
      changes.modificationResultsByID)
    let perRecordFailure = unboundPerRecordFailure.map {
      $0.bound(to: Self.checkpointFingerprint(acceptedCheckpoint))
    }
    guard records.allSatisfy({ $0.recordID.zoneID == context.zoneID }),
      changes.deletions.allSatisfy({ $0.recordID.zoneID == context.zoneID })
    else { throw CloudSyncGenerationBoundaryCrossed() }
    let observations = try Self.validateReservedRecords(records, context: context)
    return Self.makeBatch(
      records: records,
      deletedRecordNames: changes.deletions.map { $0.recordID.recordName }.sorted(),
      perRecordFailure: perRecordFailure,
      changeTokenData: try Self.data(from: changes.changeToken),
      moreComing: changes.moreComing,
      observedGenerationRoot: observations.sawRoot,
      observedReadyWitness: observations.readyWitness,
      observedTraversalWitnessIdentifiers: observations.traversalIdentifiers,
      traversalWitnessServerModificationDates:
        observations.traversalServerModificationDates,
      discardedInvalidCheckpointToken: discardedInvalidCheckpointToken
    )
  }

  /// Split a page's per-record modification results into the successfully-fetched
  /// records (sorted by record name for a stable apply order) and a flag for
  /// whether ANY per-record fetch failed.
  static func partitionModifications(
    _ results: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>]
  ) -> (records: [CKRecord], perRecordFailure: CloudSyncPerRecordFetchFailure?) {
    var records: [CKRecord] = []
    var failureCount = 0
    var failedRecordNames: [String] = []
    var cloudKitErrorCodes = Set<Int>()
    var allFailuresTransient = true
    var retryAfter: TimeInterval?
    for (recordID, result) in results {
      switch result {
      case .success(let modification): records.append(modification.record)
      case .failure(let error):
        failureCount += 1
        failedRecordNames.append(recordID.recordName)
        allFailuresTransient = allFailuresTransient
          && CloudSyncTransientClassifier.isTransient(error)
        let nsError = error as NSError
        if nsError.domain == CKErrorDomain {
          cloudKitErrorCodes.insert(nsError.code)
        }
        if let candidate = CloudSyncTransientClassifier.serverRetryAfter(error) {
          retryAfter = max(retryAfter ?? candidate, candidate)
        }
      }
    }
    records.sort { $0.recordID.recordName < $1.recordID.recordName }
    failedRecordNames.sort()
    let failure = failureCount > 0
      ? CloudSyncPerRecordFetchFailure(
        failedRecordCount: failureCount,
        failedRecordNames: failedRecordNames,
        cloudKitErrorCodes: cloudKitErrorCodes.sorted(),
        kind: allFailuresTransient ? .transient : .persistent,
        retryAfter: retryAfter)
      : nil
    return (records, failure)
  }

  /// Assemble the fetch batch, applying the SY7 no-advance-on-failure rule.
  ///
  /// A per-record fetch FAILURE must not be skipped past: `recordZoneChanges`
  /// still returns an advanced change token for the page, but a record that
  /// failed to materialize is not in it, so persisting that token would move the
  /// checkpoint permanently past the missing record and lose it. When any
  /// per-record failure occurred we WITHHOLD the advanced token (`nil`, which the
  /// coordinator reads as "do not advance the checkpoint") and force
  /// `moreComing == false` so the drain loop stops rather than re-pulling this
  /// same unadvanced page. The successfully fetched records remain in the batch
  /// for diagnostics, but every coordinator path rejects the whole page before
  /// apply or staging. That page-atomic rule prevents a partial authoritative
  /// inventory and lets the next cycle retry the exact same CloudKit page.
  static func makeBatch(
    records: [CKRecord], deletedRecordNames: [String] = [],
    perRecordFailure: CloudSyncPerRecordFetchFailure?,
    changeTokenData: Data, moreComing: Bool,
    observedGenerationRoot: Bool = false,
    observedReadyWitness: String? = nil,
    observedTraversalWitnessIdentifiers: [String] = [],
    traversalWitnessServerModificationDates: [String: Date] = [:],
    discardedInvalidCheckpointToken: Bool = false
  ) -> CloudSyncRemoteChangeBatch {
    CloudSyncRemoteChangeBatch(
      records: records,
      deletedRecordNames: deletedRecordNames,
      serverChangeTokenData: perRecordFailure == nil ? changeTokenData : nil,
      perRecordFailure: perRecordFailure,
      moreComing: perRecordFailure == nil ? moreComing : false,
      observedGenerationRoot: observedGenerationRoot,
      observedReadyWitness: observedReadyWitness,
      observedTraversalWitnessIdentifiers: observedTraversalWitnessIdentifiers,
      traversalWitnessServerModificationDates:
        traversalWitnessServerModificationDates,
      discardedInvalidCheckpointToken: discardedInvalidCheckpointToken
    )
  }

  private static func serverChangeToken(from checkpoint: CloudSyncChangeCursor)
    -> CKServerChangeToken?
  {
    try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: CKServerChangeToken.self,
      from: checkpoint.serverChangeTokenData
    )
  }

  private static func checkpointFingerprint(
    _ checkpoint: CloudSyncChangeCursor?
  ) -> String {
    guard let data = checkpoint?.serverChangeTokenData else { return "baseline" }
    let digest = CloudSyncHex.lowercase(
      SHA256.hash(data: data), capacity: SHA256.Digest.byteCount)
    return String(digest.prefix(16))
  }

  private static func data(from token: CKServerChangeToken) throws -> Data {
    try NSKeyedArchiver.archivedData(
      withRootObject: token,
      requiringSecureCoding: true
    )
  }

  private static func validateReservedRecords(
    _ records: [CKRecord], context: CloudSyncGenerationContext
  ) throws -> (
    sawRoot: Bool, readyWitness: String?, traversalIdentifiers: [String],
    traversalServerModificationDates: [String: Date]
  ) {
    var sawRoot = false
    var readyWitness: String?
    var traversalIdentifiers = Set<String>()
    var traversalServerModificationDates: [String: Date] = [:]
    for record in records {
      if record.recordID.recordName == CloudSyncGenerationRootRecord.recordName
        || record.recordType == CloudSyncGenerationRootRecord.recordType
      {
        let valid: Bool
        if let witness = context.readyWitness {
          valid = CloudSyncGenerationRootRecord.matches(
            record,
            descriptor: CloudSyncGenerationDescriptor(
              epoch: context.epoch, generationID: context.generationID,
              zoneName: context.zoneName, readyWitness: witness,
              tombstoneCompactionCutoff: context.tombstoneCompactionCutoff))
        } else if let lease = context.rebuildLease {
          valid = CloudSyncGenerationRootRecord.matches(record, lease: lease)
        } else {
          valid = false
        }
        guard valid else { throw CloudSyncGenerationBoundaryCrossed() }
        sawRoot = true
        continue
      }
      if record.recordID.recordName == CloudSyncGenerationSealRecord.recordName
        || record.recordType == CloudSyncGenerationSealRecord.recordType
      {
        guard let witness = context.readyWitness else {
          // Candidate readback happens before sealing. Any seal already present
          // belongs to a stale/partially reused candidate and must fail closed.
          throw CloudSyncGenerationBoundaryCrossed()
        }
        let descriptor = CloudSyncGenerationDescriptor(
          epoch: context.epoch, generationID: context.generationID,
          zoneName: context.zoneName, readyWitness: witness,
          tombstoneCompactionCutoff: context.tombstoneCompactionCutoff)
        guard CloudSyncGenerationSealRecord.matches(record, descriptor: descriptor) else {
          throw CloudSyncGenerationBoundaryCrossed()
        }
        readyWitness = witness
        continue
      }
      if record.recordID.recordName.hasPrefix(
        CloudSyncTraversalWitnessRecord.recordNamePrefix)
        || record.recordType == CloudSyncTraversalWitnessRecord.recordType
      {
        guard let traversalIdentifier =
          record[CloudSyncTraversalWitnessRecord.traversalIdentifierField] as? String,
          CloudSyncGenerationNaming.isValidIdentifier(traversalIdentifier),
          CloudSyncTraversalWitnessRecord.matches(
            record, context: context,
            traversalIdentifier: traversalIdentifier)
        else { throw CloudSyncGenerationBoundaryCrossed() }
        traversalIdentifiers.insert(traversalIdentifier)
        if let modifiedAt = record.modificationDate {
          traversalServerModificationDates[traversalIdentifier] = modifiedAt
        }
      }
    }
    return (
      sawRoot, readyWitness, traversalIdentifiers.sorted(),
      traversalServerModificationDates)
  }
}
