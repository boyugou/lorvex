import Foundation
import LorvexStore

/// Stable fixed-width identity shared by the sync engine and its CloudKit carrier.
///
/// CloudKit stores every syncable aggregate in one `LorvexEntity` record type.
/// The record name is the only plaintext routing value, so it is the SHA-256 of
/// the unambiguous `(entity_type, entity_id)` pair rather than either raw value.
/// This hides the literal strings and bounds their length; it does not prevent a
/// dictionary test of enumerable low-entropy pairs. Keeping this primitive in
/// the transport-independent sync module lets recovery code compare a complete
/// remote-record inventory with local rows without teaching the core about
/// CloudKit.
public enum SyncRecordName {
  /// SHA-256 hex of `entityType + NUL + entityId`.
  public static func opaque(entityType: String, entityId: String) -> String {
    Sha256Checksum.hexDigest(Data((entityType + "\u{0}" + entityId).utf8))
  }
}
