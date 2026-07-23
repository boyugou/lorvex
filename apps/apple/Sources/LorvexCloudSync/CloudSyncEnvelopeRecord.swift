@preconcurrency import CloudKit
import Foundation
import LorvexDomain
import LorvexSync

/// Lossless mapping between the engine's canonical ``SyncEnvelope`` and a
/// CloudKit `CKRecord` of type `LorvexEntity` (the single-domain-record-type
/// envelope schema in `cloudkit/schema.ckdb`).
///
/// Every syncable entity shares one CK record type; the entity is identified by
/// the `entity_type` field and dispatched by the engine. The seven wire fields
/// the engine's LWW gate depends on — `entity_type`, `entity_id`, `operation`,
/// `version` (canonical HLC string), `payload_schema_version`, `payload`
/// (canonical JSON bytes), `device_id` — survive a round trip byte-identical:
/// the version HLC string and the payload string are stored and read back
/// verbatim, never re-parsed or re-serialized in transit.
///
/// Every wire field is written **end-to-end encrypted** via
/// `CKRecord.encryptedValues` (backed by the user's iCloud Keychain key), so
/// CloudKit's servers store only ciphertext: `entity_id` (a routing identity
/// that may still be a user-controlled natural key for `preference`),
/// `entity_type`, `operation`, the user-content `payload`, the `device_id`,
/// the `version` HLC string, and the receiver-compat `payload_schema_version`.
/// The record's custom top-level (plaintext, server-readable) field set is
/// EMPTY — the only identity in the clear is the record NAME, a SHA-256 of
/// `type\0id`. No field needs to be server-queryable or sortable: inbound sync
/// is driven by `CKFetchRecordZoneChangesOperation` change tokens (server
/// commit order), never by `CKQuery` or a sort descriptor.
/// ``decode(_:)`` reads each wire field ONLY from `encryptedValues` — the single
/// shape every record is written in, so a record missing an encrypted field is
/// undecodable rather than silently recovered from a plaintext sibling.
/// ``versionString(from:)`` exposes the same encrypted read for
/// ``CloudSyncRecordPushing``, whose conflict resolution reads `version` directly
/// off CKRecords surfaced by CloudKit's `serverRecordChanged` error payload
/// rather than through ``decode(_:)``.
public enum CloudSyncEnvelopeRecord {
  /// The single CloudKit record type all syncable entities map onto.
  public static let recordType = "LorvexEntity"

  public enum Field {
    public static let entityType = "entity_type"
    public static let entityId = "entity_id"
    public static let operation = "operation"
    public static let version = "version"
    public static let payloadSchemaVersion = "payload_schema_version"
    public static let payload = "payload"
    public static let deviceId = "device_id"

    /// Every wire field, stored end-to-end encrypted via `CKRecord.encryptedValues`
    /// so CloudKit's servers only ever see ciphertext: the routing `entity_id`,
    /// the `entity_type` and `operation` metadata, the user-content `payload`,
    /// the `device_id`, the `version` HLC string, and the receiver-compat
    /// `payload_schema_version`. This is the WHOLE wire-field set — the record
    /// carries no plaintext custom field. Re-stamped by ``restamp(from:onto:)``
    /// through the encrypted-values view, and cross-checked field-by-field
    /// against `cloudkit/schema.ckdb` by
    /// `script/verify_cloudkit_sync_readiness.py`, which requires each to be
    /// declared ENCRYPTED there.
    public static let encrypted = [
      entityId, entityType, operation, payload, deviceId, version, payloadSchemaVersion,
    ]
  }

  /// Stable, bounded CloudKit record name for an envelope: the SHA-256 hex of
  /// `entityType \0 entityId`, with NO plaintext prefix.
  ///
  /// Folding `entityType` into the hash — rather than letting it ride as a
  /// cleartext prefix — prevents direct disclosure of either input. This is not
  /// a secrecy boundary for enumerable low-entropy pairs: a record-metadata
  /// observer can hash plausible inputs and test for their presence. The NUL
  /// separator keeps the `(type, id)` pair unambiguous, so the name stays
  /// deterministic and unique per `(type, id)`. Hashing also keeps names
  /// independent of user-controlled id length, so long natural keys cannot
  /// exceed CloudKit's limit and sanitized strings cannot collide (`a/b` versus
  /// `a_b`).
  public static func recordName(entityType: String, entityId: String) -> String {
    SyncRecordName.opaque(entityType: entityType, entityId: entityId)
  }

  /// Encode an envelope into a `LorvexEntity` CKRecord in the given zone.
  public static func makeRecord(_ envelope: SyncEnvelope, zoneID: CKRecordZone.ID) -> CKRecord {
    let id = CKRecord.ID(
      recordName: recordName(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      zoneID: zoneID)
    let record = CKRecord(recordType: recordType, recordID: id)
    // Every wire field is end-to-end encrypted at rest, so CloudKit's servers
    // store only ciphertext; the stable record NAME (a SHA-256 of `type\0id`)
    // is what carries identity in the clear. No custom plaintext field exists.
    record.encryptedValues[Field.payloadSchemaVersion] = String(envelope.payloadSchemaVersion)
    record.encryptedValues[Field.entityType] = envelope.entityType.asString
    record.encryptedValues[Field.entityId] = envelope.entityId
    record.encryptedValues[Field.operation] = envelope.operation.asString
    record.encryptedValues[Field.payload] = envelope.payload
    record.encryptedValues[Field.deviceId] = envelope.deviceId
    record.encryptedValues[Field.version] = envelope.version.description
    return record
  }

  /// Classify a fetched `LorvexEntity` CKRecord into a typed decode outcome.
  ///
  /// The four outcomes let the inbound pipeline account for each record exactly:
  /// - ``EnvelopeDecodeOutcome/decoded(_:)`` — a valid ``SyncEnvelope`` to apply.
  /// - ``EnvelopeDecodeOutcome/foreign`` — a record of another `recordType`
  ///   sharing the zone; ignored, never counted against sync health.
  /// - ``EnvelopeDecodeOutcome/corrupt`` — a `LorvexEntity` missing or malforming
  ///   a required wire field, violating ``SyncEnvelope/validate()``'s bounded
  ///   wire contract, or using a same-generation unknown operation; the engine
  ///   never produced it, so it is dropped and counted undecodable.
  /// - ``EnvelopeDecodeOutcome/unknownEntityType(_:)`` — a record well-formed in
  ///   every wire field EXCEPT a future/unknown `entity_type`, OR a future/unknown
  ///   `operation` (with a known OR unknown `entity_type`) on a forward-compat
  ///   record (`payload_schema_version` ahead of this build). Carries the raw
  ///   fields so the caller can durably PARK it (not drop it) for a later build
  ///   that understands the future type / operation. Requires a CANONICAL `version`
  ///   (the HLC is the LWW ordering key and can never be re-derived), the same
  ///   bounded field/JSON/schema validation as a typed envelope, and — whenever
  ///   the `operation` is unrecognized — the forward-compat schema marker: a
  ///   same-generation unknown operation is genuine corruption this build should
  ///   have understood, so it stays ``EnvelopeDecodeOutcome/corrupt``.
  public static func decode(_ record: CKRecord) -> EnvelopeDecodeOutcome {
    guard record.recordType == recordType else { return .foreign }
    // The structural fields must be present and the `version` must be a CANONICAL
    // HLC (it is the LWW ordering key — a non-canonical version can never be
    // compared, so it is never parkable). `entity_type` and `operation` are parsed
    // AFTER, because a present-but-future value of either is forward-compat data to
    // PARK, not drop.
    guard
      let entityTypeRaw = encryptedString(record, Field.entityType),
      let entityId = encryptedString(record, Field.entityId),
      let operationRaw = encryptedString(record, Field.operation),
      let versionRaw = encryptedString(record, Field.version),
      let version = canonicalHlc(from: versionRaw),
      let payload = encryptedString(record, Field.payload),
      let deviceId = encryptedString(record, Field.deviceId),
      let schemaVersion = canonicalSchemaVersion(
        from: encryptedString(record, Field.payloadSchemaVersion))
    else { return .corrupt }

    let entityKind = EntityKind.parse(entityTypeRaw)
    let operation = operation(from: operationRaw)

    let raw = RawEnvelopeFields(
      entityType: entityTypeRaw, entityId: entityId, operation: operationRaw,
      version: version.description, payloadSchemaVersion: schemaVersion, payload: payload,
      deviceId: deviceId)

    let envelope: SyncEnvelope?
    if let entityKind, let operation {
      let candidate = SyncEnvelope(
        entityType: entityKind,
        entityId: entityId,
        operation: operation,
        version: version,
        payloadSchemaVersion: schemaVersion,
        payload: payload,
        deviceId: deviceId)
      guard case .success = candidate.validate() else { return .corrupt }
      envelope = candidate
    } else {
      guard case .success = raw.validate() else { return .corrupt }
      envelope = nil
    }

    guard record.recordID.recordName == recordName(entityType: entityTypeRaw, entityId: entityId)
    else { return .corrupt }

    if let envelope { return .decoded(envelope) }

    // Future/unknown entity_type, well-formed in every OTHER field (operation
    // recognized): durably parkable on its own — a new entity kind need not bump
    // the payload schema.
    if entityKind == nil, operation != nil {
      return .unknownEntityType(raw)
    }

    // Known entity_type but a present-yet-future operation on a forward-compat
    // record (schema ahead of this build): park like an unknown type rather than
    // drop, so a future build that adds the operation still applies the record
    // instead of losing it while the change token advances past it. A same/older
    // schema means this build SHOULD understand the operation, so an unrecognized
    // value there is genuine corruption → drop.
    if entityKind != nil, operation == nil, !operationRaw.isEmpty,
      schemaVersion > LorvexVersion.payloadSchemaVersion
    {
      return .unknownEntityType(raw)
    }

    // BOTH the entity_type and the operation are future/unknown on a forward-compat
    // record (schema ahead of this build): a newer build can introduce a new entity
    // kind and a new operation together, so park it rather than drop it while the
    // change token advances past it — the same forward-compat rule as the two lanes
    // above, applied when neither field resolves. A same/older schema means this
    // build SHOULD have understood both, so it stays corruption → drop.
    if entityKind == nil, operation == nil, !operationRaw.isEmpty,
      schemaVersion > LorvexVersion.payloadSchemaVersion
    {
      return .unknownEntityType(raw)
    }

    return .corrupt
  }

  /// Optional-returning convenience over ``decode(_:)`` for callers that only
  /// want the envelope and treat every non-``EnvelopeDecodeOutcome/decoded(_:)``
  /// outcome as "skip" — e.g. the push-path server-record decode, where the
  /// record is always this device's own known type. The inbound engine calls
  /// ``decode(_:)`` directly so it can park future-type records rather than drop
  /// them.
  public static func envelope(from record: CKRecord) -> SyncEnvelope? {
    if case .decoded(let envelope) = decode(record) { return envelope }
    return nil
  }

  private static func canonicalHlc(from raw: String) -> Hlc? {
    try? Hlc.parseCanonical(raw)
  }

  /// Re-stamp every wire field from `source` onto `target` through
  /// `CKRecord.encryptedValues` — the view every field is stored in. A plain
  /// subscript copy would read `nil` for these encrypted fields and silently
  /// blank them on the re-saved record. `target`'s record-change tag is left
  /// intact so a subsequent re-save still satisfies CloudKit's
  /// `ifServerRecordUnchanged` barrier — used by the pusher's local-wins
  /// conflict re-save.
  public static func restamp(from source: CKRecord, onto target: CKRecord) {
    for field in Field.encrypted { target.encryptedValues[field] = source.encryptedValues[field] }
  }

  /// Whether two records carry the exact same complete Lorvex envelope wire
  /// contract. Equal HLCs normally identify the same immutable mutation, but a
  /// corrupt record (or a cloned writer that violated HLC uniqueness) can reuse
  /// a version with different content. Push conflict resolution must not confirm
  /// that row merely because the ordering key matches.
  static func hasIdenticalWireFields(_ lhs: CKRecord, _ rhs: CKRecord) -> Bool {
    guard lhs.recordType == rhs.recordType, lhs.recordID == rhs.recordID else { return false }
    for field in Field.encrypted {
      guard let left = encryptedString(lhs, field),
        let right = encryptedString(rhs, field),
        left == right
      else { return false }
    }
    return true
  }

  /// Prove that two records occupy the same Lorvex entity slot independently
  /// of their mutation fields. This narrow proof is what permits recovery of a
  /// missing/noncanonical server version: a different embedded type/id (or a
  /// hash/name mismatch) remains foreign and must never be overwritten.
  static func hasIdenticalEnvelopeIdentity(_ lhs: CKRecord, _ rhs: CKRecord) -> Bool {
    guard lhs.recordType == recordType, rhs.recordType == recordType,
      lhs.recordID == rhs.recordID,
      let leftType = encryptedString(lhs, Field.entityType),
      let rightType = encryptedString(rhs, Field.entityType),
      let leftId = encryptedString(lhs, Field.entityId),
      let rightId = encryptedString(rhs, Field.entityId),
      leftType == rightType, leftId == rightId,
      lhs.recordID.recordName == recordName(entityType: leftType, entityId: leftId)
    else { return false }
    return true
  }

  /// Read the `version` HLC string field from `CKRecord.encryptedValues` — the
  /// only view it is written in. ``decode(_:)`` performs this same encrypted read
  /// inline; this entry point exists for ``CloudSyncRecordPushing``, whose conflict
  /// resolution reads `version` directly off CKRecords surfaced by CloudKit's
  /// `serverRecordChanged` error payload rather than through ``decode(_:)``.
  public static func versionString(from record: CKRecord) -> String? {
    encryptedString(record, Field.version)
  }

  /// Read a string wire field from `CKRecord.encryptedValues`, the only view the
  /// encoder writes it in; `nil` when the field is absent (an undecodable record).
  private static func encryptedString(_ record: CKRecord, _ field: String) -> String? {
    record.encryptedValues[field] as? String
  }

  private static func operation(from raw: String) -> SyncOperation? {
    switch raw {
    case SyncOperation.upsert.asString, "upsert": return .upsert
    case SyncOperation.delete.asString, "delete": return .delete
    default: return nil
    }
  }

  /// Parse `payload_schema_version` as a canonical UInt32 string. The shared
  /// envelope validator enforces the contract ladder's lower bound of one.
  /// The field is an ENCRYPTED STRING every writer emits as `String(UInt32)`, so
  /// an absent value, a numeric CK value, or a non-canonical string (leading
  /// zeros, sign, whitespace) is a shape no Lorvex build produces — the record is
  /// corrupt. A future build's larger version still parses, preserving the
  /// forward-compat park decision.
  private static func canonicalSchemaVersion(from raw: String?) -> UInt32? {
    guard let raw, let parsed = UInt32(raw), String(parsed) == raw else { return nil }
    return parsed
  }
}

/// Typed result of decoding a fetched CKRecord — see
/// ``CloudSyncEnvelopeRecord/decode(_:)``. Distinguishes the three nil-reasons
/// the old optional decode collapsed: a foreign record (ignore), structural
/// corruption (drop as undecodable), and a well-formed future `entity_type`
/// (durably park via ``RawEnvelopeFields`` rather than lose it).
public enum EnvelopeDecodeOutcome: Sendable, Equatable {
  /// A valid envelope ready to feed through the apply pipeline.
  case decoded(SyncEnvelope)
  /// A record of another `recordType` sharing the zone — ignore it.
  case foreign
  /// A `LorvexEntity` record missing or malforming a required field — drop it.
  case corrupt
  /// A record well-formed in every field but a future/unknown `entity_type`.
  case unknownEntityType(RawEnvelopeFields)
}
