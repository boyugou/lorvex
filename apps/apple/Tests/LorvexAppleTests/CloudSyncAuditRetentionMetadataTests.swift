import Foundation
import LorvexDomain
import LorvexSync
import Testing
@preconcurrency import CloudKit

@testable import LorvexCloudSync

private actor AuditGuardDatabase: CloudKitDatabaseModifying {
  private let context: CloudSyncGenerationContext
  private var metadataRecord: CKRecord?
  private var revision = 0
  private var replacementBeforeNextModify: CloudSyncAuditRetentionMetadata?
  private var savedEntityNames = Set<String>()
  private var auditBatchSizesStorage: [Int] = []
  private var incomingGuardRevisionsStorage: [Int] = []
  private var allGuardedRequestsWereAtomic = true
  private let conflictingServerRecord: CKRecord?

  init(
    context: CloudSyncGenerationContext,
    metadata: CloudSyncAuditRetentionMetadata?,
    conflictingServerRecord: CKRecord? = nil
  ) {
    self.context = context
    self.conflictingServerRecord = conflictingServerRecord
    if let metadata {
      revision = 1
      let record = CloudSyncAuditRetentionMetadataRecord.makeRecord(
        metadata: metadata, context: context)
      record["test_revision"] = revision as CKRecordValue
      metadataRecord = record
    }
  }

  func replaceMetadataBeforeNextModify(with metadata: CloudSyncAuditRetentionMetadata) {
    replacementBeforeNextModify = metadata
  }

  func modifyRecordZones(
    saving _: [CKRecordZone], deleting _: [CKRecordZone.ID]
  ) async throws -> (
    saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
    deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
  ) { ([:], [:]) }

  func modifyRecords(
    saving records: [CKRecord], deleting _: [CKRecord.ID],
    savePolicy _: CKModifyRecordsOperation.RecordSavePolicy, atomically: Bool
  ) async throws -> (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
  ) {
    let guardID = CloudSyncAuditRetentionMetadataRecord.recordID(zoneID: context.zoneID)
    guard let incomingGuard = records.first(where: { $0.recordID == guardID }) else {
      return ([:], [:])
    }
    let entities = records.filter { $0.recordID != guardID }
    allGuardedRequestsWereAtomic = allGuardedRequestsWereAtomic && atomically
    auditBatchSizesStorage.append(entities.count)
    incomingGuardRevisionsStorage.append((incomingGuard["test_revision"] as? NSNumber)?.intValue ?? -1)

    if let replacement = replacementBeforeNextModify {
      replacementBeforeNextModify = nil
      revision += 1
      let advanced = CloudSyncAuditRetentionMetadataRecord.makeRecord(
        metadata: replacement, context: context)
      advanced["test_revision"] = revision as CKRecordValue
      metadataRecord = advanced
    }

    guard metadataRecord != nil,
      (incomingGuard["test_revision"] as? NSNumber)?.intValue == revision
    else {
      var failures: [CKRecord.ID: Result<CKRecord, any Error>] = [
        guardID: .failure(CKError(.serverRecordChanged))
      ]
      for entity in entities {
        failures[entity.recordID] = .failure(CKError(.batchRequestFailed))
      }
      return (failures, [:])
    }

    if let server = conflictingServerRecord,
      let entity = entities.first(where: { $0.recordID == server.recordID })
    {
      return (
        [
          guardID: .failure(CKError(.batchRequestFailed)),
          entity.recordID: .failure(
            CKError(
              .serverRecordChanged,
              userInfo: [
                CKRecordChangedErrorServerRecordKey: server,
                CKRecordChangedErrorClientRecordKey: entity,
              ])),
        ],
        [:])
    }

    revision += 1
    let savedGuard = copyRecord(incomingGuard)
    savedGuard["test_revision"] = revision as CKRecordValue
    metadataRecord = savedGuard
    var successes: [CKRecord.ID: Result<CKRecord, any Error>] = [
      guardID: .success(copyRecord(savedGuard))
    ]
    for entity in entities {
      savedEntityNames.insert(entity.recordID.recordName)
      successes[entity.recordID] = .success(entity)
    }
    return (successes, [:])
  }

  func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? {
    if recordID == CloudSyncZoneEpochRecord.recordID() {
      guard let readyWitness = context.readyWitness else { return nil }
      let descriptor = CloudSyncGenerationDescriptor(
        epoch: context.epoch,
        generationID: context.generationID,
        zoneName: context.zoneName,
        readyWitness: readyWitness,
        tombstoneCompactionCutoff: context.tombstoneCompactionCutoff)
      let completedLease = CloudSyncZoneRebuildLease(
        identifier: "metadata-codec-completed-rebuild",
        ownerIdentifier: "metadata-codec-database-instance",
        epoch: context.epoch,
        generationID: context.generationID,
        candidateZoneName: context.zoneName)
      let control = CloudSyncZoneEpochRecord.makeRecord()
      CloudSyncZoneEpochRecord.stampReady(
        descriptor: descriptor,
        completedLease: completedLease,
        retiredZoneNames: [],
        onto: control)
      return control
    }
    guard recordID == metadataRecord?.recordID, let metadataRecord else { return nil }
    return copyRecord(metadataRecord)
  }

  func allRecordZones() async throws -> [CKRecordZone] { [] }

  var auditBatchSizes: [Int] { auditBatchSizesStorage }
  var incomingGuardRevisions: [Int] { incomingGuardRevisionsStorage }
  var savedEntityCount: Int { savedEntityNames.count }
  var guardedRequestsWereAtomic: Bool { allGuardedRequestsWereAtomic }

  private func copyRecord(_ source: CKRecord) -> CKRecord {
    let copy = CKRecord(recordType: source.recordType, recordID: source.recordID)
    for key in source.allKeys() { copy[key] = source[key] }
    for key in CloudSyncEnvelopeRecord.Field.encrypted {
      copy.encryptedValues[key] = source.encryptedValues[key]
    }
    for key in CloudSyncAuditRetentionMetadataRecord.encryptedFields {
      copy.encryptedValues[key] = source.encryptedValues[key]
    }
    return copy
  }
}

struct CloudSyncAuditRetentionMetadataTests {
  private let canonicalVersion = "6000000000000_0001_a1b2c3d4a1b2c3d4"
  private let unpaddedVersion = "6000000000000_1_a1b2c3d4a1b2c3d4"
  private let uppercaseVersion = "6000000000000_0001_A1B2C3D4A1B2C3D4"

  private var descriptor: CloudSyncGenerationDescriptor {
    CloudSyncGenerationDescriptor(
      epoch: 1, generationID: "metadata-codec-generation",
      zoneName: "LorvexData-e1-metadata-codec-generation",
      readyWitness: "metadata-codec-witness")
  }

  private var context: CloudSyncGenerationContext {
    CloudSyncGenerationContext(
      accountIdentifier: "metadata-codec-account",
      descriptor: descriptor)
  }

  private func metadata(policyVersion: String) -> CloudSyncAuditRetentionMetadata {
    CloudSyncAuditRetentionMetadata(
      frontier: .initial, policy: .maximum,
      policyVersion: policyVersion, policyAuthorizedEpoch: 0)
  }

  @Test
  func canonicalPolicyVersionRoundTrips() {
    let value = metadata(policyVersion: canonicalVersion)
    #expect(CloudSyncAuditRetentionMetadataRecord.isValid(value))
    let record = CloudSyncAuditRetentionMetadataRecord.makeRecord(
      metadata: value, context: context)
    #expect(CloudSyncAuditRetentionMetadataRecord.decode(record, context: context) == value)
    for field in CloudSyncAuditRetentionMetadataRecord.encryptedFields {
      #expect(record[field] == nil)
      #expect(record.encryptedValues[field] != nil)
    }
  }

  @Test
  func parseableButNoncanonicalPolicyVersionsAreRejected() throws {
    for noncanonical in [unpaddedVersion, uppercaseVersion] {
      _ = try Hlc.parse(noncanonical)
      let value = metadata(policyVersion: noncanonical)
      #expect(CloudSyncAuditRetentionMetadataRecord.isValid(value) == false)

      let record = CloudSyncAuditRetentionMetadataRecord.makeRecord(
        metadata: metadata(policyVersion: canonicalVersion), context: context)
      record.encryptedValues[CloudSyncAuditRetentionMetadataRecord.policyVersionField] =
        noncanonical as CKRecordValue
      #expect(CloudSyncAuditRetentionMetadataRecord.decode(record, context: context) == nil)
    }
  }

  @Test
  func reservedHlcHeadroomIsRejectedByDecodeAndMerge() throws {
    let boundary = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "eeeeeeeeeeeeeeee").description
    let overCeiling = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
      deviceSuffix: "ffffffffffffffff").description
    #expect(CloudSyncAuditRetentionMetadataRecord.isValid(metadata(policyVersion: boundary)))
    #expect(
      CloudSyncAuditRetentionMetadataRecord.isValid(
        metadata(policyVersion: overCeiling)) == false)

    let record = CloudSyncAuditRetentionMetadataRecord.makeRecord(
      metadata: metadata(policyVersion: boundary), context: context)
    record.encryptedValues[CloudSyncAuditRetentionMetadataRecord.policyVersionField] =
      overCeiling as CKRecordValue
    #expect(CloudSyncAuditRetentionMetadataRecord.decode(record, context: context) == nil)

    #expect(throws: CloudSyncZoneEpochError.self) {
      try CloudKitRecordPusher.mergeRetentionMetadata(
        .initial, metadata(policyVersion: overCeiling))
    }
  }

  @Test
  func concurrentNewerPolicyAtOlderFrontierJoinsWithoutWedgeOrResurrection() throws {
    let olderPolicyAtNewerFrontier = CloudSyncAuditRetentionMetadata(
      frontier: AuditRetentionFrontierValue(epoch: 1),
      policy: .off,
      policyVersion: "6000000000000_0001_a1b2c3d4a1b2c3d4",
      policyAuthorizedEpoch: 1)
    let newerPolicyAtOlderFrontier = CloudSyncAuditRetentionMetadata(
      frontier: .initial,
      policy: .days(30),
      policyVersion: "6000000000000_0002_b1b2c3d4b1b2c3d4",
      policyAuthorizedEpoch: 0)

    let forward = try CloudKitRecordPusher.mergeRetentionMetadata(
      olderPolicyAtNewerFrontier, newerPolicyAtOlderFrontier)
    let reverse = try CloudKitRecordPusher.mergeRetentionMetadata(
      newerPolicyAtOlderFrontier, olderPolicyAtNewerFrontier)

    #expect(forward == reverse, "the concurrent join must be commutative")
    #expect(forward.frontier == olderPolicyAtNewerFrontier.frontier)
    #expect(forward.policy == newerPolicyAtOlderFrontier.policy)
    #expect(forward.policyVersion == newerPolicyAtOlderFrontier.policyVersion)
    #expect(forward.policyAuthorizedEpoch == forward.frontier.epoch)
    #expect(
      try CloudKitRecordPusher.mergeRetentionMetadata(forward, forward) == forward,
      "the joined authority must be idempotent")
  }

  @Test
  func equalPolicyVersionsWithDifferentPoliciesConvergeConservatively() throws {
    let version = "6000000000000_0003_c1b2c3d4c1b2c3d4"
    let lhs = CloudSyncAuditRetentionMetadata(
      frontier: .initial, policy: .maximum,
      policyVersion: version, policyAuthorizedEpoch: 0)
    let rhs = CloudSyncAuditRetentionMetadata(
      frontier: AuditRetentionFrontierValue(epoch: 1), policy: .off,
      policyVersion: version, policyAuthorizedEpoch: 1)

    let forward = try CloudKitRecordPusher.mergeRetentionMetadata(lhs, rhs)
    let reverse = try CloudKitRecordPusher.mergeRetentionMetadata(rhs, lhs)
    #expect(forward == reverse)
    #expect(forward.policy == .maximum)
    #expect(forward.policyVersion == version)
    #expect(forward.frontier == rhs.frontier)
    #expect(forward.policyAuthorizedEpoch == rhs.frontier.epoch)
    #expect(try CloudKitRecordPusher.mergeRetentionMetadata(forward, forward) == forward)
  }

  @Test
  func guardedAuditPushCarriesReturnedMetadataRevisionAcrossBatches() async throws {
    let database = AuditGuardDatabase(context: context, metadata: .initial)
    let pusher = CloudKitRecordPusher(database: database)
    let records = try (0..<200).map { index in
      let envelope = SyncEnvelope(
        entityType: .aiChangelog,
        entityId: String(format: "01966a3f-7c8b-7d4e-8f3a-%012d", index),
        operation: .upsert,
        version: try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "device-a")
      return CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: context.zoneID)
    }

    let results = try await pusher.pushAuditRecords(
      records, guardedBy: .initial, context: context,
      expectation: .ready(descriptor), boundaryGuard: nil)

    #expect(results.count == 200)
    #expect(results.allSatisfy { $0.succeeded })
    #expect(await database.auditBatchSizes == [199, 1])
    #expect(await database.incomingGuardRevisions == [1, 2])
    #expect(await database.savedEntityCount == 200)
    #expect(await database.guardedRequestsWereAtomic)
  }

  @Test
  func concurrentFrontierAdvanceMakesStaleAuditBatchAtomicNoOp() async throws {
    let database = AuditGuardDatabase(context: context, metadata: .initial)
    let advanced = CloudSyncAuditRetentionMetadata(
      frontier: AuditRetentionFrontierValue(epoch: 1), policy: .off,
      policyVersion: "6000000000000_0002_b1b2c3d4b1b2c3d4",
      policyAuthorizedEpoch: 1)
    await database.replaceMetadataBeforeNextModify(with: advanced)
    let pusher = CloudKitRecordPusher(database: database)
    let envelope = SyncEnvelope(
      entityType: .aiChangelog,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000999",
      operation: .upsert,
      version: try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}", deviceId: "device-a")
    let record = CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: context.zoneID)

    await #expect(throws: CloudSyncAuditRetentionGuardError.stale) {
      try await pusher.pushAuditRecords(
        [record], guardedBy: .initial, context: context,
        expectation: .ready(descriptor), boundaryGuard: nil)
    }
    #expect(await database.savedEntityCount == 0)
    #expect(await database.guardedRequestsWereAtomic)
  }

  @Test
  func missingRetentionMetadataFailsClosedBeforeAuditTransport() async throws {
    let database = AuditGuardDatabase(context: context, metadata: nil)
    let pusher = CloudKitRecordPusher(database: database)
    let envelope = SyncEnvelope(
      entityType: .aiChangelog,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000998",
      operation: .upsert,
      version: try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}", deviceId: "device-a")

    await #expect(throws: CloudSyncAuditRetentionGuardError.missing) {
      try await pusher.pushAuditRecords(
        [CloudSyncEnvelopeRecord.makeRecord(envelope, zoneID: context.zoneID)],
        guardedBy: .initial, context: context,
        expectation: .ready(descriptor), boundaryGuard: nil)
    }
    #expect(await database.savedEntityCount == 0)
  }

  @Test
  func guardedAuditEqualHlcMismatchReturnsTypedSuccessorCollision() async throws {
    let version = try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4")
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000997"
    let local = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"local"}"#, deviceId: "device-a")
    let server = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"server"}"#, deviceId: "device-b")
    let serverRecord = CloudSyncEnvelopeRecord.makeRecord(
      server, zoneID: context.zoneID)
    let database = AuditGuardDatabase(
      context: context, metadata: .initial,
      conflictingServerRecord: serverRecord)
    let pusher = CloudKitRecordPusher(database: database)

    let result = try #require(
      try await pusher.pushAuditRecords(
        [CloudSyncEnvelopeRecord.makeRecord(local, zoneID: context.zoneID)],
        guardedBy: .initial, context: context,
        expectation: .ready(descriptor), boundaryGuard: nil).first)

    #expect(!result.succeeded)
    guard case .equalVersion(let returned)? = result.collision else {
      Issue.record("guarded audit conflict must request deterministic successor repair")
      return
    }
    #expect(returned == server)
    #expect(result.systemFieldsReceipt?.recordName == serverRecord.recordID.recordName)
    #expect(await database.savedEntityCount == 0)
  }

  @Test
  func guardedAuditCorruptHigherServerSlotCarriesVersionFloor() async throws {
    let localVersion = try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc.parse("6000000000001_0000_b1b2c3d4b1b2c3d4")
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000996"
    let local = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: localVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"local"}"#, deviceId: "device-a")
    let server = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: serverVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"server"}"#, deviceId: "device-b")
    let serverRecord = CloudSyncEnvelopeRecord.makeRecord(
      server, zoneID: context.zoneID)
    serverRecord.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = nil
    let database = AuditGuardDatabase(
      context: context, metadata: .initial,
      conflictingServerRecord: serverRecord)
    let pusher = CloudKitRecordPusher(database: database)

    let result = try #require(
      try await pusher.pushAuditRecords(
        [CloudSyncEnvelopeRecord.makeRecord(local, zoneID: context.zoneID)],
        guardedBy: .initial, context: context,
        expectation: .ready(descriptor), boundaryGuard: nil).first)

    guard case .corruptServerSlot(let floor)? = result.collision else {
      Issue.record("corrupt guarded audit slot must request successor repair")
      return
    }
    #expect(floor == serverVersion)
    #expect(result.systemFieldsReceipt?.recordName == serverRecord.recordID.recordName)
    #expect(await database.savedEntityCount == 0)
  }

  @Test
  func guardedAuditValidUnequalVersionConflictReturnsImmutableIdentityCollision()
    async throws
  {
    let localVersion = try Hlc.parse("6000000000000_0001_a1b2c3d4a1b2c3d4")
    let serverVersion = try Hlc.parse("6000000000001_0000_b1b2c3d4b1b2c3d4")
    let entityId = "01966a3f-7c8b-7d4e-8f3a-000000000995"
    let local = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: localVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"local"}"#, deviceId: "device-a")
    let server = SyncEnvelope(
      entityType: .aiChangelog, entityId: entityId, operation: .upsert,
      version: serverVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"summary":"server"}"#, deviceId: "device-b")
    let serverRecord = CloudSyncEnvelopeRecord.makeRecord(
      server, zoneID: context.zoneID)
    let database = AuditGuardDatabase(
      context: context, metadata: .initial,
      conflictingServerRecord: serverRecord)
    let pusher = CloudKitRecordPusher(database: database)

    let result = try #require(
      try await pusher.pushAuditRecords(
        [CloudSyncEnvelopeRecord.makeRecord(local, zoneID: context.zoneID)],
        guardedBy: .initial, context: context,
        expectation: .ready(descriptor), boundaryGuard: nil).first)

    guard case .immutableIdentity(let returned)? = result.collision else {
      Issue.record("valid unequal audit conflict must preserve its immutable identity")
      return
    }
    #expect(returned == server)
    #expect(result.systemFieldsReceipt?.recordName == serverRecord.recordID.recordName)
    #expect(await database.savedEntityCount == 0)
  }
}
