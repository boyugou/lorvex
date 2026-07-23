@preconcurrency import CloudKit
import Testing

@testable import LorvexCloudSync

/// SY7: a per-record fetch failure must not let the change token advance past the
/// missing record. `makeBatch` encodes the decision; `partitionModifications`
/// detects the failure.
struct CloudSyncRemoteChangeFetcherTests {
  private static let zoneID = CKRecordZone.ID(
    zoneName: "LorvexZone", ownerName: CKCurrentUserDefaultName)

  @Test
  func makeBatchWithholdsTokenAndStopsDrainOnPerRecordFailure() {
    let token = Data([1, 2, 3])
    let batch = CloudKitRemoteChangeFetcher.makeBatch(
      records: [],
      perRecordFailure: CloudSyncPerRecordFetchFailure(failedRecordCount: 1),
      changeTokenData: token, moreComing: true)

    // nil token => the coordinator keeps the prior cursor (no advance past
    // the failed record); moreComing forced false => re-pull next cycle, not a
    // tight re-pull of the same unadvanced page.
    #expect(batch.serverChangeTokenData == nil)
    #expect(batch.perRecordFailure != nil)
    #expect(batch.moreComing == false)
  }

  @Test
  func makeBatchAdvancesTokenWhenNoPerRecordFailure() {
    let token = Data([9, 9, 9])
    let batch = CloudKitRemoteChangeFetcher.makeBatch(
      records: [], perRecordFailure: nil,
      changeTokenData: token, moreComing: true)

    #expect(batch.serverChangeTokenData == token)
    #expect(batch.perRecordFailure == nil)
    #expect(batch.moreComing == true)
  }

  @Test
  func partitionFlagsPerRecordFailure() {
    let id = CKRecord.ID(recordName: "r1", zoneID: Self.zoneID)
    let results: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>] = [
      id: .failure(CKError(.networkFailure))
    ]

    let (records, perRecordFailure) = CloudKitRemoteChangeFetcher.partitionModifications(results)

    #expect(records.isEmpty)
    #expect(perRecordFailure?.failedRecordNames == ["r1"])
    #expect(perRecordFailure?.kind == .transient)
  }

  @Test
  func partitionReportsNoFailureForEmptyPage() {
    let (records, perRecordFailure) = CloudKitRemoteChangeFetcher.partitionModifications([:])

    #expect(records.isEmpty)
    #expect(perRecordFailure == nil)
  }
}
