import Foundation
import LorvexDomain

/// Wire-envelope payload canonicalization.
///
/// Delegates to the domain serializer
/// ``canonicalizeJSON(_:)`` for the sorted-key, compact, escape-table-stable
/// output, then layers the two sync-specific caps the wire boundary requires:
///
/// - ``maxJSONDepth`` (shared with the domain serializer, so a payload that
///   passes the store-side encoder also passes here) — enforced inside
///   `canonicalizeJSON`, surfaced here as ``SyncCanonError/depthExceeded``.
/// - ``maxCanonicalPayloadBytes`` — a heap/disk cap the depth guard alone does
///   not provide. Without it a peer could push a single multi-MB string, a
///   million flat keys, or a wide array; the result would land in the sync
///   shadow / inbox tables and persist under the LWW preservation guarantee.
///
/// String values are preserved byte-for-byte — no NFC or other normalization
/// is applied to user content.
public enum SyncCanonicalize {
  /// Maximum nesting depth, shared with `LorvexDomain.maxJSONDepth` so the
  /// wire-side wrapper and the in-process domain serializer reject identically.
  public static let maxJSONDepth = LorvexDomain.maxJSONDepth

  /// Maximum byte size for a canonicalized envelope payload. Shares the
  /// canonical `StorageSchema.maxPayloadBytes` source of truth with the shadow
  /// writer and the pending-inbox staging path.
  public static let maxCanonicalPayloadBytes = StorageSchema.maxPayloadBytes

  /// Errors returned by ``canonicalizeJSON(_:)``.
  public enum SyncCanonError: Error, Equatable {
    /// Input nested deeper than ``maxJSONDepth``.
    case depthExceeded
    /// The canonicalized output is larger than ``maxCanonicalPayloadBytes``.
    case payloadTooLarge(sizeBytes: Int)
  }

  /// Canonicalize a JSON value for wire emission: sorted keys, compact format,
  /// depth-checked, byte-capped. Output is byte-identical to the domain
  /// serializer plus the sync byte cap.
  public static func canonicalizeJSON(_ value: JSONValue) throws -> String {
    let out: String
    do {
      out = try LorvexDomain.canonicalizeJSON(value)
    } catch CanonError.depthExceeded {
      throw SyncCanonError.depthExceeded
    }
    let byteLen = out.utf8.count
    if byteLen > maxCanonicalPayloadBytes {
      throw SyncCanonError.payloadTooLarge(sizeBytes: byteLen)
    }
    return out
  }
}
