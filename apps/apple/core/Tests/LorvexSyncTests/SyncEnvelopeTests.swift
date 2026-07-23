import Foundation
import LorvexDomain
import XCTest

@testable import LorvexSync

/// Ports `lorvex-sync/src/envelope/tests.rs`. The wire shape (snake_case field
/// names, lowercase `entity_type`, `"upsert"`/`"delete"` operation, canonical
/// HLC string `version`) must round-trip; `validate()` enforces the field caps
/// and entity_id safety/canonical-shape rules.
final class SyncEnvelopeTests: XCTestCase {
  private func wellFormed() -> SyncEnvelope {
    SyncEnvelope(
      entityType: .task,
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001",
      operation: .upsert,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1,
      payload: #"{"title":"test"}"#,
      deviceId: "device-001")
  }

  private func encode(_ env: SyncEnvelope) -> String {
    String(data: try! JSONEncoder().encode(env), encoding: .utf8)!
  }

  private func decode(_ json: String) throws -> SyncEnvelope {
    try JSONDecoder().decode(SyncEnvelope.self, from: Data(json.utf8))
  }

  func testTypedEnvelopeRoundTripsThroughSerde() throws {
    let json = encode(wellFormed())
    XCTAssertTrue(
      json.contains(#""entity_type":"task""#),
      "entity_type must serialize as canonical lowercase string: \(json)")
    let parsed = try decode(json)
    XCTAssertEqual(parsed.entityType, .task)
    XCTAssertEqual(parsed.operation, .upsert)
  }

  func testDeserializeRejectsUnknownEntityType() {
    let json = """
      {
        "entity_type": "future_unknown_kind",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
      }
      """
    XCTAssertThrowsError(try decode(json))
  }

  func testOperationSerializesSnakeCase() {
    XCTAssertEqual(
      String(data: try! JSONEncoder().encode(SyncOperation.upsert), encoding: .utf8), #""upsert""#)
    XCTAssertEqual(
      String(data: try! JSONEncoder().encode(SyncOperation.delete), encoding: .utf8), #""delete""#)
  }

  func testDeserializeRejectsUnknownOperation() {
    let json = """
      {
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "future_rekey",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
      }
      """
    XCTAssertThrowsError(try decode(json))
  }

  func testDeserializeRejectsNoncanonicalHlcWireValue() {
    let json = """
      {
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0_A1B2C3D4A1B2C3D4",
        "payload_schema_version": 1,
        "payload": "{}",
        "device_id": "device-001"
      }
      """
    XCTAssertNoThrow(try Hlc.parse("1711234567890_0_A1B2C3D4A1B2C3D4"))
    XCTAssertThrowsError(try decode(json))
  }

  func testEnvelopeAcceptsUnknownTopLevelFields() throws {
    let json = """
      {
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-000000000001",
        "operation": "upsert",
        "version": "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "payload_schema_version": 1,
        "payload": "{\\"title\\":\\"test\\"}",
        "device_id": "device-001",
        "future_signature": "abc123",
        "future_compression": "zstd"
      }
      """
    let parsed = try decode(json)
    XCTAssertEqual(parsed.entityType, .task)
    XCTAssertEqual(parsed.operation, .upsert)
  }

  func testValidateAcceptsWellFormedEnvelope() {
    XCTAssertNoThrow(try wellFormed().validate().get())
  }

  func testValidateRejectsPayloadSchemaVersionZero() {
    var env = wellFormed()
    env.payloadSchemaVersion = 0
    guard case .failure(.payloadSchemaVersionUnsupported(let version)) = env.validate() else {
      return XCTFail("expected payloadSchemaVersionUnsupported")
    }
    XCTAssertEqual(version, 0)
  }

  func testValidateAcceptsMemoryOpaqueUuidEntityId() {
    var env = wellFormed()
    env.entityType = .memory
    env.entityId = "01966a3f-7c8b-7d4e-8f3a-00000000a001"
    env.payload =
      #"{"key":"grocery list preferences","content":"buy oat milk","updated_at":"2026-04-01T00:00:00.000Z"}"#
    XCTAssertNoThrow(try env.validate().get())
  }

  func testValidateRejectsMemoryKeyAsEntityId() {
    var env = wellFormed()
    env.entityType = .memory
    env.entityId = "grocery list preferences"
    env.payload =
      #"{"key":"grocery list preferences","content":"buy oat milk","updated_at":"2026-04-01T00:00:00.000Z"}"#
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertEqual(reason, "canonical hyphenated lowercase UUID")
  }

  func testValidateRejectsOversizedPayload() {
    var env = wellFormed()
    env.payload = String(repeating: "x", count: SyncEnvelope.maxEnvelopePayloadBytes + 1)
    guard case .failure(.fieldTooLong(let field, let len, let max)) = env.validate() else {
      return XCTFail("expected fieldTooLong")
    }
    XCTAssertEqual(field, "payload")
    XCTAssertEqual(len, SyncEnvelope.maxEnvelopePayloadBytes + 1)
    XCTAssertEqual(max, SyncEnvelope.maxEnvelopePayloadBytes)
  }

  func testEnvelopePayloadCapMatchesStorageAndCanonicalizationAuthority() {
    XCTAssertEqual(SyncEnvelope.maxEnvelopePayloadBytes, StorageSchema.maxPayloadBytes)
    XCTAssertEqual(
      SyncEnvelope.maxEnvelopePayloadBytes, SyncCanonicalize.maxCanonicalPayloadBytes)
  }

  func testValidateRejectsMalformedPayloadJson() {
    var env = wellFormed()
    env.payload = #"{"title":"unterminated""#
    guard case .failure(.invalidPayloadJson) = env.validate() else {
      return XCTFail("expected invalidPayloadJson")
    }
  }

  func testValidateRejectsMalformedDeletePayloadJson() {
    var env = wellFormed()
    env.operation = .delete
    env.payload = #"{"deleted":true"#
    guard case .failure(.invalidPayloadJson) = env.validate() else {
      return XCTFail("expected invalidPayloadJson for delete payload")
    }
  }

  func testValidateRejectsOversizedDeviceId() {
    var env = wellFormed()
    env.deviceId = String(repeating: "x", count: SyncEnvelope.maxEnvelopeDeviceIdLen + 1)
    guard case .failure(.fieldTooLong(let field, _, _)) = env.validate() else {
      return XCTFail("expected fieldTooLong")
    }
    XCTAssertEqual(field, "device_id")
  }

  func testValidateRejectsPathTraversalEntityId() {
    var env = wellFormed()
    env.entityId = "../../../etc/passwd"
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertTrue(reason.contains("path-traversal"))
  }

  func testValidateRejectsPathSeparatorEntityId() {
    var env = wellFormed()
    env.entityId = "task/secrets"
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertTrue(reason.contains("path separator"))
  }

  func testValidateRejectsControlCharEntityId() {
    var env = wellFormed()
    env.entityId = "task-\u{001B}inject"
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertTrue(reason.contains("control character"))
  }

  func testValidateAcceptsCanonicalUuidAndCompositeEdgeEntityId() {
    var env = wellFormed()
    env.entityId = "01966a3f-7c8b-7d4e-8f3a-000000000001"
    XCTAssertNoThrow(try env.validate().get())
    env.entityType = .taskTag
    env.entityId = "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000002"
    XCTAssertNoThrow(try env.validate().get())
  }

  func testValidateRejectsNonCanonicalUuidForUuidBackedKind() {
    var env = wellFormed()
    env.entityId = "not-a-uuid"
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertTrue(reason.contains("canonical hyphenated lowercase UUID"))
  }

  func testValidateRejectsNonCanonicalCompositeEdgeMembers() {
    var env = wellFormed()
    env.entityType = .taskTag
    env.entityId = "not-a-uuid:01966a3f-7c8b-7d4e-8f3a-000000000002"
    guard case .failure(.unsafeEntityId(_, let reason)) = env.validate() else {
      return XCTFail("expected unsafeEntityId")
    }
    XCTAssertTrue(reason.contains("canonical"))
  }

  func testValidateRejectsPayloadSchemaVersionTooFarAhead() {
    var env = wellFormed()
    env.payloadSchemaVersion = UInt32.max
    guard
      case .failure(.payloadSchemaVersionTooFarAhead(let version, let localMax)) = env.validate()
    else {
      return XCTFail("expected payloadSchemaVersionTooFarAhead")
    }
    XCTAssertEqual(version, UInt32.max)
    XCTAssertEqual(
      localMax, LorvexVersion.payloadSchemaVersion + SyncEnvelope.maxPayloadSchemaVersionAhead)
  }

  func testValidateAcceptsPayloadSchemaVersionWithinHeadroom() {
    var env = wellFormed()
    env.payloadSchemaVersion = LorvexVersion.payloadSchemaVersion + 1
    XCTAssertNoThrow(try env.validate().get())
    env.payloadSchemaVersion =
      LorvexVersion.payloadSchemaVersion + SyncEnvelope.maxPayloadSchemaVersionAhead
    XCTAssertNoThrow(try env.validate().get())
  }

  func testRawEnvelopeValidationRejectsNoncanonicalHlc() {
    let raw = RawEnvelopeFields(
      entityType: "future_kind",
      entityId: "01966a3f-7c8b-7d4e-8f3a-000000000001",
      operation: "upsert",
      version: "1711234567890_0_A1B2C3D4A1B2C3D4",
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: "{}",
      deviceId: "device-001")

    guard case .failure(.invalidVersion(let value)) = raw.validate() else {
      return XCTFail("expected invalidVersion")
    }
    XCTAssertEqual(value, "1711234567890_0_A1B2C3D4A1B2C3D4")
  }

  /// `containers` nested arrays around a leaf `0`: `[[…[0]…]]`.
  private func nestedArrayPayload(_ containers: Int) -> String {
    String(repeating: "[", count: containers) + "0" + String(repeating: "]", count: containers)
  }

  /// The `JSONValue` equivalent of ``nestedArrayPayload(_:)`` so the envelope
  /// scan and `canonicalizeJSON` can be checked on the identical structure.
  private func nestedArrayValue(_ containers: Int) -> JSONValue {
    var value: JSONValue = 0
    for _ in 0..<containers { value = .array([value]) }
    return value
  }

  /// The envelope depth scan and `canonicalizeJSON` must agree on the boundary.
  /// `writeCanonical` errors on any value at depth `maxJSONDepth` (a leaf wrapped
  /// in `maxJSONDepth` containers), so the envelope scan must reject that same
  /// payload — otherwise a payload passes validation yet throws `depthExceeded`
  /// when re-canonicalized on the next enqueue, breaking the re-emit invariant.
  func testValidateRejectsMaxDepthNestingMatchingCanonicalize() throws {
    let depth = SyncEnvelope.maxJSONDepth  // 32
    var env = wellFormed()
    env.payload = nestedArrayPayload(depth)
    guard case .failure(.payloadJsonTooDeep(let reported, let max)) = env.validate() else {
      return XCTFail("expected payloadJsonTooDeep for \(depth) nested containers")
    }
    XCTAssertEqual(reported, depth)
    XCTAssertEqual(max, SyncEnvelope.maxJSONDepth)
    // canonicalizeJSON rejects the equivalent value — the scan matches it.
    XCTAssertThrowsError(try canonicalizeJSON(nestedArrayValue(depth))) { error in
      XCTAssertEqual(error as? CanonError, .depthExceeded)
    }
  }

  /// One container shallower than the cap is accepted by BOTH the envelope scan
  /// and `canonicalizeJSON` — the accepted set is aligned, not merely the
  /// rejected set.
  func testValidateAcceptsJustBelowMaxDepthMatchingCanonicalize() throws {
    let depth = SyncEnvelope.maxJSONDepth - 1  // 31
    var env = wellFormed()
    env.payload = nestedArrayPayload(depth)
    XCTAssertNoThrow(try env.validate().get())
    XCTAssertNoThrow(try canonicalizeJSON(nestedArrayValue(depth)))
  }
}
