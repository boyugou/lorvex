import CloudKit
import Foundation
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexApple
@testable import LorvexCloudSync

// MARK: - SyncEnvelope <-> CKRecord round trip

private let testZoneID = CKRecordZone.ID(
  zoneName: "LorvexZone", ownerName: CKCurrentUserDefaultName)

private func sampleEnvelope(
  entityType: EntityKind = .task,
  entityId: String = "01966a3f-7c8b-7d4e-8f3a-000000000001",
  operation: SyncOperation = .upsert,
  payload: String = #"{"title":"round trip","nested":{"a":[1,2,3]}}"#
) -> SyncEnvelope {
  SyncEnvelope(
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    version: try! Hlc.parse("1711234567890_0007_a1b2c3d4a1b2c3d4"),
    payloadSchemaVersion: 1,
    payload: payload,
    deviceId: "device-001")
}

private func isSHA256Hex(_ s: String) -> Bool {
  s.count == 64 && s.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
}

@Test
func envelopeEncodesToLorvexEntityRecordType() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  #expect(record.recordType == "LorvexEntity")
  #expect(record.recordID.zoneID == testZoneID)
  // SY5: the record name is a bare SHA-256 hex digest — no plaintext entity_type
  // prefix that would let CloudKit classify records by type.
  #expect(isSHA256Hex(record.recordID.recordName))
  #expect(record.recordID.recordName.hasPrefix("task_") == false)
}

@Test
func recordNameIsBoundedDeterministicAndCollisionResistant() {
  let safe = CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: "a_b")
  let unsafe = CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: "a/b")
  let long = CloudSyncEnvelopeRecord.recordName(
    entityType: "memory", entityId: String(repeating: "x", count: 500))

  #expect(unsafe != safe)
  #expect(unsafe == CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: "a/b"))
  // Every name is a bare 64-char SHA-256 hex digest regardless of id length.
  #expect(isSHA256Hex(safe))
  #expect(isSHA256Hex(unsafe))
  #expect(isSHA256Hex(long))
}

@Test
func recordNameFoldsEntityTypeIntoHashWithNoPlaintextPrefix() {
  // SY5: the entity_type is folded INTO the digest, not carried as a cleartext
  // prefix. The same id under two types yields two distinct names, and neither
  // name discloses the type or the id.
  let id = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  let taskName = CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: id)
  let listName = CloudSyncEnvelopeRecord.recordName(entityType: "list", entityId: id)

  #expect(taskName != listName)
  #expect(isSHA256Hex(taskName))
  #expect(isSHA256Hex(listName))
  #expect(taskName.hasPrefix("task") == false)
  #expect(taskName.contains(id) == false)
  // Deterministic: recomputing the same (type, id) reproduces the name exactly.
  #expect(taskName == CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: id))
}

@Test
func envelopeRoundTripsLosslessly() {
  let original = sampleEnvelope()
  let record = CloudSyncEnvelopeRecord.makeRecord(original, zoneID: testZoneID)
  let decoded = CloudSyncEnvelopeRecord.envelope(from: record)
  // Every wire field the engine's LWW gate depends on must survive verbatim.
  #expect(decoded == original)
  #expect(decoded?.entityType == original.entityType)
  #expect(decoded?.entityId == original.entityId)
  #expect(decoded?.operation == original.operation)
  #expect(decoded?.version.description == original.version.description)
  #expect(decoded?.payload == original.payload)
  #expect(decoded?.payloadSchemaVersion == original.payloadSchemaVersion)
  #expect(decoded?.deviceId == original.deviceId)
}

@Test
func deleteOperationRoundTrips() {
  let original = sampleEnvelope(operation: .delete, payload: "{}")
  let record = CloudSyncEnvelopeRecord.makeRecord(original, zoneID: testZoneID)
  let decoded = CloudSyncEnvelopeRecord.envelope(from: record)
  #expect(decoded?.operation == .delete)
  #expect(decoded == original)
}

@Test
func decodingRejectsForeignRecordType() {
  let foreign = CKRecord(recordType: "SomethingElse", recordID: CKRecord.ID(recordName: "x"))
  #expect(CloudSyncEnvelopeRecord.envelope(from: foreign) == nil)
}

@Test
func decodingRejectsRecordMissingRequiredField() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  // Remove the version field (stored encrypted) — the engine can never use
  // this record. The plain top-level subscript was already empty for
  // `version` post-encryption, so the encrypted view is what must be cleared.
  record.encryptedValues["version"] = nil
  #expect(CloudSyncEnvelopeRecord.envelope(from: record) == nil)
}

// MARK: - Typed decode outcomes (S-4 classification)

private func unknownTypeRecord(
  entityType: String = "quantum_widget",
  entityId: String = "01966a3f-7c8b-7d4e-8f3a-0000000000ff",
  recordName: String? = nil
) -> CKRecord {
  let id = CKRecord.ID(
    recordName: recordName
      ?? CloudSyncEnvelopeRecord.recordName(entityType: entityType, entityId: entityId),
    zoneID: testZoneID)
  let record = CKRecord(recordType: CloudSyncEnvelopeRecord.recordType, recordID: id)
  record.encryptedValues["entity_type"] = entityType
  record.encryptedValues["entity_id"] = entityId
  record.encryptedValues["operation"] = "upsert"
  record.encryptedValues["version"] = "1711234567890_0007_a1b2c3d4a1b2c3d4"
  record.encryptedValues["payload_schema_version"] = "1"
  record.encryptedValues["payload"] = #"{"q":1}"#
  record.encryptedValues["device_id"] = "device-001"
  return record
}

@Test
func decodeClassifiesForeignAndCorruptDistinctly() {
  let foreign = CKRecord(recordType: "SomethingElse", recordID: CKRecord.ID(recordName: "x"))
  #expect(CloudSyncEnvelopeRecord.decode(foreign) == .foreign)

  let corrupt = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  corrupt.encryptedValues["version"] = nil
  #expect(CloudSyncEnvelopeRecord.decode(corrupt) == .corrupt)

  let good = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  #expect(CloudSyncEnvelopeRecord.decode(good) == .decoded(sampleEnvelope()))
}

@Test
func decodeClassifiesWellFormedFutureTypeAsUnknownEntityType() {
  guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(unknownTypeRecord())
  else {
    Issue.record("expected .unknownEntityType for a well-formed future entity_type")
    return
  }
  #expect(raw.entityType == "quantum_widget")
  #expect(raw.entityId == "01966a3f-7c8b-7d4e-8f3a-0000000000ff")
  #expect(raw.operation == "upsert")
  #expect(raw.version == "1711234567890_0007_a1b2c3d4a1b2c3d4")
  #expect(raw.payloadSchemaVersion == 1)
  #expect(raw.payload == #"{"q":1}"#)
  #expect(raw.deviceId == "device-001")
  // The optional convenience still returns nil — it can never become an envelope.
  #expect(CloudSyncEnvelopeRecord.envelope(from: unknownTypeRecord()) == nil)
}

@Test
func decodeTreatsUnknownTypeWithBadOtherFieldAsCorrupt() {
  // Unknown type AND otherwise malformed (bad HLC) stays .corrupt — only a
  // record well-formed in every OTHER field earns the deferral lane.
  let record = unknownTypeRecord()
  record.encryptedValues["version"] = "not-an-hlc"
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

/// A record with a KNOWN entity_type but a future/unknown `operation` on a
/// forward-compat record.
private func futureOperationRecord(
  schemaVersion: UInt32,
  operation: String = "archive",
  entityId: String = "01966a3f-7c8b-7d4e-8f3a-0000000000fe",
  recordName: String? = nil
) -> CKRecord {
  let id = CKRecord.ID(
    recordName: recordName
      ?? CloudSyncEnvelopeRecord.recordName(entityType: "task", entityId: entityId),
    zoneID: testZoneID)
  let record = CKRecord(recordType: CloudSyncEnvelopeRecord.recordType, recordID: id)
  record.encryptedValues["entity_type"] = "task"
  record.encryptedValues["entity_id"] = entityId
  record.encryptedValues["operation"] = operation
  record.encryptedValues["version"] = "1711234567890_0007_a1b2c3d4a1b2c3d4"
  record.encryptedValues["payload_schema_version"] = String(schemaVersion)
  record.encryptedValues["payload"] = #"{"title":"t"}"#
  record.encryptedValues["device_id"] = "device-001"
  return record
}

@Test
func decodeParksFutureOperationOnForwardCompatRecord() {
  // A future operation a newer build authored (payload_schema_version ahead of
  // this build) must be durably PARKED, not dropped, so today's device does not
  // lose it while the change token advances past it.
  let record = futureOperationRecord(schemaVersion: LorvexVersion.payloadSchemaVersion + 1)
  guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(record) else {
    Issue.record(
      "expected a park (.unknownEntityType) for a future operation on a forward-compat record")
    return
  }
  #expect(raw.entityType == "task")
  #expect(raw.operation == "archive")
  #expect(raw.version == "1711234567890_0007_a1b2c3d4a1b2c3d4")
  // It can never become an envelope on this build.
  #expect(CloudSyncEnvelopeRecord.envelope(from: record) == nil)
}

@Test
func decodeDropsUnknownOperationAtCurrentSchema() {
  // A same-generation unknown operation is corruption this build should have
  // understood — dropped, not parked.
  let record = futureOperationRecord(schemaVersion: LorvexVersion.payloadSchemaVersion)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeParksUnknownTypeAndUnknownOperationOnForwardCompatRecord() {
  // BOTH the entity_type and the operation are future/unknown on a schema-ahead
  // record: a newer build introduced a new entity kind and a new operation
  // together. It must be PARKED (forward-compat), not dropped, so today's device
  // keeps it for a later build instead of losing it while the token advances.
  let record = unknownTypeRecord()
  record.encryptedValues["operation"] = "archive"
  record.encryptedValues["payload_schema_version"] =
    String(LorvexVersion.payloadSchemaVersion + 1)
  guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(record) else {
    Issue.record("expected a park for unknown type + unknown operation on a schema-ahead record")
    return
  }
  #expect(raw.entityType == "quantum_widget")
  #expect(raw.operation == "archive")
}

@Test
func decodeDropsUnknownTypeAndUnknownOperationAtCurrentSchema() {
  // Same shape at the local schema: this build should have understood both, so it
  // is corruption → dropped, not parked.
  let record = unknownTypeRecord()
  record.encryptedValues["operation"] = "archive"
  record.encryptedValues["payload_schema_version"] =
    String(LorvexVersion.payloadSchemaVersion)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeRejectsEmptyEntityIdBeforeTypedApply() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(entityId: ""), zoneID: testZoneID)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
  #expect(CloudSyncEnvelopeRecord.envelope(from: record) == nil)
}

@Test
func decodeRejectsRecordNameMismatchedToPayloadIdentity() {
  let record = futureOperationRecord(
    schemaVersion: LorvexVersion.payloadSchemaVersion + 1,
    operation: "upsert",
    recordName: "wrong_record_name")
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeRejectsUnknownTypeWhenRecordNameMismatchesRawIdentity() {
  let record = unknownTypeRecord(recordName: "wrong_future_record_name")
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

// MARK: - Inbound envelope trust boundary

@Test
func decodeRejectsKnownEnvelopeWithEmptyOrOversizedDeviceId() {
  let empty = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  empty.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = ""
  #expect(CloudSyncEnvelopeRecord.decode(empty) == .corrupt)

  let oversized = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  oversized.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = String(
    repeating: "d", count: SyncEnvelope.maxEnvelopeDeviceIdLen + 1)
  #expect(CloudSyncEnvelopeRecord.decode(oversized) == .corrupt)
}

@Test
func decodeRejectsKnownEnvelopeWithOversizedInvalidOrTooDeepPayload() {
  let oversized = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  oversized.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] =
    "\"" + String(repeating: "x", count: SyncEnvelope.maxEnvelopePayloadBytes) + "\""
  #expect(CloudSyncEnvelopeRecord.decode(oversized) == .corrupt)

  let invalid = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  invalid.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = "{\"unterminated\":"
  #expect(CloudSyncEnvelopeRecord.decode(invalid) == .corrupt)

  let tooDeep = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  tooDeep.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] =
    String(repeating: "[", count: SyncEnvelope.maxJSONDepth) + "0"
    + String(repeating: "]", count: SyncEnvelope.maxJSONDepth)
  #expect(CloudSyncEnvelopeRecord.decode(tooDeep) == .corrupt)
}

@Test
func decodeRejectsKnownEnvelopeWhosePayloadSchemaExceedsAheadCap() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  let tooFarAhead =
    LorvexVersion.payloadSchemaVersion + SyncEnvelope.maxPayloadSchemaVersionAhead + 1
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] =
    String(tooFarAhead)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeAppliesTheSameBoundsToUnknownFutureRecords() {
  let emptyDevice = unknownTypeRecord()
  emptyDevice.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = ""
  #expect(CloudSyncEnvelopeRecord.decode(emptyDevice) == .corrupt)

  let oversizedDevice = unknownTypeRecord()
  oversizedDevice.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = String(
    repeating: "d", count: SyncEnvelope.maxEnvelopeDeviceIdLen + 1)
  #expect(CloudSyncEnvelopeRecord.decode(oversizedDevice) == .corrupt)

  let oversizedPayload = unknownTypeRecord()
  oversizedPayload.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] =
    "\"" + String(repeating: "x", count: SyncEnvelope.maxEnvelopePayloadBytes) + "\""
  #expect(CloudSyncEnvelopeRecord.decode(oversizedPayload) == .corrupt)

  let invalidPayload = unknownTypeRecord()
  invalidPayload.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = "{\"unterminated\":"
  #expect(CloudSyncEnvelopeRecord.decode(invalidPayload) == .corrupt)

  let tooDeepPayload = unknownTypeRecord()
  tooDeepPayload.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] =
    String(repeating: "[", count: SyncEnvelope.maxJSONDepth) + "0"
    + String(repeating: "]", count: SyncEnvelope.maxJSONDepth)
  #expect(CloudSyncEnvelopeRecord.decode(tooDeepPayload) == .corrupt)

  let schemaTooFarAhead = unknownTypeRecord()
  let tooFarAhead =
    LorvexVersion.payloadSchemaVersion + SyncEnvelope.maxPayloadSchemaVersionAhead + 1
  schemaTooFarAhead.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] =
    String(tooFarAhead)
  #expect(CloudSyncEnvelopeRecord.decode(schemaTooFarAhead) == .corrupt)
}

@Test
func decodeBoundsUnknownFutureIdentityAndOperationBeforeParking() {
  let emptyType = unknownTypeRecord(entityType: "")
  #expect(CloudSyncEnvelopeRecord.decode(emptyType) == .corrupt)

  let oversizedTypeName = String(repeating: "t", count: 129)
  let oversizedType = unknownTypeRecord(entityType: oversizedTypeName)
  #expect(CloudSyncEnvelopeRecord.decode(oversizedType) == .corrupt)

  let unsafeId = unknownTypeRecord(entityId: "../future")
  #expect(CloudSyncEnvelopeRecord.decode(unsafeId) == .corrupt)

  let oversizedOperation = unknownTypeRecord()
  oversizedOperation.encryptedValues[CloudSyncEnvelopeRecord.Field.operation] = String(
    repeating: "o", count: 129)
  oversizedOperation.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] =
    String(LorvexVersion.payloadSchemaVersion + 1)
  #expect(CloudSyncEnvelopeRecord.decode(oversizedOperation) == .corrupt)
}

// MARK: - Canonical future versions remain recoverable

/// A well-formed `task` upsert record whose `version` HLC string is replaced
/// wholesale (identity + routing + payload stay valid, only the clock changes).
private func recordWithVersion(_ versionString: String) -> CKRecord {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] = versionString
  return record
}

@Test
func decodeAcceptsCanonicalFutureVersion() {
  // A peer with a badly advanced clock can legitimately emit any canonical HLC
  // inside the format's fixed-width range. Classifying it as corrupt would make
  // every nil-token and incremental traversal retry the same page forever. The
  // apply clock observes peers with bounded drift, while an explicit edit uses
  // the detached dominance lane, so decode must remain independent of local wall
  // time.
  let ceiling = "9999999999999_0000_a1b2c3d4a1b2c3d4"  // ~year 2286
  guard case .decoded(let envelope) = CloudSyncEnvelopeRecord.decode(recordWithVersion(ceiling))
  else {
    Issue.record("a canonical future HLC must not poison the traversal cursor")
    return
  }
  #expect(envelope.version.description == ceiling)
}

@Test
func decodeAcceptsVersionAFewDaysAhead() {
  // An honest dead-RTC / NTP skew is a pure wire classification concern. The
  // local clock is advanced only by the apply pipeline, never by decode.
  let fixedNow: UInt64 = 1_711_234_567_890
  let threeDaysMs: UInt64 = 3 * 24 * 60 * 60 * 1000
  let ahead = try! Hlc(
    physicalMs: fixedNow + threeDaysMs, counter: 0, deviceSuffix: "a1b2c3d4a1b2c3d4")
  guard
    case .decoded = CloudSyncEnvelopeRecord.decode(recordWithVersion(ahead.description))
  else {
    Issue.record("a few-days-ahead version must still decode")
    return
  }
}

@Test
func decodeRejectsNonCanonicalWireVersion() {
  let unpadded = recordWithVersion("1711234567890_7_a1b2c3d4a1b2c3d4")
  let mixedCase = recordWithVersion("1711234567890_0007_A1B2C3D4A1B2C3D4")

  #expect(CloudSyncEnvelopeRecord.decode(unpadded) == .corrupt)
  #expect(CloudSyncEnvelopeRecord.decode(mixedCase) == .corrupt)
}

// MARK: - End-to-end encryption of payload / device_id / version (CloudKit encryptedValues)

@Test
func makeRecordEncryptsPayloadDeviceIdAndVersion() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)

  // payload + device_id + version live ONLY in the end-to-end-encrypted view;
  // the plain top-level subscript (what CloudKit servers store in cleartext)
  // is empty for each.
  #expect(
    record.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String
      == #"{"title":"round trip","nested":{"a":[1,2,3]}}"#)
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] as? String == "device-001")
  #expect(
    record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] as? String
      == "1711234567890_0007_a1b2c3d4a1b2c3d4")
  #expect(record[CloudSyncEnvelopeRecord.Field.payload] == nil)
  #expect(record[CloudSyncEnvelopeRecord.Field.deviceId] == nil)
  #expect(record[CloudSyncEnvelopeRecord.Field.version] == nil)
}

@Test
func makeRecordLeavesNoPlaintextCustomFields() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)

  // The record's custom top-level (plaintext, server-readable) field set is
  // EMPTY: every wire field is either end-to-end encrypted or folded into the
  // SHA-256 record name. In particular there is no `updated_at` field at all,
  // and `payload_schema_version` lives ONLY in the encrypted view.
  #expect(record["updated_at"] == nil)
  #expect(record.encryptedValues["updated_at"] == nil)
  #expect(record[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] == nil)
  #expect(
    record.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] as? String == "1")

  // The identity + routing fields are NOT plaintext — they live in the
  // encrypted view (asserted in `makeRecordEncryptsIdentityRoutingAndContent`).
  #expect(record[CloudSyncEnvelopeRecord.Field.entityType] == nil)
  #expect(record[CloudSyncEnvelopeRecord.Field.entityId] == nil)
  #expect(record[CloudSyncEnvelopeRecord.Field.operation] == nil)
}

@Test
func makeRecordEncryptsIdentityRoutingAndContent() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)

  // entity_type / entity_id / operation join payload / device_id / version in
  // the end-to-end-encrypted view; CloudKit's servers only ever see ciphertext.
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityType] as? String == "task")
  #expect(
    record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] as? String
      == "01966a3f-7c8b-7d4e-8f3a-000000000001")
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.operation] as? String == "upsert")
}

@Test
func memoryEntityIdIsEncryptedNotPlaintext() {
  // Memory routes on the row's opaque id, while the human key rides inside the
  // encrypted payload. The routing id still lives only in the encrypted view,
  // never as a plaintext CloudKit field, and must round-trip intact.
  let memoryId = "01966a3f-7c8b-7d4e-8f3a-00000000a001"
  let original = sampleEnvelope(
    entityType: .memory, entityId: memoryId,
    payload: #"{"key":"grocery list preferences","content":"buy oat milk"}"#)
  let record = CloudSyncEnvelopeRecord.makeRecord(original, zoneID: testZoneID)

  // The routing id is ciphertext-only.
  #expect(record[CloudSyncEnvelopeRecord.Field.entityId] == nil)
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] as? String == memoryId)
  // The record NAME (plaintext identity) is the bare SHA-256 hash, never the raw
  // id and never a plaintext type prefix.
  #expect(record.recordID.recordName.contains(memoryId) == false)
  #expect(isSHA256Hex(record.recordID.recordName))
  #expect(record.recordID.recordName.hasPrefix("memory_") == false)

  // Round-trips with the opaque id intact.
  #expect(CloudSyncEnvelopeRecord.decode(record) == .decoded(original))
  #expect(CloudSyncEnvelopeRecord.envelope(from: record)?.entityId == memoryId)
}

@Test
func preferenceEntityIdIsEncryptedNotPlaintext() {
  // A preference's entity_id is its semantically meaningful, wire-stable key.
  // It remains ciphertext-only and round-trips intact.
  let prefKey = PreferenceKeys.prefTimezone
  let original = sampleEnvelope(
    entityType: .preference, entityId: prefKey, payload: #"{"value":"America/Los_Angeles"}"#)
  let record = CloudSyncEnvelopeRecord.makeRecord(original, zoneID: testZoneID)

  #expect(record[CloudSyncEnvelopeRecord.Field.entityId] == nil)
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] as? String == prefKey)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .decoded(original))
}

/// A record whose wire fields all live in `encryptedValues` — the shape
/// `makeRecord` produces — with a caller-chosen `entity_type`, `operation`,
/// and `payload_schema_version`, for exercising the forward-compat gate on
/// the encrypted schema-version read.
private func encryptedFieldsRecord(
  entityType: String,
  operation: String,
  schemaVersion: UInt32,
  entityId: String = "01966a3f-7c8b-7d4e-8f3a-0000000000fd"
) -> CKRecord {
  let id = CKRecord.ID(
    recordName: CloudSyncEnvelopeRecord.recordName(entityType: entityType, entityId: entityId),
    zoneID: testZoneID)
  let record = CKRecord(recordType: CloudSyncEnvelopeRecord.recordType, recordID: id)
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityType] = entityType
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.entityId] = entityId
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.operation] = operation
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] =
    "1711234567890_0007_a1b2c3d4a1b2c3d4"
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] =
    String(schemaVersion)
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] = #"{"q":1}"#
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] = "device-001"
  return record
}

@Test
func decodeParksFutureOperationWithEncryptedSchemaVersion() {
  // The forward-compat park-vs-drop gate must read `payload_schema_version`
  // from the encrypted view: a schema-ahead record with an unknown operation,
  // carrying its schema version ONLY in `encryptedValues`, is parked.
  let record = encryptedFieldsRecord(
    entityType: "task", operation: "archive",
    schemaVersion: LorvexVersion.payloadSchemaVersion + 1)
  guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(record) else {
    Issue.record("expected a park for a future operation with an encrypted schema version")
    return
  }
  #expect(raw.operation == "archive")
  #expect(raw.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)
}

@Test
func decodeParksUnknownTypeAndOperationWithEncryptedSchemaVersion() {
  // Same gate, both fields unknown: a schema-ahead record whose encrypted
  // schema version is the only forward-compat marker still parks.
  let record = encryptedFieldsRecord(
    entityType: "quantum_widget", operation: "archive",
    schemaVersion: LorvexVersion.payloadSchemaVersion + 1)
  guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(record) else {
    Issue.record("expected a park for unknown type + operation with an encrypted schema version")
    return
  }
  #expect(raw.entityType == "quantum_widget")
  #expect(raw.payloadSchemaVersion == LorvexVersion.payloadSchemaVersion + 1)
}

@Test
func decodeDropsUnknownOperationAtCurrentSchemaWithEncryptedSchemaVersion() {
  // A same-generation unknown operation stays corruption when the schema
  // version is read from the encrypted view — the gate compares the same
  // value it would have compared plaintext.
  let record = encryptedFieldsRecord(
    entityType: "task", operation: "archive",
    schemaVersion: LorvexVersion.payloadSchemaVersion)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeReadsEncryptedRecord() {
  // A record produced the new (encrypted) way — payload, device_id, AND
  // version all live in `encryptedValues` — round-trips through decode.
  let original = sampleEnvelope(payload: #"{"secret":"user note"}"#)
  let record = CloudSyncEnvelopeRecord.makeRecord(original, zoneID: testZoneID)
  #expect(record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] != nil)
  #expect(CloudSyncEnvelopeRecord.decode(record) == .decoded(original))
}

@Test
func decodeRejectsRecordCarryingWireFieldsOnlyInPlaintext() {
  // Encrypted-only decode: a record that carries every wire field in the plain
  // top-level view (NOT `encryptedValues`) is undecodable — the decoder never
  // reads a plaintext sibling, so no such record can masquerade as valid.
  let id = CKRecord.ID(
    recordName: CloudSyncEnvelopeRecord.recordName(
      entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001"),
    zoneID: testZoneID)
  let plaintextOnly = CKRecord(recordType: CloudSyncEnvelopeRecord.recordType, recordID: id)
  plaintextOnly[CloudSyncEnvelopeRecord.Field.entityType] = "task" as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.entityId] =
    "01966a3f-7c8b-7d4e-8f3a-000000000001" as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.operation] = "upsert" as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] = "1" as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.version] =
    "1711234567890_0007_a1b2c3d4a1b2c3d4" as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.payload] =
    #"{"title":"round trip","nested":{"a":[1,2,3]}}"# as CKRecordValue
  plaintextOnly[CloudSyncEnvelopeRecord.Field.deviceId] = "device-001" as CKRecordValue

  #expect(CloudSyncEnvelopeRecord.decode(plaintextOnly) == .corrupt)
}

@Test
func decodeRejectsVersionCarriedOnlyInPlaintext() {
  // Every other field is encrypted, but `version` lives only in the plaintext
  // view: encrypted-only decode reads no plaintext sibling, so the missing
  // encrypted `version` makes the record undecodable.
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  let versionValue = record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] as? String
  record.encryptedValues[CloudSyncEnvelopeRecord.Field.version] = nil
  record[CloudSyncEnvelopeRecord.Field.version] = versionValue as CKRecordValue?

  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func restampCopiesEveryWireFieldThroughEncryptedValues() {
  // The local-wins re-save re-stamps the client's fields onto a fresh server
  // record. Every wire field must travel through the encrypted view; a plain
  // copy would read nil and blank payload/device_id/version on the re-saved
  // record. restamp writes only the encrypted view, so the target's custom
  // top-level view stays empty.
  let client = CloudSyncEnvelopeRecord.makeRecord(
    sampleEnvelope(payload: #"{"k":"v"}"#), zoneID: testZoneID)
  let target = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(
      recordName: CloudSyncEnvelopeRecord.recordName(
        entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001"),
      zoneID: testZoneID))

  CloudSyncEnvelopeRecord.restamp(from: client, onto: target)

  #expect(target.encryptedValues[CloudSyncEnvelopeRecord.Field.payload] as? String == #"{"k":"v"}"#)
  #expect(target.encryptedValues[CloudSyncEnvelopeRecord.Field.deviceId] as? String == "device-001")
  #expect(
    target.encryptedValues[CloudSyncEnvelopeRecord.Field.version] as? String
      == "1711234567890_0007_a1b2c3d4a1b2c3d4")
  #expect(
    target.encryptedValues[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] as? String
      == "1")
  #expect(target[CloudSyncEnvelopeRecord.Field.payload] == nil)
  #expect(target[CloudSyncEnvelopeRecord.Field.version] == nil)
  #expect(target[CloudSyncEnvelopeRecord.Field.payloadSchemaVersion] == nil)
  #expect(target["updated_at"] == nil)
  // The re-stamped copy decodes back to the same envelope.
  #expect(
    CloudSyncEnvelopeRecord.decode(target) == .decoded(sampleEnvelope(payload: #"{"k":"v"}"#)))
}

@Test
func versionStringReadsEncryptedValueOnly() {
  // `CloudSyncRecordPushing`'s conflict resolution reads `version` directly
  // off CKRecords surfaced by CloudKit's `serverRecordChanged` error payload
  // (not through `decode(_:)`), via this entry point. It reads ONLY the
  // encrypted view — the single shape `version` is written in.
  let base = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(recordName: "version_x", zoneID: testZoneID))
  #expect(CloudSyncEnvelopeRecord.versionString(from: base) == nil)

  let encrypted = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(recordName: "version_e", zoneID: testZoneID))
  encrypted.encryptedValues[CloudSyncEnvelopeRecord.Field.version] =
    "1711234567890_0007_a1b2c3d4a1b2c3d4"
  #expect(
    CloudSyncEnvelopeRecord.versionString(from: encrypted)
      == "1711234567890_0007_a1b2c3d4a1b2c3d4")

  // A `version` present only in the plaintext view is NOT read.
  let plaintextOnly = CKRecord(
    recordType: CloudSyncEnvelopeRecord.recordType,
    recordID: CKRecord.ID(recordName: "version_l", zoneID: testZoneID))
  plaintextOnly[CloudSyncEnvelopeRecord.Field.version] =
    "1711234560000_0000_a1b2c3d4a1b2c3d4" as CKRecordValue
  #expect(CloudSyncEnvelopeRecord.versionString(from: plaintextOnly) == nil)
}

// MARK: - payload_schema_version is a required canonical encrypted string

@Test
func decodeRejectsMissingPayloadSchemaVersion() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  record.encryptedValues["payload_schema_version"] = nil
  // Required encrypted field: an absent value is corruption (every writer emits
  // it), never a silent default-0.
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeRejectsNumericPayloadSchemaVersion() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  // The schema declares it ENCRYPTED STRING; a numeric CK value is a shape no
  // writer produces.
  record.encryptedValues["payload_schema_version"] = 1 as NSNumber
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeRejectsNonCanonicalPayloadSchemaVersion() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  record.encryptedValues["payload_schema_version"] = "01"
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeRejectsZeroPayloadSchemaVersion() {
  let record = CloudSyncEnvelopeRecord.makeRecord(sampleEnvelope(), zoneID: testZoneID)
  record.encryptedValues["payload_schema_version"] = "0"
  #expect(CloudSyncEnvelopeRecord.decode(record) == .corrupt)
}

@Test
func decodeStillParksAFutureCanonicalSchemaVersion() {
  // Forward-compat MUST survive the tightening: a future integer version on a
  // record with a future operation still parks (not corrupt), proving the
  // canonical parse accepts larger values rather than dropping them.
  let record = futureOperationRecord(schemaVersion: LorvexVersion.payloadSchemaVersion + 5)
  guard case .unknownEntityType = CloudSyncEnvelopeRecord.decode(record) else {
    Issue.record("a future canonical schema version must still park a forward-compat record")
    return
  }
}

// MARK: - Generation-control INT64 decoding

@Test
func generationControlReadsNonnegativeInt64AndRejectsInvalidValues() {
  #expect(CloudSyncRecordValueCodec.nonnegativeInt(7 as NSNumber) == 7)
  // A negative generation would break the monotonic counter contract.
  #expect(CloudSyncRecordValueCodec.nonnegativeInt(-1 as NSNumber) == nil)
  #expect(CloudSyncRecordValueCodec.nonnegativeInt(1.5 as NSNumber) == nil)
  #expect(CloudSyncRecordValueCodec.nonnegativeInt(true as NSNumber) == nil)
  // The schema declares `epoch` INT64; a legacy string representation is rejected.
  #expect(CloudSyncRecordValueCodec.nonnegativeInt("9" as NSString) == nil)
  // Absent → nil.
  #expect(CloudSyncRecordValueCodec.nonnegativeInt(nil) == nil)
}
