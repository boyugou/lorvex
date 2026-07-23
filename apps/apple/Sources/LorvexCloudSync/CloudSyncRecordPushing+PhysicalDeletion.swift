import Foundation
import LorvexDomain
@preconcurrency import CloudKit

extension CloudKitRecordPusher {
  public func physicallyDelete(
    _ recordIDs: [CKRecord.ID], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CKRecord.ID: Result<Void, any Error>] {
    if recordIDs.isEmpty { return [:] }
    guard context.matches(expectation),
      recordIDs.allSatisfy({ $0.zoneID == context.zoneID })
    else { throw CloudSyncGenerationBoundaryCrossed() }
    try await assertRequestBoundary(
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    let (_, deleteResults) = try await database.modifyRecords(
      saving: [], deleting: recordIDs,
      savePolicy: .ifServerRecordUnchanged, atomically: false)
    try await assertRequestBoundary(
      context: context, expectation: expectation,
      boundaryGuard: boundaryGuard)
    for (recordID, result) in deleteResults {
      if case .success = result {
        await systemFieldsStore.remove(
          accountIdentifier: context.accountIdentifier,
          zoneName: recordID.zoneID.zoneName,
          recordName: recordID.recordName)
      }
    }
    return deleteResults
  }

  public func clearRecordSystemFieldsCache(
    accountIdentifier: String, zoneName: String
  ) async {
    await systemFieldsStore.removeAll(
      accountIdentifier: accountIdentifier, zoneName: zoneName)
  }

  public func clearAllRecordSystemFieldsCache() async {
    await systemFieldsStore.removeAll()
  }
}
