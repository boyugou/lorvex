import Foundation
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  /// Concrete service bridge for an initial active-zone durable capture.
  public func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: try LocalChangeSeq.read(db))
    }
  }

  public func captureGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionOutboundAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.capture(
        db, binding: binding, authorization: authorization,
        sourceLocalChangeSequence: try LocalChangeSeq.read(db),
        tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    }
  }

  /// Concrete service bridge for a replacement candidate durable capture.
  public func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: try LocalChangeSeq.read(db))
    }
  }

  public func captureCandidateGenerationSnapshot(
    binding: GenerationSnapshotBinding,
    authorization: AuditRetentionCandidateAuthorization,
    tombstoneCompactionCutoff: String?
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.capture(
        db, binding: binding, candidateAuthorization: authorization,
        sourceLocalChangeSequence: try LocalChangeSeq.read(db),
        tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    }
  }

  /// Return one count-and-byte-bounded immutable staged page.
  public func stagedGenerationSnapshotPage(
    binding: GenerationSnapshotBinding, offset: Int,
    limit: Int = GenerationSnapshot.maximumPageSize,
    maximumEncodedBytes: Int = GenerationSnapshot.maximumPageEncodedBytes
  ) throws -> GenerationSnapshotPage {
    try read { db in
      try GenerationSnapshot.stagedPage(
        db, binding: binding, offset: offset, limit: limit,
        maximumEncodedBytes: maximumEncodedBytes)
    }
  }

  /// Read the durable state for the exact bound lease, if it exists.
  public func generationSnapshotStaging(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging? {
    try read { db in try GenerationSnapshot.staging(db, binding: binding) }
  }

  /// Read an unfinished/published singleton staging lease for exact remote
  /// descriptor reconciliation after relaunch.
  public func currentGenerationSnapshotStaging() throws -> GenerationSnapshotStaging? {
    try read { db in try GenerationSnapshot.currentStaging(db) }
  }

  /// Compare-and-swap the first ordinal not yet confirmed uploaded.
  public func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.advanceUploadProgress(
        db, binding: binding, expectedNextOrdinal: expectedNextOrdinal,
        nextOrdinal: nextOrdinal)
    }
  }

  public func advanceGenerationSnapshotUploadProgress(
    binding: GenerationSnapshotBinding, expectedNextOrdinal: Int,
    nextOrdinal: Int, cloudReceipts: [InboundCloudRecordReceipt]
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      for receipt in cloudReceipts {
        try Tombstone.observeTrustedServerTime(
          db, accountIdentifier: binding.accountIdentifier,
          serverTime: receipt.serverModifiedAt)
      }
      return try GenerationSnapshot.recordUploadProgressAndReceipts(
        db, binding: binding, expectedNextOrdinal: expectedNextOrdinal,
        nextOrdinal: nextOrdinal,
        tombstoneConfirmations: cloudReceipts.compactMap(\.tombstoneConfirmation))
    }
  }

  /// Atomically persist one readback page, its token, and terminal proof state.
  public func recordGenerationSnapshotReadbackPage(
    binding: GenerationSnapshotBinding, expectedPageIndex: Int,
    witnesses: [GenerationSnapshotWitness], deletedRecordNames: [String],
    continuationToken: Data, observedTraversalWitness: Bool, terminal: Bool
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.recordReadbackPage(
        db, binding: binding, expectedPageIndex: expectedPageIndex,
        witnesses: witnesses, deletedRecordNames: deletedRecordNames,
        continuationToken: continuationToken,
        observedTraversalWitness: observedTraversalWitness, terminal: terminal)
    }
  }

  /// Discard remote witnesses and restart candidate-zone traversal from page zero.
  public func resetGenerationSnapshotReadbackProgress(
    binding: GenerationSnapshotBinding
  ) throws -> GenerationSnapshotStaging {
    try write { db in
      try GenerationSnapshot.resetReadbackProgress(db, binding: binding)
    }
  }

  /// Atomically activate a proven candidate (or verify an active bootstrap)
  /// and delete the exact durable staging lease.
  public func finalizePublishedGenerationSnapshot(
    binding: GenerationSnapshotBinding
  ) throws {
    try write { db in
      try GenerationSnapshot.finalizePublished(db, binding: binding)
    }
  }

  /// Revoke an exact candidate capability and delete its staging atomically.
  /// Active-generation routing and authorization are left untouched.
  public func discardGenerationSnapshot(
    binding: GenerationSnapshotBinding
  ) throws {
    try write { db in try GenerationSnapshot.discard(db, binding: binding) }
  }

}
