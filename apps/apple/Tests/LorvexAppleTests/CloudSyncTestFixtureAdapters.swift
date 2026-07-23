import Foundation
import LorvexCore
import LorvexSync
@preconcurrency import CloudKit

@testable import LorvexCloudSync

/// Canonical published generation used by non-generation-specific UI tests.
let cloudSyncTestDescriptor = CloudSyncGenerationDescriptor(
  epoch: 1, generationID: "test-generation-1",
  zoneName: CloudSyncZoneConstants.zoneName,
  readyWitness: "test-ready-witness-1")

/// Fleet-control record matching ``cloudSyncTestDescriptor``. Stateful pusher
/// tests return this from the default zone so every entity request exercises
/// the same exact-generation pre/post fence as production.
func makeCloudSyncTestControlRecord() -> CKRecord {
  let record = CloudSyncZoneEpochRecord.makeRecord()
  let completedLease = CloudSyncZoneRebuildLease(
    identifier: "test-completed-rebuild-1",
    ownerIdentifier: "test-database-instance-1",
    epoch: cloudSyncTestDescriptor.epoch,
    generationID: cloudSyncTestDescriptor.generationID,
    candidateZoneName: cloudSyncTestDescriptor.zoneName)
  CloudSyncZoneEpochRecord.stampReady(
    descriptor: cloudSyncTestDescriptor,
    completedLease: completedLease,
    retiredZoneNames: [],
    onto: record)
  return record
}

extension CloudKitRecordPusher {
  /// Invoke an ordinary entity push against the canonical published test
  /// generation without weakening the production API's explicit binding.
  func pushInTestGeneration(_ records: [CKRecord]) async throws -> [CloudSyncPushResult] {
    let context = CloudSyncGenerationContext(
      accountIdentifier: "account-A", descriptor: cloudSyncTestDescriptor)
    return try await push(
      records, context: context,
      expectation: .ready(cloudSyncTestDescriptor),
      boundaryGuard: nil)
  }
}

/// A zone argument on the pre-generation pusher initializer selected one fixed
/// namespace. Current requests carry their exact zone in the generation
/// context, so legacy unit fixtures may discard only that constructor argument.
extension CloudKitRecordPusher {
  init(
    database: any CloudKitDatabaseModifying,
    zoneID _: CKRecordZone.ID,
    systemFieldsStore: any CloudSyncRecordSystemFieldsStoring =
      InMemoryCloudSyncRecordSystemFieldsStore()
  ) {
    self.init(database: database, systemFieldsStore: systemFieldsStore)
  }
}

private struct CloudSyncTestServerClock: CloudKitServerClockCommitting {
  func commitServerTime() async throws -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
  }
}

extension CloudKitRecordPusher {
  init(
    database: any CloudKitDatabaseModifying,
    systemFieldsStore: any CloudSyncRecordSystemFieldsStoring =
      InMemoryCloudSyncRecordSystemFieldsStore()
  ) {
    self.init(
      database: database,
      systemFieldsStore: systemFieldsStore,
      serverClock: CloudSyncTestServerClock())
  }
}

/// Compatibility only for test assertions that predate account+zone-qualified
/// system-field keys. New generation tests always call the qualified methods.
extension CloudSyncRecordSystemFieldsStoring {
  func systemFields(forRecordName recordName: String) async -> Data? {
    await systemFields(
      accountIdentifier: "account-A",
      zoneName: CloudSyncZoneConstants.zoneName,
      recordName: recordName)
  }

  func store(_ data: Data, forRecordName recordName: String) async {
    await store(
      data, accountIdentifier: "account-A",
      zoneName: CloudSyncZoneConstants.zoneName,
      recordName: recordName)
  }
}

extension CloudSyncZoneEpochRecord {
  static func epoch(from record: CKRecord) -> Int? {
    generationState(from: record)?.epoch
  }
}

/// Small surface/UI fakes that only care whether a push occurred do not need to
/// reimplement the control-plane machinery. Generation-protocol tests use
/// explicit stateful pushers instead of these defaults.
extension CloudSyncRecordPushing {
  func currentZoneGenerationState() async throws -> CloudSyncZoneGenerationState? {
    .ready(descriptor: cloudSyncTestDescriptor, retiredZoneNames: [])
  }

  func beginZoneRebuild(
    atLeast floor: Int, ownerIdentifier: String, allowFromDeleted _: Bool,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    let epoch = max(floor, cloudSyncTestDescriptor.epoch) + 1
    return CloudSyncZoneRebuildLease(
      identifier: "test-rebuild-(epoch)", ownerIdentifier: ownerIdentifier,
      epoch: epoch, generationID: "test-generation-(epoch)",
      candidateZoneName: "LorvexData-e(epoch)-test-generation-(epoch)")
  }

  func restartZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneRebuildLease {
    let epoch = lease.epoch + 1
    return CloudSyncZoneRebuildLease(
      identifier: "test-rebuild-(epoch)", ownerIdentifier: lease.ownerIdentifier,
      epoch: epoch, generationID: "test-generation-(epoch)",
      candidateZoneName: "LorvexData-e(epoch)-test-generation-(epoch)")
  }

  func advanceZoneRebuildPhase(
    _ lease: CloudSyncZoneRebuildLease, to phase: CloudSyncZoneRebuildPhase,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func completeZoneRebuild(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest _: CloudSyncGenerationManifest,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncGenerationDescriptor {
    CloudSyncGenerationDescriptor(
      epoch: lease.epoch, generationID: lease.generationID,
      zoneName: lease.candidateZoneName, readyWitness: readyWitness)
  }

  func markCloudDataDeleted(
    atLeast _: Int,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncZoneGenerationState {
    .deleted(deletionGeneration: 2, retiredZoneNames: [], modifiedAt: nil)
  }

  func ensureZone(
    _ zoneID: CKRecordZone.ID, expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func ensureGenerationRoot(
    _ lease: CloudSyncZoneRebuildLease,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func validateGenerationRoot(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> Bool { true }

  func saveGenerationSeal(
    _ lease: CloudSyncZoneRebuildLease, readyWitness: String,
    manifest: CloudSyncGenerationManifest,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func publishTraversalWitness(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func deleteTraversalWitness(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    traversalIdentifier: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func readAuditRetentionMetadata(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata? { .initial }

  func mergeAuditRetentionMetadata(
    _ proposed: CloudSyncAuditRetentionMetadata,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncAuditRetentionMetadata { proposed }

  func publishGenerationWake(
    descriptor: CloudSyncGenerationDescriptor,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func push(
    _ records: [CKRecord], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    records.map {
      CloudSyncPushResult(recordName: $0.recordID.recordName, succeeded: true)
    }
  }

  func physicallyDelete(
    _ recordIDs: [CKRecord.ID], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecord.ID: Result<Void, any Error>] {
    Dictionary(uniqueKeysWithValues: recordIDs.map { ($0, .success(())) })
  }

  func deleteRetiredZone(
    zoneName: String, accountIdentifier: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func finalizeRetiredZoneDeletion(
    zoneName: String,
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws {}

  func allRecordZones(
    boundaryGuard _: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecordZone] { [] }

  func clearRecordSystemFieldsCache(
    accountIdentifier: String, zoneName: String
  ) async {}

  func clearAllRecordSystemFieldsCache() async {}
}
