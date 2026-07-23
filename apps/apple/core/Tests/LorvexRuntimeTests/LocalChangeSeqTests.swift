import GRDB
import XCTest

@testable import LorvexRuntime

/// Ports `lorvex-runtime/src/local_state/tests.rs` (the bump/read parity
/// cases). The Rust `runtime_fixture_matches_production_schema` test is
/// intentionally NOT ported: the Swift runtime tests run against the canonical
/// `schema/schema.sql` via `RuntimeTestSupport.freshStore`, so the
/// fixture-vs-production drift it guards is structurally impossible here.
final class LocalChangeSeqTests: XCTestCase {
  func testDefaultsToZero() throws {
    let store = try RuntimeTestSupport.freshStore()
    let seq = try store.writer.read { try LocalChangeSeq.read($0) }
    XCTAssertEqual(seq, 0)
  }

  func testBumpMonotonicallyIncrements() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try LocalChangeSeq.bump(db), 1)
      XCTAssertEqual(try LocalChangeSeq.bump(db), 2)
      XCTAssertEqual(try LocalChangeSeq.read(db), 2)
    }
  }

  func testBumpYieldsDistinctValuesPerCall() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      var seen = Set<UInt64>()
      var last: UInt64 = 0
      for _ in 0..<32 {
        let n = try LocalChangeSeq.bump(db)
        XCTAssertTrue(seen.insert(n).inserted, "duplicate seq \(n)")
        XCTAssertGreaterThan(n, last, "seq did not strictly increase")
        last = n
      }
      XCTAssertEqual(seen.count, 32)
      XCTAssertEqual(try LocalChangeSeq.read(db), 32)
    }
  }

  func testReadSurfacesCorruptNegativeValue() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      // Negative values are rejected by `bump` at write time; seed one
      // directly to model on-disk corruption.
      try db.execute(
        sql: "INSERT INTO local_counters (name, value, updated_at) VALUES (?1, -1, ?2)",
        arguments: [LocalChangeSeq.key, 1_700_000_000_000 as Int64])
      XCTAssertThrowsError(try LocalChangeSeq.read(db)) { error in
        XCTAssertEqual(error as? RuntimeError, .corruptLocalChangeSeq("-1"))
      }
    }
  }
}
