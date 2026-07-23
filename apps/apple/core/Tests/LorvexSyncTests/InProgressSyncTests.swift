import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// `in_progress` rides the task aggregate as a plain LWW status field: the
/// inbound apply accepts it, and a cross-device start-vs-complete race converges
/// on the higher-HLC status.
final class InProgressSyncTests: XCTestCase {
  private static let taskId = "00000000-0000-7000-8000-0000000000aa"
  private static let vLow = "1711234567000_0000_dec0000100000001"
  private static let vHigh = "1711234567000_0001_dec0000100000001"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func payload(_ status: String) -> String {
    var obj: [String: JSONValue] = [
      "title": .string("started task"),
      "status": .string(status),
      "list_id": .string(inboxListId),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    if status == StatusName.completed {
      obj["completed_at"] = .string("2026-04-01T00:00:00.000Z")
    }
    return (try? SyncCanonicalize.canonicalizeJSON(.object(obj))) ?? "{}"
  }

  private func applyUpsert(_ db: Database, _ status: String, version: String) throws {
    try ApplyTask.applyTaskUpsert(
      db, entityId: Self.taskId, payload: payload(status), version: version,
      tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
  }

  private func status(_ db: Database) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [Self.taskId])
  }

  /// The inbound apply trust boundary accepts an `in_progress` status (the
  /// whitelist was widened alongside the CHECK constraint).
  func testApplyAcceptsInProgressStatus() throws {
    try withDB { db in
      let row = try ApplyTask.buildTaskRow(
        db, taskId: Self.taskId, payload: self.payload("in_progress"), version: Self.vLow)
      XCTAssertEqual(row.status, "in_progress")
    }
  }

  /// An `in_progress` upsert survives outbound → inbound: the status persists on
  /// the peer.
  func testInProgressStatusRoundTrips() throws {
    try withDB { db in
      try self.applyUpsert(db, "in_progress", version: Self.vLow)
      XCTAssertEqual(try self.status(db), "in_progress")
    }
  }

  /// Cross-device start-vs-complete race: the higher-HLC envelope wins and a
  /// stale lower-HLC `in_progress` envelope cannot resurrect the marker.
  func testStartVsCompleteConvergesByHlc() throws {
    try withDB { db in
      // Device A starts the task (lower HLC).
      try self.applyUpsert(db, "in_progress", version: Self.vLow)
      XCTAssertEqual(try self.status(db), "in_progress")
      // Device B completes it concurrently with a higher HLC — it wins.
      try self.applyUpsert(db, "completed", version: Self.vHigh)
      XCTAssertEqual(try self.status(db), "completed")
      // A late replay of the stale start envelope must not regress the status.
      try self.applyUpsert(db, "in_progress", version: Self.vLow)
      XCTAssertEqual(try self.status(db), "completed")
    }
  }
}
