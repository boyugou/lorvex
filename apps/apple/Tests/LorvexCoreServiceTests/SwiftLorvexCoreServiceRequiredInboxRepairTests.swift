import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// End-to-end coverage for the canonical-inbox convergence repair. A crafted
/// peer delete must not merely be ignored locally: the service must replace the
/// shared record with a fresh dominating upsert before acknowledging inbound
/// progress, otherwise a later authoritative snapshot would remain poisoned.
final class SwiftLorvexCoreServiceRequiredInboxRepairTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func inboxDelete(version: String) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object(["version": .string(version)]))
    return SyncEnvelope(
      entityType: .list, entityId: "inbox", operation: .delete,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "crafted-peer")
  }

  func testCraftedPeerDeleteEnqueuesDominatingInboxUpsertAtomically() throws {
    let service = try makeService()
    let remoteDelete = try inboxDelete(
      version: "9000000000000_0000_aaaaaaaaaaaaaaaa")

    let report = try service.applyInbound([remoteDelete], undecodable: 0)

    XCTAssertEqual(report.skipped, 1)
    XCTAssertEqual(report.applied + report.deferred + report.remapped, 0)
    let repairs = try service.pendingOutbound().map(\.envelope).filter {
      $0.entityType == .list && $0.entityId == "inbox"
    }
    XCTAssertEqual(repairs.count, 1)
    let repair = try XCTUnwrap(repairs.first)
    XCTAssertEqual(repair.operation, .upsert)
    XCTAssertGreaterThan(repair.version, remoteDelete.version)
    guard let parsedPayload = JSONValue.parse(repair.payload),
      case .object(let payload) = parsedPayload
    else {
      return XCTFail("inbox repair payload must be a JSON object")
    }
    XCTAssertEqual(payload["id"], .string("inbox"))
    XCTAssertEqual(payload["version"], .string(repair.version.description))

    let state = try service.read { db in
      let liveVersion = try String.fetchOne(
        db, sql: "SELECT version FROM lists WHERE id = 'inbox'")
      let tombstones = try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'list' AND entity_id = 'inbox'")
      let pending = try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_type = 'list' AND envelope_entity_id = 'inbox'")
      return (liveVersion, tombstones, pending)
    }
    XCTAssertEqual(state.0, repair.version.description)
    XCTAssertEqual(state.1, 0)
    XCTAssertEqual(state.2, 0)
  }
}
