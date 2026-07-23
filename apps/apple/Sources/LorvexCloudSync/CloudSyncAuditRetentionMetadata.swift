import CoreFoundation
import CryptoKit
import Foundation
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

/// Single-record, generation-local authority for the audit-retention frontier
/// and the policy version that authorizes it. Keeping both in one CKRecord
/// makes every custom-zone update atomic. Every custom field is stored through
/// `CKRecord.encryptedValues`: this fixed-name record is fetched by identity and
/// no retention field needs to remain queryable in plaintext.
public struct CloudSyncAuditRetentionMetadata: Sendable, Equatable {
  public var frontier: AuditRetentionFrontierValue
  public var policy: ChangelogRetentionPolicy
  public var policyVersion: String
  public var policyAuthorizedEpoch: Int64

  public init(
    frontier: AuditRetentionFrontierValue,
    policy: ChangelogRetentionPolicy,
    policyVersion: String,
    policyAuthorizedEpoch: Int64
  ) {
    self.frontier = frontier
    self.policy = policy
    self.policyVersion = policyVersion
    self.policyAuthorizedEpoch = policyAuthorizedEpoch
  }

  public static let initial = CloudSyncAuditRetentionMetadata(
    frontier: .initial, policy: .maximum, policyVersion: "",
    policyAuthorizedEpoch: 0)

  public var canonicalDigest: String {
    let material = [
      String(frontier.epoch), frontier.minimumRetainedTimestamp,
      frontier.minimumRetainedEntityId, policy.wireValue, policyVersion,
      String(policyAuthorizedEpoch),
    ].joined(separator: "\u{0}")
    let digest = SHA256.hash(data: Data(material.utf8))
    return CloudSyncHex.lowercase(digest, capacity: SHA256.Digest.byteCount)
  }
}

enum CloudSyncAuditRetentionMetadataRecord {
  static let recordType = "LorvexAuditRetentionMetadata"
  static let recordName = "lorvex-audit-retention-metadata"
  static let protocolVersionField = "protocol_version"
  static let generationEpochField = "generation_epoch"
  static let generationIDField = "generation_id"
  static let frontierEpochField = "frontier_epoch"
  static let cutoffTimestampField = "cutoff_timestamp"
  static let cutoffEntityIDField = "cutoff_entity_id"
  static let policyField = "policy"
  static let policyVersionField = "policy_version"
  static let policyAuthorizedEpochField = "policy_authorized_epoch"
  static let protocolVersion = 1
  static let encryptedFields = [
    protocolVersionField, generationEpochField, generationIDField,
    frontierEpochField, cutoffTimestampField, cutoffEntityIDField,
    policyField, policyVersionField, policyAuthorizedEpochField,
  ]

  static func recordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  static func makeRecord(
    metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext
  ) -> CKRecord {
    let record = CKRecord(
      recordType: recordType, recordID: recordID(zoneID: context.zoneID))
    stamp(metadata, context: context, onto: record)
    return record
  }

  static func stamp(
    _ metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    onto record: CKRecord
  ) {
    precondition(isValid(metadata))
    record.encryptedValues[protocolVersionField] = protocolVersion as CKRecordValue
    record.encryptedValues[generationEpochField] = context.epoch as CKRecordValue
    record.encryptedValues[generationIDField] = context.generationID as CKRecordValue
    record.encryptedValues[frontierEpochField] = metadata.frontier.epoch as CKRecordValue
    record.encryptedValues[cutoffTimestampField] =
      metadata.frontier.minimumRetainedTimestamp as CKRecordValue
    record.encryptedValues[cutoffEntityIDField] =
      metadata.frontier.minimumRetainedEntityId as CKRecordValue
    record.encryptedValues[policyField] = metadata.policy.wireValue as CKRecordValue
    record.encryptedValues[policyVersionField] = metadata.policyVersion as CKRecordValue
    record.encryptedValues[policyAuthorizedEpochField] =
      metadata.policyAuthorizedEpoch as CKRecordValue
  }

  static func decode(
    _ record: CKRecord, context: CloudSyncGenerationContext
  ) -> CloudSyncAuditRetentionMetadata? {
    guard record.recordType == recordType,
      record.recordID == recordID(zoneID: context.zoneID),
      integer(record.encryptedValues[protocolVersionField]) == Int64(protocolVersion),
      integer(record.encryptedValues[generationEpochField]) == Int64(context.epoch),
      record.encryptedValues[generationIDField] as? String == context.generationID,
      let frontierEpoch = integer(record.encryptedValues[frontierEpochField]),
      let cutoffTimestamp = record.encryptedValues[cutoffTimestampField] as? String,
      let cutoffEntityID = record.encryptedValues[cutoffEntityIDField] as? String,
      let policyRaw = record.encryptedValues[policyField] as? String,
      let policyVersion = record.encryptedValues[policyVersionField] as? String,
      let policyAuthorizedEpoch = integer(
        record.encryptedValues[policyAuthorizedEpochField])
    else { return nil }
    let policy = ChangelogRetentionPolicy.parse(policyRaw)
    guard policy.wireValue == policyRaw else { return nil }
    let value = CloudSyncAuditRetentionMetadata(
      frontier: AuditRetentionFrontierValue(
        epoch: frontierEpoch,
        minimumRetainedTimestamp: cutoffTimestamp,
        minimumRetainedEntityId: cutoffEntityID),
      policy: policy, policyVersion: policyVersion,
      policyAuthorizedEpoch: policyAuthorizedEpoch)
    return isValid(value) ? value : nil
  }

  static func isValid(_ metadata: CloudSyncAuditRetentionMetadata) -> Bool {
    let frontier = metadata.frontier
    guard frontier.epoch >= 0,
      metadata.policyAuthorizedEpoch == frontier.epoch,
      frontier.minimumRetainedTimestamp.utf8.count <= 128,
      frontier.minimumRetainedEntityId.utf8.count <= 512,
      metadata.policyVersion.utf8.count <= 256
    else { return false }
    if frontier.minimumRetainedTimestamp.isEmpty {
      guard frontier.minimumRetainedEntityId.isEmpty else { return false }
    } else if SyncTimestamp.parse(frontier.minimumRetainedTimestamp)?.asString
      != frontier.minimumRetainedTimestamp
    { return false }
    if !metadata.policyVersion.isEmpty {
      guard let version = try? Hlc.parseCanonical(metadata.policyVersion),
        Hlc.isOperationallyAcceptableWire(version)
      else { return false }
    }
    return true
  }

  private static func integer(_ raw: CKRecordValue?) -> Int64? {
    guard let number = raw as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(), !CFNumberIsFloatType(number)
    else { return nil }
    let value = number.int64Value
    return value >= 0 ? value : nil
  }
}

extension CloudKitRecordPusher {
  /// Atomically serialize append-only audit uploads with the exact retention
  /// authority the coordinator confirmed. Re-saving the unchanged metadata
  /// record advances its change tag; the returned record becomes the guard for
  /// the next page in this call. A concurrent frontier advance therefore lands
  /// either wholly before an audit batch (which then fails stale) or wholly
  /// after it (and its subsequent purge sees the uploaded identity).
  public func pushAuditRecords(
    _ records: [CKRecord], guardedBy metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    if records.isEmpty { return [] }
    guard records.allSatisfy(Self.hasOperationalWireVersion) else {
      throw CloudSyncOperationalWireCeilingExceeded()
    }
    guard context.matches(expectation),
      CloudSyncAuditRetentionMetadataRecord.isValid(metadata),
      records.allSatisfy({ record in
        guard record.recordID.zoneID == context.zoneID,
          case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(record)
        else { return false }
        return envelope.entityType == .aiChangelog && envelope.operation == .upsert
      })
    else { throw CloudSyncGenerationBoundaryCrossed() }

    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    let guardID = CloudSyncAuditRetentionMetadataRecord.recordID(zoneID: context.zoneID)
    guard let fetchedGuard = try await database.fetchRecord(with: guardID) else {
      throw CloudSyncAuditRetentionGuardError.missing
    }
    guard CloudSyncAuditRetentionMetadataRecord.decode(
      fetchedGuard, context: context) == metadata
    else { throw CloudSyncAuditRetentionGuardError.stale }

    let prepared = await prepareForPush(records, context: context)
    let result = try await pushAuditPages(
      prepared, guardRecord: fetchedGuard, metadata: metadata,
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    return result.results
  }

  private func pushAuditPages(
    _ records: [CKRecord], guardRecord: CKRecord,
    metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> (results: [CloudSyncPushResult], guardRecord: CKRecord) {
    let maximumAuditRecordsPerBatch = CloudSyncEngineCoordinator.maxPushBatchSize - 1
    guard records.count > maximumAuditRecordsPerBatch else {
      return try await pushOneAtomicAuditBatch(
        records, guardRecord: guardRecord, metadata: metadata,
        context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
    }
    let head = Array(records.prefix(maximumAuditRecordsPerBatch))
    let tail = Array(records.dropFirst(maximumAuditRecordsPerBatch))
    let first = try await pushOneAtomicAuditBatch(
      head, guardRecord: guardRecord, metadata: metadata,
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    let second = try await pushAuditPages(
      tail, guardRecord: first.guardRecord, metadata: metadata,
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    return (first.results + second.results, second.guardRecord)
  }

  private func pushOneAtomicAuditBatch(
    _ records: [CKRecord], guardRecord: CKRecord,
    metadata: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> (results: [CloudSyncPushResult], guardRecord: CKRecord) {
    precondition(!records.isEmpty)
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    CloudSyncAuditRetentionMetadataRecord.stamp(
      metadata, context: context, onto: guardRecord)

    let saveResults: [CKRecord.ID: Result<CKRecord, any Error>]
    do {
      (saveResults, _) = try await database.modifyRecords(
        saving: [guardRecord] + records, deleting: [],
        savePolicy: .ifServerRecordUnchanged, atomically: true)
    } catch is CloudSyncGenerationBoundaryCrossed {
      throw CloudSyncGenerationBoundaryCrossed()
    } catch is CloudSyncAccountBoundaryCrossed {
      throw CloudSyncAccountBoundaryCrossed()
    } catch let error as CKError where error.code == .limitExceeded {
      guard records.count > 1 else {
        return (
          [
            CloudSyncPushResult(
              recordName: records[0].recordID.recordName, succeeded: false,
              errorMessage:
                "audit record exceeds CloudKit's guarded request size limit: "
                + error.localizedDescription)
          ],
          guardRecord)
      }
      let midpoint = records.count / 2
      let first = try await pushOneAtomicAuditBatch(
        Array(records[..<midpoint]), guardRecord: guardRecord, metadata: metadata,
        context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      let second = try await pushOneAtomicAuditBatch(
        Array(records[midpoint...]), guardRecord: first.guardRecord,
        metadata: metadata, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      return (first.results + second.results, second.guardRecord)
    } catch {
      throw CloudSyncAuditRetentionGuardError.transport(error.localizedDescription)
    }

    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    let guardID = guardRecord.recordID
    guard let guardResult = saveResults[guardID] else {
      throw CloudSyncAuditRetentionGuardError.invalidAtomicResult
    }
    switch guardResult {
    case .success(let savedGuard):
      guard CloudSyncAuditRetentionMetadataRecord.decode(
        savedGuard, context: context) == metadata
      else { throw CloudSyncAuditRetentionGuardError.invalidAtomicResult }
      var results: [CloudSyncPushResult] = []
      results.reserveCapacity(records.count)
      for record in records {
        guard let result = saveResults[record.recordID],
          case .success(let savedRecord) = result
        else { throw CloudSyncAuditRetentionGuardError.invalidAtomicResult }
        await cacheSystemFields(of: savedRecord, context: context)
        results.append(
          CloudSyncPushResult(
            recordName: record.recordID.recordName, succeeded: true,
            serverModificationDate: savedRecord.modificationDate))
      }
      return (results, savedGuard)

    case .failure(let error):
      guard let ckError = error as? CKError else {
        throw CloudSyncAuditRetentionGuardError.transport(
          error.localizedDescription)
      }
      switch ckError.code {
      case .serverRecordChanged:
        throw CloudSyncAuditRetentionGuardError.stale
      case .unknownItem, .zoneNotFound, .userDeletedZone:
        throw CloudSyncAuditRetentionGuardError.missing
      case .batchRequestFailed:
        // The guard itself did not lose its CAS; an entity in this atomic batch
        // failed. Bisect until each poison/conflict is isolated without charging
        // healthy siblings or weakening the metadata fence.
        if records.count > 1 {
          let midpoint = records.count / 2
          let first = try await pushOneAtomicAuditBatch(
            Array(records[..<midpoint]), guardRecord: guardRecord,
            metadata: metadata, context: context, expectation: expectation,
            boundaryGuard: boundaryGuard)
          let second = try await pushOneAtomicAuditBatch(
            Array(records[midpoint...]), guardRecord: first.guardRecord,
            metadata: metadata, context: context, expectation: expectation,
            boundaryGuard: boundaryGuard)
          return (first.results + second.results, second.guardRecord)
        }
        return try await resolveSingleAuditBatchFailure(
          record: records[0], saveResults: saveResults,
          guardRecord: guardRecord, context: context)
      default:
        throw CloudSyncAuditRetentionGuardError.transport(
          ckError.localizedDescription)
      }
    }
  }

  private func resolveSingleAuditBatchFailure(
    record: CKRecord,
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    guardRecord: CKRecord,
    context: CloudSyncGenerationContext
  ) async throws -> (results: [CloudSyncPushResult], guardRecord: CKRecord) {
    guard let result = saveResults[record.recordID] else {
      throw CloudSyncAuditRetentionGuardError.invalidAtomicResult
    }
    switch result {
    case .success:
      throw CloudSyncAuditRetentionGuardError.invalidAtomicResult
    case .failure(let error):
      if let ckError = error as? CKError, ckError.code == .serverRecordChanged,
        let server = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
        let client = ckError.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord
      {
        let recordName = record.recordID.recordName
        guard server.recordType == CloudSyncEnvelopeRecord.recordType,
          client.recordType == CloudSyncEnvelopeRecord.recordType,
          server.recordID == record.recordID,
          client.recordID == record.recordID,
          CloudSyncEnvelopeRecord.hasIdenticalEnvelopeIdentity(client, server),
          let localVersion = CloudSyncEnvelopeRecord.versionString(from: client),
          (try? Hlc.parseCanonical(localVersion)) != nil
        else {
          return (
            [
              CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage:
                  "guarded audit conflict returned a foreign or mismatched record slot")
            ],
            guardRecord)
        }
        let serverVersion = CloudSyncEnvelopeRecord.versionString(from: server) ?? ""
        switch resolveCloudSyncPushConflict(
          localVersion: localVersion, serverVersion: serverVersion)
        {
        case .equalConfirm:
          switch (CloudSyncEnvelopeRecord.decode(client), CloudSyncEnvelopeRecord.decode(server)) {
          case (.decoded(let localEnvelope), .decoded(let serverEnvelope)):
            do {
              if try SyncMutationSemantics.isExactSemanticReplay(
                localEnvelope, serverEnvelope)
              {
                await cacheSystemFields(of: server, context: context)
                return (
                  [
                    CloudSyncPushResult(
                      recordName: recordName, succeeded: true,
                      serverModificationDate: server.modificationDate)
                  ],
                  guardRecord)
              }
            } catch {
              return (
                [
                  CloudSyncPushResult(
                    recordName: recordName, succeeded: false,
                    errorMessage:
                      "guarded audit semantic comparison failed: \(error)")
                ],
                guardRecord)
            }
            return (
              [
                CloudSyncPushResult(
                  recordName: recordName, succeeded: false,
                  collision: .equalVersion(serverEnvelope: serverEnvelope),
                  systemFieldsReceipt: reconciliationReceipt(for: server))
              ],
              guardRecord)
          case (_, .corrupt):
            return (
              [
                CloudSyncPushResult(
                  recordName: recordName, succeeded: false,
                  collision: .corruptServerSlot(
                    serverVersionFloor: try? Hlc.parseCanonical(serverVersion)),
                  systemFieldsReceipt: reconciliationReceipt(for: server))
              ],
              guardRecord)
          default:
            break
          }
        case .corruptServerSlot:
          return (
            [
              CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                collision: .corruptServerSlot(serverVersionFloor: nil),
                systemFieldsReceipt: reconciliationReceipt(for: server))
            ],
            guardRecord)
        case .localWinsResaveOntoServer, .serverWinsConfirmAndApply:
          switch CloudSyncEnvelopeRecord.decode(server) {
          case .decoded(let serverEnvelope):
            return (
              [
                CloudSyncPushResult(
                  recordName: recordName, succeeded: false,
                  collision: .immutableIdentity(serverEnvelope: serverEnvelope),
                  systemFieldsReceipt: reconciliationReceipt(for: server))
              ],
              guardRecord)
          case .corrupt:
            return (
              [
                CloudSyncPushResult(
                  recordName: recordName, succeeded: false,
                  collision: .corruptServerSlot(
                    serverVersionFloor: try? Hlc.parseCanonical(serverVersion)),
                  systemFieldsReceipt: reconciliationReceipt(for: server))
              ],
              guardRecord)
          case .unknownEntityType, .foreign:
            break
          }
        }
      }
      if let ckError = error as? CKError, ckError.code == .unknownItem {
        await systemFieldsStore.remove(
          accountIdentifier: context.accountIdentifier,
          zoneName: context.zoneName,
          recordName: record.recordID.recordName)
      }
      return (
        [
          CloudSyncPushResult(
            recordName: record.recordID.recordName, succeeded: false,
            errorMessage: error.localizedDescription,
            isTransient: CloudSyncTransientClassifier.isTransient(error)
              || (error as? CKError)?.code == .unknownItem)
        ],
        guardRecord)
    }
  }

  public func readAuditRetentionMetadata(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata? {
    guard context.matches(expectation) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    let record = try await database.fetchRecord(
      with: CloudSyncAuditRetentionMetadataRecord.recordID(zoneID: context.zoneID))
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    guard let record else { return nil }
    guard let metadata = CloudSyncAuditRetentionMetadataRecord.decode(
      record, context: context)
    else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
    return metadata
  }

  public func mergeAuditRetentionMetadata(
    _ proposed: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata {
    guard context.matches(expectation),
      CloudSyncAuditRetentionMetadataRecord.isValid(proposed)
    else { throw CloudSyncZoneEpochError.generationMarkerMismatch }

    for _ in 0..<Self.maxZoneEpochCASAttempts {
      try await assertRequestBoundary(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)
      let existing = try await database.fetchRecord(
        with: CloudSyncAuditRetentionMetadataRecord.recordID(zoneID: context.zoneID))
      try await assertRequestBoundary(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)

      let merged: CloudSyncAuditRetentionMetadata
      let record: CKRecord
      if let existing {
        guard let remote = CloudSyncAuditRetentionMetadataRecord.decode(
          existing, context: context)
        else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
        merged = try Self.mergeRetentionMetadata(remote, proposed)
        record = existing
        CloudSyncAuditRetentionMetadataRecord.stamp(
          merged, context: context, onto: record)
      } else {
        merged = proposed
        record = CloudSyncAuditRetentionMetadataRecord.makeRecord(
          metadata: merged, context: context)
      }

      try await assertRequestBoundary(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)
      let (saveResults, _) = try await database.modifyRecords(
        saving: [record], deleting: [],
        savePolicy: .ifServerRecordUnchanged, atomically: false)
      try await assertRequestBoundary(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)
      guard let result = saveResults[record.recordID] else {
        throw CloudSyncZoneEpochError.generationMarkerMismatch
      }
      switch result {
      case .success(let saved):
        guard let decoded = CloudSyncAuditRetentionMetadataRecord.decode(
          saved, context: context), decoded == merged
        else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
        return decoded
      case .failure(let error):
        if let ckError = error as? CKError,
          ckError.code == .serverRecordChanged || ckError.code == .unknownItem
        {
          continue
        }
        throw error
      }
    }
    throw CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
  }

  /// Join the independently monotonic frontier and policy-version dimensions.
  /// A policy edit can race a generation-advancing edit from an older policy,
  /// so the newer policy is allowed to authorize the maximum observed frontier
  /// even when it was originally proposed at a lower epoch. The frontier never
  /// decreases, which preserves the no-resurrection fence; requiring the policy
  /// source to have already observed that epoch would instead permanently wedge
  /// a legitimate concurrent pair. Equal-version/different-value state is
  /// corruption, but failing before the CAS would wedge every future cycle. Join
  /// it with the domain's conservative, data-preserving policy rule instead.
  static func mergeRetentionMetadata(
    _ lhs: CloudSyncAuditRetentionMetadata,
    _ rhs: CloudSyncAuditRetentionMetadata
  ) throws -> CloudSyncAuditRetentionMetadata {
    let policyOrdering = try Self.comparePolicyVersion(
      lhs.policyVersion, rhs.policyVersion)
    let policy: ChangelogRetentionPolicy
    let policyVersion: String
    switch policyOrdering {
    case 0:
      policy = ChangelogRetentionPolicy.conservativeCollisionWinner(
        lhs.policy, rhs.policy)
      policyVersion = lhs.policyVersion
    case ..<0:
      policy = rhs.policy
      policyVersion = rhs.policyVersion
    default:
      policy = lhs.policy
      policyVersion = lhs.policyVersion
    }
    let frontier = max(lhs.frontier, rhs.frontier)
    return CloudSyncAuditRetentionMetadata(
      frontier: frontier, policy: policy, policyVersion: policyVersion,
      policyAuthorizedEpoch: frontier.epoch)
  }

  private static func comparePolicyVersion(_ lhs: String, _ rhs: String) throws -> Int {
    let left = try Self.canonicalPolicyVersion(lhs)
    let right = try Self.canonicalPolicyVersion(rhs)
    switch (left, right) {
    case (nil, nil): return 0
    case (nil, .some): return -1
    case (.some, nil): return 1
    case (.some(let left), .some(let right)):
      if left < right { return -1 }
      if left > right { return 1 }
      return 0
    }
  }

  private static func canonicalPolicyVersion(_ raw: String) throws -> Hlc? {
    if raw.isEmpty { return nil }
    guard let parsed = try? Hlc.parseCanonical(raw),
      Hlc.isOperationallyAcceptableWire(parsed)
    else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    return parsed
  }
}
