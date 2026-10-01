import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Deferred apply repairs must publish the final canonical state after every
/// envelope and pending-inbox replay in the page has settled.
final class DeferredApplyRepairFinalStateTests: XCTestCase {
  private let timestamp = "2026-08-05T12:00:00.000Z"
  private let v1 = "1760000010000_0001_1111111111111111"
  private let v2 = "1760000010100_0001_2222222222222222"
  private let deviceId = "77777777-7777-4777-8777-777777777799"

  func testLaterHigherPreferenceUpsertSupersedesEarlierEqualCollisionRepair() throws {
    let service = try makeService()
    let key = PreferenceKeys.prefSetupSummary
    XCTAssertEqual(
      try service.applyInbound(
        [try preferenceEnvelope(key: key, value: "base", version: v1)], undecodable: 0
      ).applied,
      1)

    _ = try service.applyInbound(
      [
        try preferenceEnvelope(key: key, value: "collision", version: v1),
        try preferenceEnvelope(key: key, value: "final", version: v2),
      ],
      undecodable: 0)

    let stored = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?1", arguments: [key])
    }
    XCTAssertEqual(stored.flatMap(JSONValue.parse), .string("final"))
  }

  func testLaterHigherPreferenceDeleteSupersedesEarlierEqualCollisionRepair() throws {
    let service = try makeService()
    let key = PreferenceKeys.prefSetupSummary
    XCTAssertEqual(
      try service.applyInbound(
        [try preferenceEnvelope(key: key, value: "base", version: v1)], undecodable: 0
      ).applied,
      1)

    _ = try service.applyInbound(
      [
        try preferenceEnvelope(key: key, value: "collision", version: v1),
        preferenceDeleteEnvelope(key: key, version: v2),
      ],
      undecodable: 0)

    let state = try service.read { db in
      (
        value: try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?1", arguments: [key]),
        tombstone: try Tombstone.getTombstone(
          db, entityType: EntityName.preference, entityId: key)
      )
    }
    XCTAssertNil(state.value)
    XCTAssertEqual(state.tombstone?.version, v2)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations()))
  }

  private func preferenceEnvelope(
    key: String, value: String, version: String
  ) throws -> SyncEnvelope {
    try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .preference, entityId: key, operation: .upsert,
        version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "key": .string(key), "value": .string(value),
            "updated_at": .string(timestamp),
          ])),
        deviceId: deviceId))
  }

  private func preferenceDeleteEnvelope(key: String, version: String) -> SyncEnvelope {
    SyncEnvelope(
      entityType: .preference, entityId: key, operation: .delete,
      version: try! Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"version\":\"\(version)\"}", deviceId: deviceId)
  }
}
