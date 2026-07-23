@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync

struct CloudSyncCandidateReadbackFetchFailure: Error, Sendable {
  let failure: CloudSyncPerRecordFetchFailure
}

extension CloudSyncEngineCoordinator {
  func generationSnapshotBinding(
    accountIdentifier: String, lease: CloudSyncZoneRebuildLease
  ) throws -> GenerationSnapshotBinding {
    try GenerationSnapshotBinding(
      accountIdentifier: accountIdentifier,
      databaseInstanceIdentifier: lease.ownerIdentifier,
      candidateZoneName: lease.candidateZoneName,
      generation: lease.epoch,
      generationIdentifier: lease.generationID,
      leaseIdentifier: lease.identifier,
      leaseOwnerIdentifier: lease.ownerIdentifier)
  }

  func captureDurableCandidateSnapshot(
    sync: any EnvelopeSyncServicing, binding: GenerationSnapshotBinding,
    retention: CloudSyncCandidateRetentionCapability,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging {
    switch retention {
    case .initialActive(let authorization, _):
      return try sync.captureGenerationSnapshot(
        binding: binding, authorization: authorization,
        tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    case .staged(let authorization, _):
      return try sync.captureCandidateGenerationSnapshot(
        binding: binding, authorization: authorization,
        tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    }
  }

  func uploadDurableCandidateSnapshot(
    sync: any EnvelopeSyncServicing, binding: GenerationSnapshotBinding,
    staging initialStaging: GenerationSnapshotStaging,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool,
    retention: CloudSyncCandidateRetentionCapability
  ) async throws -> GenerationSnapshotStaging {
    var staging = initialStaging
    while staging.progress.uploadNextOrdinal < staging.manifest.recordCount {
      let offset = staging.progress.uploadNextOrdinal
      let page = try sync.stagedGenerationSnapshotPage(
        binding: binding, offset: offset,
        limit: GenerationSnapshot.maximumPageSize,
        maximumEncodedBytes: GenerationSnapshot.maximumPageEncodedBytes)
      guard page.manifest == staging.manifest, !page.envelopes.isEmpty else {
        throw CloudSyncCandidateBuildError.restartRequired
      }

      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      let auditEnvelopes = page.envelopes.filter { $0.entityType == .aiChangelog }
      let marks: [AuditRetentionCloudPresenceMarkResult]
      switch retention {
      case .initialActive(let authorization, _):
        marks = try sync.markAuditGenerationSnapshotBatchCloudPresencePossible(
          envelopes: auditEnvelopes, authorization: authorization)
      case .staged(let authorization, _):
        marks = try sync.markAuditCandidateGenerationSnapshotBatchCloudPresencePossible(
          envelopes: auditEnvelopes, authorization: authorization)
      }
      guard marks.count == auditEnvelopes.count,
        marks.allSatisfy({ $0 == .marked }), await boundaryGuard()
      else { throw CloudSyncCandidateBuildError.restartRequired }

      let records = page.envelopes.map {
        CloudSyncEnvelopeRecord.makeRecord($0, zoneID: context.zoneID)
      }
      let envelopesByRecordName = Dictionary(
        uniqueKeysWithValues: zip(records.map(\.recordID.recordName), page.envelopes))
      let results = try await pusher.push(
        records, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      let names = Set(records.map(\.recordID.recordName))
      guard results.count == records.count,
        Set(results.map(\.recordName)) == names,
        results.allSatisfy({
          $0.succeeded && $0.serverEnvelopeToApply == nil
            && $0.serverRawToDefer == nil
        })
      else { throw CloudSyncZoneEpochError.zoneEpochPendingBackfillFailed }

      let receipts = results.compactMap { result -> InboundCloudRecordReceipt? in
        guard let date = result.serverModificationDate,
          let envelope = envelopesByRecordName[result.recordName]
        else { return nil }
        return Self.inboundCloudReceipt(envelope: envelope, serverModifiedAt: date)
      }

      let next = page.nextOffset ?? staging.manifest.recordCount
      guard next > offset, next <= staging.manifest.recordCount else {
        throw CloudSyncCandidateBuildError.restartRequired
      }
      staging = try sync.advanceGenerationSnapshotUploadProgress(
        binding: binding, expectedNextOrdinal: offset, nextOrdinal: next,
        cloudReceipts: receipts)
    }
    return staging
  }

  static func inboundCloudReceipt(
    envelope: SyncEnvelope, serverModifiedAt: Date
  ) -> InboundCloudRecordReceipt {
    let timestamp = SyncTimestampFormat.formatSyncTimestamp(serverModifiedAt)
    let confirmation: Tombstone.CloudConfirmation? = envelope.operation == .delete
      ? Tombstone.CloudConfirmation(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        version: envelope.version.description, confirmedAt: timestamp)
      : nil
    return InboundCloudRecordReceipt(
      serverModifiedAt: timestamp, tombstoneConfirmation: confirmation)
  }

  func verifyDurableCandidateReadback(
    sync: any EnvelopeSyncServicing, binding: GenerationSnapshotBinding,
    staging initialStaging: GenerationSnapshotStaging,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> GenerationSnapshotStaging {
    let traversalIdentifier = binding.leaseIdentifier
    try await pusher.publishTraversalWitness(
      context: context, expectation: expectation,
      traversalIdentifier: traversalIdentifier,
      boundaryGuard: boundaryGuard)

    var staging = initialStaging
    var resetInvalidTokenOnce = false
    while !staging.progress.readbackComplete {
      let cursor = staging.progress.readbackContinuationToken.map {
        CloudSyncChangeCursor(
          accountIdentifier: binding.accountIdentifier,
          zoneName: binding.candidateZoneName, generationEpoch: binding.generation,
          generationID: binding.generationIdentifier,
          readyWitness: context.checkpointWitness,
          serverChangeTokenData: $0)
      }
      let batch: CloudSyncRemoteChangeBatch
      do {
        batch = try await fetcher.fetchChanges(
          after: cursor, context: context,
          traversalWitnessIdentifier: traversalIdentifier,
          boundaryGuard: boundaryGuard)
        try batch.assertPreservesGenerationMarkers(context: context)
      } catch let error as CKError where error.code == .changeTokenExpired {
        guard !resetInvalidTokenOnce else {
          throw CloudSyncCandidateBuildError.restartRequired
        }
        staging = try sync.resetGenerationSnapshotReadbackProgress(binding: binding)
        resetInvalidTokenOnce = true
        continue
      }
      if batch.discardedInvalidCheckpointToken {
        guard !resetInvalidTokenOnce else {
          throw CloudSyncCandidateBuildError.restartRequired
        }
        staging = try sync.resetGenerationSnapshotReadbackProgress(binding: binding)
        resetInvalidTokenOnce = true
        continue
      }
      if let failure = batch.perRecordFailure {
        throw CloudSyncCandidateReadbackFetchFailure(failure: failure)
      }
      guard let token = batch.serverChangeTokenData, !token.isEmpty else {
        throw CloudSyncZoneEpochError.zoneEpochPendingBackfillFailed
      }

      var witnesses: [GenerationSnapshotWitness] = []
      witnesses.reserveCapacity(batch.records.count)
      for record in batch.records {
        switch CloudSyncEnvelopeRecord.decode(record) {
        case .decoded(let envelope):
          let witness = try GenerationSnapshot.witness(for: envelope)
          guard witness.recordName == record.recordID.recordName else {
            throw CloudSyncCandidateBuildError.restartRequired
          }
          witnesses.append(witness)
        case .foreign:
          continue
        case .unknownEntityType, .corrupt:
          throw CloudSyncCandidateBuildError.restartRequired
        }
      }
      staging = try sync.recordGenerationSnapshotReadbackPage(
        binding: binding,
        expectedPageIndex: staging.progress.readbackPageIndex,
        witnesses: witnesses,
        deletedRecordNames: batch.deletedRecordNames,
        continuationToken: token,
        observedTraversalWitness:
          batch.observedTraversalWitnessIdentifiers.contains(traversalIdentifier),
        terminal: !batch.moreComing)
    }

    guard staging.progress.readbackWitnessObserved,
      staging.remoteManifest == staging.manifest,
      try await pusher.validateGenerationRoot(
        context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
    else { throw CloudSyncCandidateBuildError.restartRequired }
    try await pusher.deleteTraversalWitness(
      context: context, expectation: expectation,
      traversalIdentifier: traversalIdentifier,
      boundaryGuard: boundaryGuard)
    return staging
  }
}
