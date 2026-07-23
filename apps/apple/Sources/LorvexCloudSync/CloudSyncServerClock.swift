import Foundation
@preconcurrency import CloudKit

/// A server-time probe failed to return the exact singleton record that was
/// committed. Lease takeover must fail closed for every case.
enum CloudSyncServerClockError: Error, Equatable {
  case saveResultMissing
  case invalidSavedRecord
}

/// Narrow seam for the one server-owned instant needed by generation-lease
/// takeover. Tests script this directly; production commits the fixed CloudKit
/// singleton below.
protocol CloudKitServerClockCommitting: Sendable {
  func commitServerTime() async throws -> Date
}

/// Codec for the fixed server-clock singleton in the private default zone.
/// Every probe overwrites one random nonce, so the record count is permanently
/// bounded at one while CloudKit supplies a fresh modification timestamp.
enum CloudSyncServerClockRecord {
  static let recordType = "LorvexServerClock"
  static let recordName = "lorvex-server-clock"
  static let homeZoneID = CKRecordZone.default().zoneID
  static let nonceField = "nonce"

  static func recordID() -> CKRecord.ID {
    CKRecord.ID(recordName: recordName, zoneID: homeZoneID)
  }

  static func makeRecord(nonce: String) -> CKRecord {
    let record = CKRecord(recordType: recordType, recordID: recordID())
    record[nonceField] = nonce as CKRecordValue
    return record
  }

  static func validatedServerTime(from record: CKRecord, nonce: String) -> Date? {
    guard record.recordType == recordType,
      record.recordID == recordID(),
      record[nonceField] as? String == nonce,
      let modificationDate = record.modificationDate,
      modificationDate.timeIntervalSinceReferenceDate.isFinite
    else { return nil }
    return modificationDate
  }
}

/// Production server-clock commit over the same private database used by the
/// generation control plane. No fetch or compare-and-swap is involved: a fresh
/// random nonce is upserted with `.changedKeys`, and only the saved record's
/// CloudKit-owned modification date is trusted.
struct CloudKitServerClockCommitter: CloudKitServerClockCommitting {
  let database: any CloudKitDatabaseModifying

  func commitServerTime() async throws -> Date {
    let nonce = CloudSyncGenerationNaming.newGenerationID()
    let record = CloudSyncServerClockRecord.makeRecord(nonce: nonce)
    let (saveResults, _) = try await database.modifyRecords(
      saving: [record], deleting: [], savePolicy: .changedKeys, atomically: false)
    guard let result = saveResults[record.recordID] else {
      throw CloudSyncServerClockError.saveResultMissing
    }
    let saved = try result.get()
    guard let serverTime = CloudSyncServerClockRecord.validatedServerTime(
      from: saved, nonce: nonce)
    else {
      throw CloudSyncServerClockError.invalidSavedRecord
    }
    return serverTime
  }
}
