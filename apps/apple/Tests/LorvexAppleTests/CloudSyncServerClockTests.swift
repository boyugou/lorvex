import Foundation
import Testing
@preconcurrency import CloudKit

@testable import LorvexCloudSync

@Suite(.serialized)
struct CloudSyncServerClockTests {
  private enum SavedClockRecordMode: Sendable {
    case serverStamped(Date)
    case wrongIdentity(Date)
    case missingModificationDate
  }

  private actor ClockCommitDatabase: CloudKitDatabaseModifying {
    let mode: SavedClockRecordMode

    init(mode: SavedClockRecordMode) {
      self.mode = mode
    }

    func modifyRecordZones(
      saving _: [CKRecordZone], deleting _: [CKRecordZone.ID]
    ) async throws -> (
      saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
      deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
    ) {
      ([:], [:])
    }

    func modifyRecords(
      saving recordsToSave: [CKRecord], deleting _: [CKRecord.ID],
      savePolicy _: CKModifyRecordsOperation.RecordSavePolicy, atomically _: Bool
    ) async throws -> (
      saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
      deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
      guard let requested = recordsToSave.first else { return ([:], [:]) }
      let returned: CKRecord
      switch mode {
      case .serverStamped(let date):
        returned = requested
        setModificationDate(date, on: returned)
      case .wrongIdentity(let date):
        returned = CKRecord(
          recordType: requested.recordType,
          recordID: CKRecord.ID(
            recordName: "wrong-server-clock",
            zoneID: CloudSyncServerClockRecord.homeZoneID))
        setModificationDate(date, on: returned)
      case .missingModificationDate:
        returned = requested
      }
      returned[CloudSyncServerClockRecord.nonceField] =
        requested[CloudSyncServerClockRecord.nonceField]
      return ([requested.recordID: .success(returned)], [:])
    }

    private func setModificationDate(_ date: Date, on record: CKRecord) {
      _ = record.perform(NSSelectorFromString("setModificationDate:"), with: date)
    }
  }

  private actor GenerationControlDatabase: CloudKitDatabaseModifying {
    private var records: [CKRecord.ID: CKRecord]

    init(control: CKRecord) {
      records = [control.recordID: control]
    }

    func modifyRecordZones(
      saving recordZonesToSave: [CKRecordZone], deleting _: [CKRecordZone.ID]
    ) async throws -> (
      saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
      deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
    ) {
      let saves: [CKRecordZone.ID: Result<CKRecordZone, any Error>] = Dictionary(
        uniqueKeysWithValues: recordZonesToSave.map { ($0.zoneID, .success($0)) })
      return (saves, [:])
    }

    func modifyRecords(
      saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
      savePolicy _: CKModifyRecordsOperation.RecordSavePolicy, atomically _: Bool
    ) async throws -> (
      saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
      deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
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
      records[recordID]
    }
  }

  private actor ScriptedServerClock: CloudKitServerClockCommitting {
    private var dates: [Date]

    init(_ dates: [Date]) {
      self.dates = dates
    }

    func commitServerTime() async throws -> Date {
      guard !dates.isEmpty else {
        throw CloudSyncServerClockError.saveResultMissing
      }
      return dates.removeFirst()
    }
  }

  @Test
  func committerReturnsTheSavedRecordsServerModificationDate() async throws {
    let expected = Date(timeIntervalSince1970: 1_900_000_123.456)
    let committer = CloudKitServerClockCommitter(
      database: ClockCommitDatabase(mode: .serverStamped(expected)))

    let actual = try await committer.commitServerTime()

    #expect(actual == expected)
  }

  @Test
  func committerRejectsWrongIdentityAndMissingModificationDate() async {
    let wrongIdentity = CloudKitServerClockCommitter(
      database: ClockCommitDatabase(
        mode: .wrongIdentity(Date(timeIntervalSince1970: 1_900_000_000))))
    await #expect(throws: CloudSyncServerClockError.invalidSavedRecord) {
      try await wrongIdentity.commitServerTime()
    }

    let missingDate = CloudKitServerClockCommitter(
      database: ClockCommitDatabase(mode: .missingModificationDate))
    await #expect(throws: CloudSyncServerClockError.invalidSavedRecord) {
      try await missingDate.commitServerTime()
    }
  }

  @Test
  func foreignLeaseTakeoverUsesServerTimeAtTheExactIdleBoundary() async throws {
    let activity = Date(timeIntervalSince1970: 1_800_000_000)
    let (lease, control) = makeRebuildingControl(
      owner: "database-owner-a", activity: activity)
    let beforeBoundary = activity.addingTimeInterval(
      CloudKitRecordPusher.zoneRebuildTakeoverInterval - 1)
    let blocked = CloudKitRecordPusher(
      database: GenerationControlDatabase(control: control),
      systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore(),
      serverClock: ScriptedServerClock([beforeBoundary]))

    await #expect(throws: CloudSyncZoneEpochError.zoneRebuildInProgress) {
      try await blocked.beginZoneRebuild(
        atLeast: lease.epoch, ownerIdentifier: "database-owner-b",
        allowFromDeleted: false, boundaryGuard: nil)
    }

    let exactBoundary = activity.addingTimeInterval(
      CloudKitRecordPusher.zoneRebuildTakeoverInterval)
    let takeover = CloudKitRecordPusher(
      database: GenerationControlDatabase(control: makeRebuildingControl(
        owner: "database-owner-a", activity: activity).control),
      systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore(),
      serverClock: ScriptedServerClock([exactBoundary]))
    let replacement = try await takeover.beginZoneRebuild(
      atLeast: lease.epoch, ownerIdentifier: "database-owner-b",
      allowFromDeleted: false, boundaryGuard: nil)

    #expect(replacement.epoch == lease.epoch + 1)
    guard case .rebuilding(
      let saved, nil, .claimed, let retired, let savedActivity
    )? = try await takeover.currentZoneGenerationState() else {
      Issue.record("takeover must publish a new claimed lease")
      return
    }
    #expect(saved == replacement)
    #expect(retired == [lease.candidateZoneName])
    #expect(savedActivity == exactBoundary)
  }

  @Test
  func sameOwnerAndRestartRefreshLeaseActivityFromServerClock() async throws {
    let initialActivity = Date(timeIntervalSince1970: 1_800_000_000)
    let sameOwnerRefresh = Date(timeIntervalSince1970: 1_800_001_000)
    let restartRefresh = Date(timeIntervalSince1970: 1_800_002_000)
    let (lease, control) = makeRebuildingControl(
      owner: "database-owner-a", activity: initialActivity)
    let pusher = CloudKitRecordPusher(
      database: GenerationControlDatabase(control: control),
      systemFieldsStore: InMemoryCloudSyncRecordSystemFieldsStore(),
      serverClock: ScriptedServerClock([sameOwnerRefresh, restartRefresh]))

    let resumed = try await pusher.beginZoneRebuild(
      atLeast: lease.epoch, ownerIdentifier: lease.ownerIdentifier,
      allowFromDeleted: false, boundaryGuard: nil)
    #expect(resumed == lease)
    guard case .rebuilding(
      let refreshedLease, nil, .claimed, [], let refreshedActivity
    )? = try await pusher.currentZoneGenerationState() else {
      Issue.record("same-owner recovery must retain and refresh the lease")
      return
    }
    #expect(refreshedLease == lease)
    #expect(refreshedActivity == sameOwnerRefresh)

    let restarted = try await pusher.restartZoneRebuild(
      lease, boundaryGuard: nil)
    guard case .rebuilding(
      let restartedLease, nil, .claimed, let retired, let restartedActivity
    )? = try await pusher.currentZoneGenerationState() else {
      Issue.record("restart must publish and refresh a replacement lease")
      return
    }
    #expect(restartedLease == restarted)
    #expect(restarted.epoch == lease.epoch + 1)
    #expect(retired == [lease.candidateZoneName])
    #expect(restartedActivity == restartRefresh)
  }

  private func makeRebuildingControl(
    owner: String, activity: Date
  ) -> (lease: CloudSyncZoneRebuildLease, control: CKRecord) {
    let generationID = "generation-existing"
    let lease = CloudSyncZoneRebuildLease(
      identifier: "lease-existing", ownerIdentifier: owner,
      epoch: 7, generationID: generationID,
      candidateZoneName: CloudSyncGenerationNaming.newZoneName(
        epoch: 7, generationID: generationID))
    let control = CloudSyncZoneEpochRecord.makeRecord()
    CloudSyncZoneEpochRecord.stampRebuilding(
      lease, previousActive: nil, phase: .claimed,
      leaseActivityAt: activity, retiredZoneNames: [], onto: control)
    return (lease, control)
  }
}
