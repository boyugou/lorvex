import CoreFoundation
import Foundation
@preconcurrency import CloudKit

/// Canonical decoder for CloudKit INT64 marker fields.
///
/// `NSNumber`'s convenience accessors coerce booleans, truncate floating-point
/// values, and wrap integers that do not fit the requested type. Those are all
/// invalid wire shapes for generation-control records, where accepting a value
/// with different bytes can select the wrong authority boundary.
enum CloudSyncRecordValueCodec {
  static func nonnegativeInt(_ raw: CKRecordValue?) -> Int? {
    guard let value = nonnegativeInt64(raw), value <= Int64(Int.max) else {
      return nil
    }
    return Int(value)
  }

  static func nonnegativeInt64(_ raw: CKRecordValue?) -> Int64? {
    guard let number = raw as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      !CFNumberIsFloatType(number)
    else { return nil }
    let value = number.int64Value
    guard value >= 0 else { return nil }
    return value
  }

  static func nonnegativeUInt64(_ raw: CKRecordValue?) -> UInt64? {
    guard let value = nonnegativeInt64(raw) else { return nil }
    return UInt64(value)
  }
}
