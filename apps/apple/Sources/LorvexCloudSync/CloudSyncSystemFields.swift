@preconcurrency import CloudKit
import Foundation

/// Archives and restores the system fields of a `CKRecord`: its record ID and
/// the server-assigned change tag. A record rebuilt on top of restored system
/// fields saves without a `serverRecordChanged` round trip as long as nobody
/// else changed it on the server.
enum CloudSyncSystemFields {
  static func archive(_ record: CKRecord) -> Data {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return archiver.encodedData
  }

  /// The record the archive describes, or nil when the archive is unreadable
  /// or describes a different record ID.
  static func restore(_ data: Data, expecting recordID: CKRecord.ID) -> CKRecord? {
    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    unarchiver.requiresSecureCoding = true
    let record = CKRecord(coder: unarchiver)
    unarchiver.finishDecoding()
    guard let record, record.recordType == CloudSyncEnvelopeRecord.recordType,
      record.recordID == recordID
    else { return nil }
    return record
  }
}
