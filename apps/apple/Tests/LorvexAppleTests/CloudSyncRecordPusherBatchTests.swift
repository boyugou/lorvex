import Foundation
import LorvexDomain
import LorvexSync
import Testing
@preconcurrency import CloudKit

@testable import LorvexCloudSync

@Suite(.serialized)
struct CloudSyncRecordPusherBatchTests {
  private actor MutableAccount {
    private var identifier: String

    init(_ identifier: String) { self.identifier = identifier }
    func current() -> String { identifier }
    func set(_ identifier: String) { self.identifier = identifier }
  }

  private actor GenerationDatabase: CloudKitDatabaseModifying {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var zones: [CKRecordZone.ID: CKRecordZone] = [:]
    private var suspendNextEntitySave = false
    private var entitySaveEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var afterNextControlFetch: (@Sendable () async -> Void)?
    private(set) var zoneDeleteRequestCount = 0

    func suspendNextDataSave() { suspendNextEntitySave = true }

    func waitUntilDataSaveEntered() async {
      if entitySaveEntered { return }
      await withCheckedContinuation { entryWaiters.append($0) }
    }

    func releaseDataSave() {
      releaseContinuation?.resume()
      releaseContinuation = nil
    }

    func runAfterNextControlFetch(_ action: @escaping @Sendable () async -> Void) {
      afterNextControlFetch = action
    }

    func modifyRecordZones(
      saving recordZonesToSave: [CKRecordZone],
      deleting recordZoneIDsToDelete: [CKRecordZone.ID]
    ) async throws -> (
      saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
      deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
    ) {
      var saves: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = [:]
      var deletes: [CKRecordZone.ID: Result<Void, any Error>] = [:]
      for zone in recordZonesToSave {
        zones[zone.zoneID] = zone
        saves[zone.zoneID] = .success(zone)
      }
      for zoneID in recordZoneIDsToDelete {
        zoneDeleteRequestCount += 1
        zones.removeValue(forKey: zoneID)
        records = records.filter { $0.key.zoneID != zoneID }
        deletes[zoneID] = .success(())
      }
      return (saves, deletes)
    }

    func modifyRecords(
      saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
      savePolicy _: CKModifyRecordsOperation.RecordSavePolicy, atomically _: Bool
    ) async throws -> (
      saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
      deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
      if suspendNextEntitySave,
        recordsToSave.contains(where: { $0.recordType == CloudSyncEnvelopeRecord.recordType })
      {
        suspendNextEntitySave = false
        entitySaveEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
      }
      var saves: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
      var deletes: [CKRecord.ID: Result<Void, any Error>] = [:]
      for record in recordsToSave {
        records[record.recordID] = record
        saves[record.recordID] = .success(record)
      }
      for recordID in recordIDsToDelete {
        records.removeValue(forKey: recordID)
        deletes[recordID] = .success(())
      }
      return (saves, deletes)
    }

    func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord? {
      let record = records[recordID]
      if recordID == CloudSyncZoneEpochRecord.recordID(),
        let action = afterNextControlFetch
      {
        afterNextControlFetch = nil
        await action()
      }
      return record
    }

    func allRecordZones() async throws -> [CKRecordZone] {
      Array(zones.values)
    }

    func contains(_ recordID: CKRecord.ID) -> Bool { records[recordID] != nil }
  }

  private let emptyManifest = CloudSyncGenerationManifest(
    sourceLocalChangeSequence: 0,
    expectedEntityCount: 0,
    expectedEncodedBytes: 0,
    canonicalDigest: String(repeating: "0", count: 64),
    expectedAuditCount: 0,
    auditCanonicalDigest: String(repeating: "0", count: 64),
    retentionMetadataDigest: CloudSyncAuditRetentionMetadata.initial.canonicalDigest)

  private func saveDirectly(
    _ record: CKRecord, to database: GenerationDatabase
  ) async throws {
    let result = try await database.modifyRecords(
      saving: [record], deleting: [], savePolicy: .changedKeys,
      atomically: true)
    _ = try #require(result.saveResults[record.recordID]).get()
  }

  private func publishReady(
    pusher: CloudKitRecordPusher,
    lease: CloudSyncZoneRebuildLease,
    manifest requestedManifest: CloudSyncGenerationManifest? = nil
  ) async throws -> CloudSyncGenerationDescriptor {
    let manifest = requestedManifest ?? emptyManifest
    let expectation = CloudSyncGenerationExpectation.rebuilding(lease)
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", lease: lease)
    try await pusher.ensureZone(
      lease.candidateZoneID, expectation: expectation, boundaryGuard: nil)
    try await pusher.ensureGenerationRoot(lease, boundaryGuard: nil)
    _ = try await pusher.mergeAuditRetentionMetadata(
      .initial, context: context, expectation: expectation, boundaryGuard: nil)
    try await pusher.advanceZoneRebuildPhase(
      lease, to: .preparing, boundaryGuard: nil)
    try await pusher.advanceZoneRebuildPhase(
      lease, to: .sealing, boundaryGuard: nil)
    let witness = "ready-witness-(lease.epoch)"
    try await pusher.saveGenerationSeal(
      lease, readyWitness: witness, manifest: manifest,
      boundaryGuard: nil)
    try await pusher.advanceZoneRebuildPhase(
      lease, to: .publishing, boundaryGuard: nil)
    return try await pusher.completeZoneRebuild(
      lease, readyWitness: witness, manifest: manifest,
      boundaryGuard: nil)
  }

  @Test
  func firstClaimUsesFreshUniqueCandidateAndPublishesOnlyAfterSeal() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let lease = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)

    #expect(lease.epoch == 1)
    #expect(lease.candidateZoneName.hasPrefix("LorvexData-e1-"))
    guard case .rebuilding(let recorded, nil, .claimed, [], _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("claim must remain rebuilding")
      return
    }
    #expect(recorded == lease)

    let descriptor = try await publishReady(pusher: pusher, lease: lease)
    #expect(descriptor.epoch == 1)
    #expect(descriptor.zoneName == lease.candidateZoneName)
    guard case .ready(let ready, let retired, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("sealed candidate must publish ready")
      return
    }
    #expect(ready == descriptor)
    #expect(retired.isEmpty)
  }

  @Test
  func restartNeverReusesCandidateNamespaceAndRecordsAbandonedZone() async throws {
    let pusher = CloudKitRecordPusher(database: GenerationDatabase())
    let first = try await pusher.beginZoneRebuild(
      atLeast: 4, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let second = try await pusher.restartZoneRebuild(first, boundaryGuard: nil)

    #expect(second.epoch == first.epoch + 1)
    #expect(second.generationID != first.generationID)
    #expect(second.candidateZoneName != first.candidateZoneName)
    guard case .rebuilding(let lease, nil, .claimed, let retired, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("replacement must remain claimed")
      return
    }
    #expect(lease == second)
    #expect(retired == [first.candidateZoneName])
  }

  @Test
  func deletedBarrierRequiresExplicitReenableAndAdvancesMonotonically() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let first = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let ready = try await publishReady(pusher: pusher, lease: first)
    let deleted = try await pusher.markCloudDataDeleted(atLeast: 0, boundaryGuard: nil)
    #expect(deleted.epoch == ready.epoch + 1)

    await #expect(throws: CloudSyncZoneEpochError.zoneRecreationStillRequired) {
      try await pusher.beginZoneRebuild(
        atLeast: 0, ownerIdentifier: "database-instance-a",
        allowFromDeleted: false, boundaryGuard: nil)
    }
    let reenabled = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: true, boundaryGuard: nil)
    #expect(reenabled.epoch == deleted.epoch + 1)
    #expect(reenabled.candidateZoneName != ready.zoneName)
  }

  @Test
  func explicitDeletionCreatesMissingBarrierAboveLocalAndOrphanEpochFloors() async throws {
    let freshDatabase = GenerationDatabase()
    let freshPusher = CloudKitRecordPusher(database: freshDatabase)
    guard case .deleted(let freshEpoch, let freshHints, _) =
      try await freshPusher.markCloudDataDeleted(atLeast: 7, boundaryGuard: nil)
    else {
      Issue.record("a fresh account must still receive a durable deleted barrier")
      return
    }
    #expect(freshEpoch == 8)
    #expect(freshHints.isEmpty)

    let orphanDatabase = GenerationDatabase()
    let orphanZoneName = CloudSyncGenerationNaming.newZoneName(
      epoch: 12, generationID: "orphan-generation")
    _ = try await orphanDatabase.modifyRecordZones(
      saving: [CKRecordZone(zoneID: CKRecordZone.ID(
        zoneName: orphanZoneName, ownerName: CKCurrentUserDefaultName))],
      deleting: [])
    let orphanPusher = CloudKitRecordPusher(database: orphanDatabase)
    guard case .deleted(let recoveredEpoch, _, _) =
      try await orphanPusher.markCloudDataDeleted(atLeast: 4, boundaryGuard: nil)
    else {
      Issue.record("orphan namespaces must not make explicit deletion unrecoverable")
      return
    }
    #expect(recoveredEpoch == 13)
  }

  @Test
  func fullRetireeLedgerCannotBlockDeletionBarrierPublication() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let lease = try await pusher.beginZoneRebuild(
      atLeast: 40, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let descriptor = try await publishReady(pusher: pusher, lease: lease)
    let fullLedger = (0..<CloudSyncGenerationNaming.retiredZoneLimit).map {
      "LorvexData-e\($0)-retired-\($0)"
    }
    let control = try #require(await database.fetchRecord(
      with: CloudSyncZoneEpochRecord.recordID()))
    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: fullLedger, onto: control)
    try await saveDirectly(control, to: database)

    guard case .deleted(_, let cleanupHints, _) =
      try await pusher.markCloudDataDeleted(atLeast: 0, boundaryGuard: nil)
    else {
      Issue.record("the deletion barrier must publish over a full retiree ledger")
      return
    }
    #expect(cleanupHints == [descriptor.zoneName])
  }

  @Test
  func accountSwitchAfterControlReadPreventsDestructiveZoneRequest() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let lease = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let ready = try await publishReady(pusher: pusher, lease: lease)
    _ = try await pusher.markCloudDataDeleted(
      atLeast: ready.epoch, boundaryGuard: nil)

    let account = MutableAccount("account-A")
    await database.runAfterNextControlFetch {
      await account.set("account-B")
    }
    await #expect(throws: CloudSyncAccountBoundaryCrossed.self) {
      try await pusher.deleteRetiredZone(
        zoneName: ready.zoneName, accountIdentifier: "account-A",
        boundaryGuard: { await account.current() == "account-A" })
    }
    #expect(await database.zoneDeleteRequestCount == 0)
  }

  @Test
  func lateOldGenerationSaveFailsPostFenceAndReturnsNoConfirmation() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let lease = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let ready = try await publishReady(pusher: pusher, lease: lease)
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: ready)
    let expectation = CloudSyncGenerationExpectation.ready(ready)
    let envelope = SyncEnvelope(
      entityType: .task,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001",
      operation: .upsert,
      version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1,
      payload: #"{"title":"late"}"#,
      deviceId: "device-a")
    let record = CloudSyncEnvelopeRecord.makeRecord(
      envelope, zoneID: ready.zoneID)
    await database.suspendNextDataSave()

    let push = Task {
      try await pusher.push(
        [record], context: context, expectation: expectation,
        boundaryGuard: nil)
    }
    await database.waitUntilDataSaveEntered()
    _ = try await pusher.beginZoneRebuild(
      atLeast: ready.epoch, ownerIdentifier: "database-instance-b",
      allowFromDeleted: false, boundaryGuard: nil)
    await database.releaseDataSave()

    await #expect(throws: CloudSyncGenerationBoundaryCrossed.self) {
      try await push.value
    }
    #expect(
      await database.contains(record.recordID),
      "the request may land remotely, but the caller receives no success to confirm its outbox")
  }

  @Test
  func controlDecoderRequiresCanonicalGenerationZoneComposition() throws {
    let generationID = "generation-a"
    let canonicalZone = CloudSyncGenerationNaming.newZoneName(
      epoch: 4, generationID: generationID)
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: 4, generationID: generationID, zoneName: canonicalZone,
      readyWitness: "ready-a")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "rebuild-a", ownerIdentifier: "database-a", epoch: 4,
      generationID: generationID, candidateZoneName: canonicalZone)

    let ready = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: [], onto: ready)
    ready[CloudSyncZoneEpochRecord.activeZoneField] =
      "LorvexData-e4-different-generation" as CKRecordValue
    #expect(CloudSyncZoneEpochRecord.generationState(from: ready) == nil)

    let rebuilding = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampRebuilding(
      lease, previousActive: nil, phase: .claimed,
      leaseActivityAt: Date(timeIntervalSince1970: 1_800_000_000),
      retiredZoneNames: [], onto: rebuilding)
    rebuilding[CloudSyncZoneEpochRecord.candidateZoneField] =
      "LorvexData-e4-different-generation" as CKRecordValue
    #expect(CloudSyncZoneEpochRecord.generationState(from: rebuilding) == nil)
  }

  @Test
  func markerCodecsRejectNumericCoercionAndResidualState() throws {
    let generationID = "generation-b"
    let zoneName = CloudSyncGenerationNaming.newZoneName(
      epoch: 5, generationID: generationID)
    let lease = CloudSyncZoneRebuildLease(
      identifier: "rebuild-b", ownerIdentifier: "database-b", epoch: 5,
      generationID: generationID, candidateZoneName: zoneName)
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: 5, generationID: generationID, zoneName: zoneName,
      readyWitness: "ready-b")

    let root = CloudSyncGenerationRootRecord.makeRecord(lease: lease)
    root[CloudSyncGenerationRootRecord.protocolVersionField] = NSNumber(value: true)
    #expect(!CloudSyncGenerationRootRecord.matches(root, lease: lease))

    let seal = try CloudSyncGenerationSealRecord.makeRecord(
      lease: lease, witness: descriptor.readyWitness,
      manifest: emptyManifest)
    seal[CloudSyncGenerationSealRecord.expectedEntityCountField] = NSNumber(value: true)
    #expect(
      CloudSyncGenerationSealRecord.manifest(
        from: seal, lease: lease, witness: descriptor.readyWitness) == nil)

    let ready = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: [], onto: ready)
    ready[CloudSyncZoneEpochRecord.epochField] = NSNumber(value: 5.0)
    #expect(CloudSyncZoneEpochRecord.generationState(from: ready) == nil)

    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: [], onto: ready)
    ready[CloudSyncZoneEpochRecord.candidateZoneField] = zoneName as CKRecordValue
    #expect(CloudSyncZoneEpochRecord.generationState(from: ready) == nil)

    CloudSyncZoneEpochRecord.stampDeleted(
      deletionGeneration: 6, retiredZoneNames: [], onto: ready)
    ready[CloudSyncZoneEpochRecord.readyWitnessField] = "residue" as CKRecordValue
    #expect(CloudSyncZoneEpochRecord.generationState(from: ready) == nil)
  }

  @Test
  func compactionCutoffRoundTripsOnlyWhenControlAndSealAgreeCanonically() throws {
    let generationID = "generation-compaction"
    let zoneName = CloudSyncGenerationNaming.newZoneName(
      epoch: 6, generationID: generationID)
    let lease = CloudSyncZoneRebuildLease(
      identifier: "rebuild-compaction", ownerIdentifier: "database-compaction",
      epoch: 6, generationID: generationID, candidateZoneName: zoneName)
    let cutoff = "2025-01-01T00:00:00.000Z"
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: 6, generationID: generationID, zoneName: zoneName,
      readyWitness: "ready-compaction", tombstoneCompactionCutoff: cutoff)
    var manifest = emptyManifest
    manifest.tombstoneCompactionCutoff = cutoff

    let seal = try CloudSyncGenerationSealRecord.makeRecord(
      lease: lease, witness: descriptor.readyWitness, manifest: manifest)
    #expect(
      CloudSyncGenerationSealRecord.manifest(
        from: seal, descriptor: descriptor) == manifest)
    let noCutoffDescriptor = CloudSyncGenerationDescriptor(
      epoch: descriptor.epoch, generationID: descriptor.generationID,
      zoneName: descriptor.zoneName, readyWitness: descriptor.readyWitness)
    #expect(
      CloudSyncGenerationSealRecord.manifest(
        from: seal, descriptor: noCutoffDescriptor) == nil)

    let ready = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: [], onto: ready)
    guard case .ready(let decoded, let retired, _)? =
      CloudSyncZoneEpochRecord.generationState(from: ready)
    else {
      Issue.record("canonical compaction cutoff must round-trip through ready control")
      return
    }
    #expect(decoded == descriptor)
    #expect(retired.isEmpty)

    ready[CloudSyncZoneEpochRecord.tombstoneCompactionCutoffField] =
      "2025-01-01T00:00:00Z" as CKRecordValue
    #expect(CloudSyncZoneEpochRecord.generationState(from: ready) == nil)
    seal[CloudSyncGenerationSealRecord.tombstoneCompactionCutoffField] =
      "not-a-timestamp" as CKRecordValue
    #expect(
      CloudSyncGenerationSealRecord.manifest(
        from: seal, descriptor: descriptor) == nil)
  }

  @Test
  func rebuildingPreservesPreviousCompactionCutoffAndSealProof() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let first = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    var manifest = emptyManifest
    manifest.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let ready = try await publishReady(
      pusher: pusher, lease: first, manifest: manifest)

    let replacement = try await pusher.beginZoneRebuild(
      atLeast: ready.epoch, ownerIdentifier: "database-instance-b",
      allowFromDeleted: false, boundaryGuard: nil)
    guard case .rebuilding(_, let previous?, _, _, _)? =
      try await pusher.currentZoneGenerationState()
    else {
      Issue.record("replacement rebuild must retain its exact previous descriptor")
      return
    }
    #expect(previous == ready)
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: ready)
    #expect(
      try await pusher.validateGenerationRoot(
        context: context,
        expectation: .previousActive(lease: replacement, descriptor: ready),
        boundaryGuard: nil))
  }

  @Test
  func readyValidationRejectsControlSealCompactionCutoffDrift() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let lease = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    var manifest = emptyManifest
    manifest.tombstoneCompactionCutoff = "2025-01-01T00:00:00.000Z"
    let ready = try await publishReady(
      pusher: pusher, lease: lease, manifest: manifest)
    let sealID = CloudSyncGenerationSealRecord.recordID(zoneID: ready.zoneID)
    let seal = try #require(try await database.fetchRecord(with: sealID))
    seal[CloudSyncGenerationSealRecord.tombstoneCompactionCutoffField] =
      "2025-01-01T00:00:00.001Z" as CKRecordValue
    try await saveDirectly(seal, to: database)

    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: ready)
    #expect(
      try await pusher.validateGenerationRoot(
        context: context, expectation: .ready(ready), boundaryGuard: nil) == false)
  }

  @Test
  func controlDecoderRejectsGenerationAboveDurableTraversalMaximum() throws {
    let maximum = CloudSyncGenerationNaming.maximumGeneration
    let generationID = "generation-max"
    let descriptor = CloudSyncGenerationDescriptor(
      epoch: maximum, generationID: generationID,
      zoneName: CloudSyncGenerationNaming.newZoneName(
        epoch: maximum, generationID: generationID),
      readyWitness: "ready-max")
    let lease = CloudSyncZoneRebuildLease(
      identifier: "lease-max", ownerIdentifier: "owner-max",
      epoch: maximum, generationID: generationID,
      candidateZoneName: descriptor.zoneName)
    let record = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampReady(
      descriptor: descriptor, completedLease: lease,
      retiredZoneNames: [], onto: record)
    let above = NSNumber(value: Int64(maximum) + 1)
    record[CloudSyncZoneEpochRecord.epochField] = above
    record[CloudSyncZoneEpochRecord.activeEpochField] = above

    #expect(CloudSyncZoneEpochRecord.generationState(from: record) == nil)
  }

  @Test
  func predecessorValidationRequiresRootAndSealProvenanceAgreement() async throws {
    let database = GenerationDatabase()
    let pusher = CloudKitRecordPusher(database: database)
    let first = try await pusher.beginZoneRebuild(
      atLeast: 0, ownerIdentifier: "database-instance-a",
      allowFromDeleted: false, boundaryGuard: nil)
    let ready = try await publishReady(pusher: pusher, lease: first)
    let replacement = try await pusher.beginZoneRebuild(
      atLeast: ready.epoch, ownerIdentifier: "database-instance-b",
      allowFromDeleted: false, boundaryGuard: nil)

    let sealID = CloudSyncGenerationSealRecord.recordID(zoneID: ready.zoneID)
    let seal = try #require(try await database.fetchRecord(with: sealID))
    seal[CloudSyncGenerationSealRecord.rebuildIdentifierField] =
      "different-valid-rebuild" as CKRecordValue
    try await saveDirectly(seal, to: database)

    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: ready)
    let expectation = CloudSyncGenerationExpectation.previousActive(
      lease: replacement, descriptor: ready)
    #expect(
      try await pusher.validateGenerationRoot(
        context: context, expectation: expectation,
        boundaryGuard: nil) == false)
  }
}
