import Foundation
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

/// Provenance shared by the immutable root and seal of one generation. During
/// predecessor draining the singleton control record retains only the ready
/// descriptor, so root/seal agreement is the remaining proof that the two
/// individually valid markers came from the same completed rebuild.
struct CloudSyncGenerationMarkerProvenance: Sendable, Equatable {
  var rebuildIdentifier: String
  var rebuildOwnerIdentifier: String
  var databaseInstanceIdentifier: String
}

/// Required identity marker inside every generation-specific custom zone.
enum CloudSyncGenerationRootRecord {
  static let recordType = "LorvexGenerationRoot"
  static let recordName = CloudSyncGenerationDescriptor.rootRecordName
  static let protocolVersionField = "protocol_version"
  static let epochField = "epoch"
  static let generationIDField = "generation_id"
  static let rebuildIdentifierField = "rebuild_id"
  static let rebuildOwnerField = "rebuild_owner"
  static let databaseInstanceIDField = "database_instance_id"
  static let protocolVersion = 2

  static func recordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  static func makeRecord(lease: CloudSyncZoneRebuildLease) -> CKRecord {
    let record = CKRecord(
      recordType: recordType, recordID: recordID(zoneID: lease.candidateZoneID))
    record[protocolVersionField] = protocolVersion as CKRecordValue
    record[epochField] = lease.epoch as CKRecordValue
    record[generationIDField] = lease.generationID as CKRecordValue
    record[rebuildIdentifierField] = lease.identifier as CKRecordValue
    record[rebuildOwnerField] = lease.ownerIdentifier as CKRecordValue
    // The rebuild owner is deliberately the physical SQLite database instance
    // identifier. Keeping the semantic field explicit in the root makes a
    // candidate copied or resumed by a different local database fail closed.
    record[databaseInstanceIDField] = lease.ownerIdentifier as CKRecordValue
    return record
  }

  static func matches(_ record: CKRecord, lease: CloudSyncZoneRebuildLease) -> Bool {
    lease.epoch >= 0
      && CloudSyncGenerationNaming.isValidIdentifier(lease.generationID)
      && CloudSyncGenerationNaming.isValidIdentifier(lease.identifier)
      && CloudSyncGenerationNaming.isValidIdentifier(lease.ownerIdentifier)
      && CloudSyncGenerationNaming.isValidGenerationZoneName(
        lease.candidateZoneName, epoch: lease.epoch,
        generationID: lease.generationID)
      && record.recordType == recordType
      && record.recordID == recordID(zoneID: lease.candidateZoneID)
      && CloudSyncRecordValueCodec.nonnegativeInt(record[protocolVersionField])
        == protocolVersion
      && CloudSyncRecordValueCodec.nonnegativeInt(record[epochField]) == lease.epoch
      && record[generationIDField] as? String == lease.generationID
      && record[rebuildIdentifierField] as? String == lease.identifier
      && record[rebuildOwnerField] as? String == lease.ownerIdentifier
      && record[databaseInstanceIDField] as? String == lease.ownerIdentifier
  }

  static func matches(
    _ record: CKRecord, descriptor: CloudSyncGenerationDescriptor
  ) -> Bool {
    provenance(from: record, descriptor: descriptor) != nil
  }

  static func provenance(
    from record: CKRecord, descriptor: CloudSyncGenerationDescriptor
  ) -> CloudSyncGenerationMarkerProvenance? {
    guard descriptor.epoch >= 0,
      CloudSyncGenerationNaming.isValidIdentifier(descriptor.generationID),
      CloudSyncGenerationNaming.isValidIdentifier(descriptor.readyWitness),
      CloudSyncGenerationNaming.isValidGenerationZoneName(
        descriptor.zoneName, epoch: descriptor.epoch,
        generationID: descriptor.generationID),
      let rebuildIdentifier = record[rebuildIdentifierField] as? String,
      CloudSyncGenerationNaming.isValidIdentifier(rebuildIdentifier),
      let rebuildOwner = record[rebuildOwnerField] as? String,
      CloudSyncGenerationNaming.isValidIdentifier(rebuildOwner),
      let databaseInstanceIdentifier = record[databaseInstanceIDField] as? String,
      databaseInstanceIdentifier == rebuildOwner
    else { return nil }
    guard record.recordType == recordType
      && record.recordID == recordID(zoneID: descriptor.zoneID)
      && CloudSyncRecordValueCodec.nonnegativeInt(record[protocolVersionField])
        == protocolVersion
      && CloudSyncRecordValueCodec.nonnegativeInt(record[epochField]) == descriptor.epoch
      && record[generationIDField] as? String == descriptor.generationID
    else { return nil }
    return CloudSyncGenerationMarkerProvenance(
      rebuildIdentifier: rebuildIdentifier,
      rebuildOwnerIdentifier: rebuildOwner,
      databaseInstanceIdentifier: databaseInstanceIdentifier)
  }
}

/// Immutable manifest of the exact local snapshot copied into one candidate.
public struct CloudSyncGenerationManifest: Sendable, Equatable, Codable {
  public var sourceLocalChangeSequence: UInt64
  public var expectedEntityCount: Int
  public var expectedEncodedBytes: Int64
  public var canonicalDigest: String
  public var expectedAuditCount: Int
  public var auditCanonicalDigest: String
  public var retentionMetadataDigest: String
  public var tombstoneCompactionCutoff: String?

  public init(
    sourceLocalChangeSequence: UInt64, expectedEntityCount: Int,
    expectedEncodedBytes: Int64,
    canonicalDigest: String, expectedAuditCount: Int,
    auditCanonicalDigest: String, retentionMetadataDigest: String,
    tombstoneCompactionCutoff: String? = nil
  ) {
    self.sourceLocalChangeSequence = sourceLocalChangeSequence
    self.expectedEntityCount = expectedEntityCount
    self.expectedEncodedBytes = expectedEncodedBytes
    self.canonicalDigest = canonicalDigest
    self.expectedAuditCount = expectedAuditCount
    self.auditCanonicalDigest = auditCanonicalDigest
    self.retentionMetadataDigest = retentionMetadataDigest
    self.tombstoneCompactionCutoff = tombstoneCompactionCutoff
  }
}

/// Completion witness written only after the candidate baseline has drained,
/// been read back from a nil token, and matched this exact manifest.
enum CloudSyncGenerationSealRecord {
  static let recordType = "LorvexGenerationSeal"
  static let recordName = "lorvex-generation-seal"
  static let epochField = "epoch"
  static let generationIDField = "generation_id"
  static let rebuildIdentifierField = "rebuild_id"
  static let rebuildOwnerField = "rebuild_owner"
  static let databaseInstanceIDField = "database_instance_id"
  static let witnessField = "ready_witness"
  static let expectedEntityCountField = "expected_entity_count"
  static let expectedEncodedBytesField = "expected_encoded_bytes"
  static let canonicalDigestField = "canonical_digest"
  static let sourceLocalChangeSequenceField = "source_local_change_seq"
  static let expectedAuditCountField = "expected_audit_count"
  static let auditCanonicalDigestField = "audit_canonical_digest"
  static let retentionMetadataDigestField = "retention_metadata_digest"
  static let tombstoneCompactionCutoffField = "tombstone_compaction_cutoff"

  static func recordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  static func makeRecord(
    lease: CloudSyncZoneRebuildLease, witness: String,
    manifest: CloudSyncGenerationManifest
  ) throws -> CKRecord {
    let compactionCutoffIsValid: Bool
    if let cutoff = manifest.tombstoneCompactionCutoff {
      compactionCutoffIsValid = SyncTimestamp.parse(cutoff)?.asString == cutoff
    } else {
      compactionCutoffIsValid = true
    }
    guard manifest.expectedEntityCount >= 0,
      manifest.expectedEntityCount <= GenerationSnapshot.maximumRecordCount,
      manifest.expectedEncodedBytes >= 0,
      manifest.expectedEncodedBytes <= GenerationSnapshot.maximumTotalEncodedBytes,
      manifest.sourceLocalChangeSequence <= UInt64(Int64.max),
      manifest.expectedAuditCount >= 0,
      manifest.expectedAuditCount <= manifest.expectedEntityCount,
      CloudSyncGenerationNaming.isValidIdentifier(witness),
      lease.epoch >= 0,
      CloudSyncGenerationNaming.isValidIdentifier(lease.generationID),
      CloudSyncGenerationNaming.isValidIdentifier(lease.identifier),
      CloudSyncGenerationNaming.isValidIdentifier(lease.ownerIdentifier),
      CloudSyncGenerationNaming.isValidGenerationZoneName(
        lease.candidateZoneName, epoch: lease.epoch,
        generationID: lease.generationID),
      CloudSyncGenerationNaming.isValidDigest(manifest.canonicalDigest),
      CloudSyncGenerationNaming.isValidDigest(manifest.auditCanonicalDigest),
      CloudSyncGenerationNaming.isValidDigest(manifest.retentionMetadataDigest),
      compactionCutoffIsValid
    else { throw CloudSyncZoneEpochError.generationMarkerMismatch }
    let record = CKRecord(
      recordType: recordType, recordID: recordID(zoneID: lease.candidateZoneID))
    record[epochField] = lease.epoch as CKRecordValue
    record[generationIDField] = lease.generationID as CKRecordValue
    record[rebuildIdentifierField] = lease.identifier as CKRecordValue
    record[rebuildOwnerField] = lease.ownerIdentifier as CKRecordValue
    record[databaseInstanceIDField] = lease.ownerIdentifier as CKRecordValue
    record[witnessField] = witness as CKRecordValue
    record[expectedEntityCountField] = manifest.expectedEntityCount as CKRecordValue
    record[expectedEncodedBytesField] = manifest.expectedEncodedBytes as CKRecordValue
    record[canonicalDigestField] = manifest.canonicalDigest as CKRecordValue
    record[sourceLocalChangeSequenceField] =
      Int64(manifest.sourceLocalChangeSequence) as CKRecordValue
    record[expectedAuditCountField] = manifest.expectedAuditCount as CKRecordValue
    record[auditCanonicalDigestField] = manifest.auditCanonicalDigest as CKRecordValue
    record[retentionMetadataDigestField] = manifest.retentionMetadataDigest as CKRecordValue
    record[tombstoneCompactionCutoffField] =
      manifest.tombstoneCompactionCutoff as CKRecordValue?
    return record
  }

  static func matches(
    _ record: CKRecord, lease: CloudSyncZoneRebuildLease, witness: String,
    manifest: CloudSyncGenerationManifest
  ) -> Bool {
    self.manifest(from: record, lease: lease, witness: witness) == manifest
  }

  static func matches(
    _ record: CKRecord, descriptor: CloudSyncGenerationDescriptor
  ) -> Bool {
    manifest(from: record, descriptor: descriptor) != nil
  }

  static func manifest(
    from record: CKRecord, lease: CloudSyncZoneRebuildLease, witness: String
  ) -> CloudSyncGenerationManifest? {
    guard lease.epoch >= 0,
      CloudSyncGenerationNaming.isValidIdentifier(lease.generationID),
      CloudSyncGenerationNaming.isValidIdentifier(lease.identifier),
      CloudSyncGenerationNaming.isValidIdentifier(lease.ownerIdentifier),
      CloudSyncGenerationNaming.isValidGenerationZoneName(
        lease.candidateZoneName, epoch: lease.epoch,
        generationID: lease.generationID),
      CloudSyncGenerationNaming.isValidIdentifier(witness),
      record.recordType == recordType,
      record.recordID == recordID(zoneID: lease.candidateZoneID),
      CloudSyncRecordValueCodec.nonnegativeInt(record[epochField]) == lease.epoch,
      record[generationIDField] as? String == lease.generationID,
      record[rebuildIdentifierField] as? String == lease.identifier,
      record[rebuildOwnerField] as? String == lease.ownerIdentifier,
      record[databaseInstanceIDField] as? String == lease.ownerIdentifier,
      record[witnessField] as? String == witness
    else { return nil }
    return decodedManifest(from: record)
  }

  /// Decode a published seal when the current control record no longer exposes
  /// its completed rebuild lease to a zone-change fetcher. Provenance fields are
  /// still required to be internally coherent; exact comparison is performed by
  /// `validateGenerationRoot`, which also has the singleton control record.
  static func manifest(
    from record: CKRecord, descriptor: CloudSyncGenerationDescriptor
  ) -> CloudSyncGenerationManifest? {
    guard provenance(from: record, descriptor: descriptor) != nil else {
      return nil
    }
    guard let manifest = decodedManifest(from: record),
      manifest.tombstoneCompactionCutoff == descriptor.tombstoneCompactionCutoff
    else { return nil }
    return manifest
  }

  static func provenance(
    from record: CKRecord, descriptor: CloudSyncGenerationDescriptor
  ) -> CloudSyncGenerationMarkerProvenance? {
    guard descriptor.epoch >= 0,
      CloudSyncGenerationNaming.isValidIdentifier(descriptor.generationID),
      CloudSyncGenerationNaming.isValidIdentifier(descriptor.readyWitness),
      CloudSyncGenerationNaming.isValidGenerationZoneName(
        descriptor.zoneName, epoch: descriptor.epoch,
        generationID: descriptor.generationID),
      record.recordType == recordType,
      record.recordID == recordID(zoneID: descriptor.zoneID),
      CloudSyncRecordValueCodec.nonnegativeInt(record[epochField]) == descriptor.epoch,
      record[generationIDField] as? String == descriptor.generationID,
      record[witnessField] as? String == descriptor.readyWitness,
      let rebuildIdentifier = record[rebuildIdentifierField] as? String,
      CloudSyncGenerationNaming.isValidIdentifier(rebuildIdentifier),
      let rebuildOwner = record[rebuildOwnerField] as? String,
      CloudSyncGenerationNaming.isValidIdentifier(rebuildOwner),
      let databaseInstanceIdentifier = record[databaseInstanceIDField] as? String,
      databaseInstanceIdentifier == rebuildOwner
    else { return nil }
    return CloudSyncGenerationMarkerProvenance(
      rebuildIdentifier: rebuildIdentifier,
      rebuildOwnerIdentifier: rebuildOwner,
      databaseInstanceIdentifier: databaseInstanceIdentifier)
  }

  private static func decodedManifest(
    from record: CKRecord
  ) -> CloudSyncGenerationManifest? {
    guard let count = CloudSyncRecordValueCodec.nonnegativeInt(
      record[expectedEntityCountField]),
      count <= GenerationSnapshot.maximumRecordCount,
      let encodedBytes = CloudSyncRecordValueCodec.nonnegativeInt64(
        record[expectedEncodedBytesField]),
      encodedBytes >= 0,
      encodedBytes <= GenerationSnapshot.maximumTotalEncodedBytes,
      let digest = record[canonicalDigestField] as? String,
      CloudSyncGenerationNaming.isValidDigest(digest),
      let sourceLocalChangeSequence = CloudSyncRecordValueCodec.nonnegativeUInt64(
        record[sourceLocalChangeSequenceField]),
      let auditCount = CloudSyncRecordValueCodec.nonnegativeInt(
        record[expectedAuditCountField]),
      auditCount <= count,
      let auditDigest = record[auditCanonicalDigestField] as? String,
      CloudSyncGenerationNaming.isValidDigest(auditDigest),
      let retentionDigest = record[retentionMetadataDigestField] as? String,
      CloudSyncGenerationNaming.isValidDigest(retentionDigest)
    else { return nil }
    let cutoff: String?
    if let raw = record[tombstoneCompactionCutoffField] {
      guard let value = raw as? String,
        let parsed = SyncTimestamp.parse(value), parsed.asString == value
      else { return nil }
      cutoff = value
    } else {
      cutoff = nil
    }
    return CloudSyncGenerationManifest(
      sourceLocalChangeSequence: sourceLocalChangeSequence,
      expectedEntityCount: count, expectedEncodedBytes: encodedBytes,
      canonicalDigest: digest,
      expectedAuditCount: auditCount, auditCanonicalDigest: auditDigest,
      retentionMetadataDigest: retentionDigest,
      tombstoneCompactionCutoff: cutoff)
  }
}

/// Per-traversal marker used to prove a nil-token traversal observed history
/// created after that exact traversal began. It is deleted after the terminal
/// page; generation root + seal alone cannot distinguish a full traversal from
/// a stale continuation token.
enum CloudSyncTraversalWitnessRecord {
  static let recordType = "LorvexTraversalWitness"
  static let recordNamePrefix = "lorvex-traversal-witness-"
  static let generationIDField = "generation_id"
  static let traversalIdentifierField = "traversal_id"

  static func recordID(
    zoneID: CKRecordZone.ID, traversalIdentifier: String
  ) -> CKRecord.ID {
    CKRecord.ID(
      recordName: recordNamePrefix + traversalIdentifier, zoneID: zoneID)
  }

  static func makeRecord(
    context: CloudSyncGenerationContext, traversalIdentifier: String
  ) throws -> CKRecord {
    guard CloudSyncGenerationNaming.isValidIdentifier(traversalIdentifier) else {
      throw CloudSyncZoneEpochError.generationMarkerMismatch
    }
    let record = CKRecord(
      recordType: recordType,
      recordID: recordID(
        zoneID: context.zoneID, traversalIdentifier: traversalIdentifier))
    record[generationIDField] = context.generationID as CKRecordValue
    record[traversalIdentifierField] = traversalIdentifier as CKRecordValue
    return record
  }

  static func matches(
    _ record: CKRecord, context: CloudSyncGenerationContext,
    traversalIdentifier: String
  ) -> Bool {
    record.recordType == recordType
      && record.recordID
        == recordID(zoneID: context.zoneID, traversalIdentifier: traversalIdentifier)
      && record[generationIDField] as? String == context.generationID
      && record[traversalIdentifierField] as? String == traversalIdentifier
  }
}

/// Post-publication custom-zone mutation used as a database-subscription wake.
enum CloudSyncGenerationWakeRecord {
  static let recordType = "LorvexGenerationWake"
  static let recordName = "lorvex-generation-wake"
  static let generationIDField = "generation_id"
  static let nonceField = "nonce"

  static func makeRecord(descriptor: CloudSyncGenerationDescriptor) -> CKRecord {
    let record = CKRecord(
      recordType: recordType,
      recordID: CKRecord.ID(recordName: recordName, zoneID: descriptor.zoneID))
    record[generationIDField] = descriptor.generationID as CKRecordValue
    record[nonceField] = UUID().uuidString as CKRecordValue
    return record
  }
}
