import Foundation
import GRDB
import LorvexDomain
import LorvexStore

public enum GenerationSnapshotError: Error, Sendable, Equatable {
  case invalidPage(offset: Int, limit: Int)
  case recordLimitExceeded(limit: Int, observedAtLeast: Int)
  case byteLimitExceeded(limit: Int64, observedAtLeast: Int64)
  case invalidStoredVersion(entityType: String, entityId: String, version: String)
  case payloadShadowVersionMismatch(
    entityType: String, entityId: String, liveVersion: String, shadowVersion: String)
  case invalidPayloadShadowSchemaVersion(
    entityType: String, entityId: String, storedVersion: Int)
  case missingPayload(entityType: String, entityId: String)
  case duplicateIdentity(entityType: String, entityId: String)
  case duplicateRecordName(String)
  case invalidBinding
  case bindingMismatch
  case stagingNotFound
  case corruptStaging
  case invalidWitness
  case progressMismatch(expected: Int, actual: Int)
  case readbackAlreadyComplete
  case manifestMismatch
}

/// Stable, read-only domain inventory copied into one unique CloudKit generation.
/// It never mutates payload shadows or reads, inserts, confirms, or otherwise
/// mutates `sync_outbox`.
public struct GenerationSnapshotManifest: Sendable, Equatable {
  public var sourceLocalChangeSequence: UInt64
  public var recordCount: Int
  public var canonicalDigest: String
  public var auditRecordCount: Int
  public var auditWitnessDigest: String
  public var totalEncodedBytes: Int64

  public init(
    sourceLocalChangeSequence: UInt64, recordCount: Int,
    canonicalDigest: String, auditRecordCount: Int,
    auditWitnessDigest: String, totalEncodedBytes: Int64 = 0
  ) {
    self.sourceLocalChangeSequence = sourceLocalChangeSequence
    self.recordCount = recordCount
    self.canonicalDigest = canonicalDigest
    self.auditRecordCount = auditRecordCount
    self.auditWitnessDigest = auditWitnessDigest
    self.totalEncodedBytes = totalEncodedBytes
  }
}

public struct GenerationSnapshotPage: Sendable, Equatable {
  public var manifest: GenerationSnapshotManifest
  public var envelopes: [SyncEnvelope]
  public var nextOffset: Int?

  public init(
    manifest: GenerationSnapshotManifest, envelopes: [SyncEnvelope],
    nextOffset: Int?
  ) {
    self.manifest = manifest
    self.envelopes = envelopes
    self.nextOffset = nextOffset
  }
}

public enum GenerationSnapshot {
  public static let maximumRecordCount = 100_000
  /// CloudKit documents 200 records as the maximum per modify operation.
  public static let maximumPageSize = 200
  /// A conservative encrypted-record batch budget below CloudKit's 1-MiB
  /// per-record ceiling. Pagination stops at either this or `maximumPageSize`.
  public static let maximumPageEncodedBytes = 768 * 1024
  /// Durable disk staging permits realistic large databases while preventing a
  /// corrupt or adversarial local store from consuming unbounded disk.
  public static let maximumTotalEncodedBytes: Int64 = 512 * 1024 * 1024
  /// Canonical wrapper bytes can expand a 256-KiB JSON payload through string
  /// escaping, but remain below this per-envelope staging bound.
  public static let maximumEncodedEnvelopeBytes = 768 * 1024

  public static func auditCanonicalDigest(
    _ envelopes: [SyncEnvelope]
  ) throws -> String {
    try digest(witnesses: envelopes.map(witness(for:)), auditOnly: true)
  }

  static func makeLiveEnvelope(
    _ db: Database, kind: EntityKind, entityId: String, version: String,
    payload: JSONValue, deviceId: String
  ) throws -> SyncEnvelope {
    guard let hlc = try? Hlc.parseCanonical(version),
      Hlc.isOperationallyAcceptableWire(hlc)
    else {
      throw GenerationSnapshotError.invalidStoredVersion(
        entityType: kind.asString, entityId: entityId, version: version)
    }
    let shadow = try PayloadShadow.getShadow(
      db, entityType: kind.asString, entityID: entityId)
    if let candidate = shadow {
      guard let shadowHlc = try? Hlc.parseCanonical(candidate.baseVersion) else {
        throw GenerationSnapshotError.payloadShadowVersionMismatch(
          entityType: kind.asString, entityId: entityId, liveVersion: version,
          shadowVersion: candidate.baseVersion)
      }
      if shadowHlc != hlc {
        // A shadow and its known row form one versioned snapshot. HLC ordering
        // alone cannot prove whether a later legacy-schema write intentionally
        // superseded future fields. Any mismatch is bookkeeping corruption: fail
        // closed and retain the only preserved copy for diagnosis/repair.
        throw GenerationSnapshotError.payloadShadowVersionMismatch(
          entityType: kind.asString, entityId: entityId, liveVersion: version,
          shadowVersion: candidate.baseVersion)
      }
    }
    let merged: JSONValue
    let effectiveShadowSchemaVersion: UInt32?
    if let shadow {
      merged = try PayloadShadow.mergePayloadWithShadowAfterLookup(
        db, entityType: kind.asString, entityID: entityId,
        knownPayload: payload, shadow: shadow)
      do {
        effectiveShadowSchemaVersion = try PayloadShadow.requireWirePayloadSchemaVersion(
          shadow, context: "generation payload shadow")
      } catch {
        throw GenerationSnapshotError.invalidPayloadShadowSchemaVersion(
          entityType: kind.asString, entityId: entityId,
          storedVersion: shadow.payloadSchemaVersion)
      }
    } else {
      merged = payload
      effectiveShadowSchemaVersion = nil
    }
    guard case .object(var object) = merged else {
      throw GenerationSnapshotError.missingPayload(
        entityType: kind.asString, entityId: entityId)
    }
    object["version"] = .string(version)
    let envelope = SyncEnvelope(
      entityType: kind, entityId: entityId, operation: .upsert,
      version: hlc,
      payloadSchemaVersion: effectiveShadowSchemaVersion.map {
        max(LorvexVersion.payloadSchemaVersion, $0)
      } ?? LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: deviceId)
    guard case .success = envelope.validate() else {
      throw GenerationSnapshotError.missingPayload(
        entityType: kind.asString, entityId: entityId)
    }
    return envelope
  }

  static func canonicalWitnessValue(_ envelope: SyncEnvelope) -> JSONValue {
    .object([
      "device_id": .string(envelope.deviceId),
      "entity_id": .string(envelope.entityId),
      "entity_type": .string(envelope.entityType.asString),
      "operation": .string(envelope.operation.asString),
      "payload": .string(envelope.payload),
      "payload_schema_version": .uint(UInt64(envelope.payloadSchemaVersion)),
      "version": .string(envelope.version.description),
    ])
  }
}
