import CryptoKit
import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Compact proof for one canonical sync envelope. Candidate readback persists
/// only these values, never a second copy of the potentially large payload.
public struct GenerationSnapshotWitness: Sendable, Equatable, Hashable {
  public let recordName: String
  public let envelopeDigest: String
  public let encodedByteCount: Int64
  public let isAudit: Bool

  public init(
    recordName: String, envelopeDigest: String, encodedByteCount: Int64,
    isAudit: Bool
  ) throws {
    guard GenerationSnapshot.isLowerHex(recordName, count: 64),
      GenerationSnapshot.isLowerHex(envelopeDigest, count: 64),
      encodedByteCount > 0,
      encodedByteCount <= Int64(GenerationSnapshot.maximumEncodedEnvelopeBytes)
    else { throw GenerationSnapshotError.invalidWitness }
    self.recordName = recordName
    self.envelopeDigest = envelopeDigest
    self.encodedByteCount = encodedByteCount
    self.isAudit = isAudit
  }
}

extension GenerationSnapshot {
  static let manifestDigestDomain = Data("lorvex-generation-manifest-v2\0".utf8)
  static let auditDigestDomain = Data("lorvex-generation-audit-v2\0".utf8)

  /// Canonical byte representation of the exact seven-field wire envelope.
  /// Only one envelope is materialized at a time during staging.
  public static func canonicalEnvelopeData(_ envelope: SyncEnvelope) throws -> Data {
    Data(try SyncCanonicalize.canonicalizeJSON(canonicalWitnessValue(envelope)).utf8)
  }

  /// Produce the compact identity, digest, size, and audit classification used
  /// by both local staging and remote final-state readback verification.
  public static func witness(for envelope: SyncEnvelope) throws -> GenerationSnapshotWitness {
    let encoded = try canonicalEnvelopeData(envelope)
    return try GenerationSnapshotWitness(
      recordName: SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      envelopeDigest: Sha256Checksum.hexDigest(encoded),
      encodedByteCount: Int64(encoded.count),
      isAudit: envelope.entityType == .aiChangelog)
  }

  /// Overall proof from compact per-envelope hashes. Payload bytes never enter
  /// the aggregate material: witnesses are sorted by opaque record name and fed
  /// incrementally into SHA-256 with fixed-width fields and domain separation.
  public static func digest(
    witnesses: [GenerationSnapshotWitness], auditOnly: Bool = false
  ) throws -> String {
    let selected = witnesses.filter { !auditOnly || $0.isAudit }
      .sorted { $0.recordName < $1.recordName }
    var previous: String?
    var hasher = SHA256()
    hasher.update(data: auditOnly ? auditDigestDomain : manifestDigestDomain)
    for witness in selected {
      guard previous != witness.recordName else {
        throw GenerationSnapshotError.duplicateRecordName(witness.recordName)
      }
      previous = witness.recordName
      hasher.update(data: Data(witness.recordName.utf8))
      hasher.update(data: Data(witness.envelopeDigest.utf8))
      var byteCount = UInt64(witness.encodedByteCount).bigEndian
      withUnsafeBytes(of: &byteCount) { hasher.update(bufferPointer: $0) }
      hasher.update(data: Data([witness.isAudit ? 1 : 0]))
    }
    return lowerHex(hasher.finalize())
  }

  static func digest(
    cursor: RowCursor, auditOnly: Bool
  ) throws -> String {
    var previous: String?
    var hasher = SHA256()
    hasher.update(data: auditOnly ? auditDigestDomain : manifestDigestDomain)
    while let row = try cursor.next() {
      let witness = try GenerationSnapshotWitness(
        recordName: row["record_name"], envelopeDigest: row["envelope_digest"],
        encodedByteCount: row["encoded_byte_count"], isAudit: row["is_audit"])
      guard previous != witness.recordName else {
        throw GenerationSnapshotError.duplicateRecordName(witness.recordName)
      }
      previous = witness.recordName
      hasher.update(data: Data(witness.recordName.utf8))
      hasher.update(data: Data(witness.envelopeDigest.utf8))
      var byteCount = UInt64(witness.encodedByteCount).bigEndian
      withUnsafeBytes(of: &byteCount) { hasher.update(bufferPointer: $0) }
      hasher.update(data: Data([witness.isAudit ? 1 : 0]))
    }
    return lowerHex(hasher.finalize())
  }

  static func isLowerHex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy {
      (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
    }
  }

  private static func lowerHex<D: Sequence>(_ digest: D) -> String
  where D.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var result = [UInt8]()
    result.reserveCapacity(64)
    for byte in digest {
      result.append(digits[Int(byte >> 4)])
      result.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: result, as: UTF8.self)
  }
}
