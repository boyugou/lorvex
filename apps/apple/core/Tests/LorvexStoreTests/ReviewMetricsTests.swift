import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class ReviewMetricsTests: XCTestCase {

  func testLoadTaskEstimateSummaryComputesCoverage() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', "
          + "'2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
      try db.execute(
        sql: """
          INSERT INTO tasks (
              id, title, status, list_id, estimated_minutes,
              completed_at, version, created_at, updated_at
          ) VALUES
              ('t1', 'Covered 1', 'completed', 'l1', 30, '2026-04-02T12:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T12:00:00Z'),
              ('t2', 'Covered 2', 'completed', 'l1', 20, '2026-04-02T13:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T13:00:00Z'),
              ('t3', 'Unestimated', 'completed', 'l1', NULL, '2026-04-02T14:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T14:00:00Z')
          """)

      let summary = try ReviewMetrics.loadTaskEstimateSummary(
        db,
        windowStartUtc: "2026-04-01T00:00:00Z",
        windowEndUtc: "2026-04-03T00:00:00Z")

      XCTAssertEqual(summary.completedTotal, 3)
      XCTAssertEqual(summary.completedWithEstimateCount, 2)
      XCTAssertEqual(summary.estimateCoverageRatio, 2.0 / 3.0)
    }
  }

  // Additional coverage for the count helpers — Rust did not have
  // dedicated unit tests for `overdue_open_count` / `deferred_open_count`
  // / `someday_count`, but they are part of the public surface so we
  // exercise them here against the same in-memory schema.
  func testOverdueOpenCountSomedayDeferredCounts() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', "
          + "'2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
      // Two open with due_date < today; one open due today; one someday;
      // one deferred 5x.
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, due_date, defer_count, version, created_at, updated_at) VALUES
            ('a', 'Past 1', 'open', 'l1', '2026-04-01', 0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'),
            ('b', 'Past 2', 'open', 'l1', '2026-04-02', 0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'),
            ('c', 'Today',  'open', 'l1', '2026-04-05', 0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'),
            ('d', 'Someday','someday', 'l1', NULL,      0, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'),
            ('e', 'Stale',  'open', 'l1', NULL,         5, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')
          """)

      XCTAssertEqual(try ReviewMetrics.overdueOpenCount(db, todayYmd: "2026-04-05"), 2)
      XCTAssertEqual(try ReviewMetrics.somedayCount(db), 1)
      XCTAssertEqual(try ReviewMetrics.deferredOpenCount(db, minCount: 3), 1)
      XCTAssertEqual(try ReviewMetrics.deferredOpenCount(db, minCount: 10), 0)
    }
  }

  func testOverdueOpenCountExcludesArchivedAndNullDue() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', "
          + "'2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, due_date, archived_at, version, created_at, updated_at) VALUES
            ('a', 'Past archived', 'open', 'l1', '2026-04-01', '2026-04-02T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z'),
            ('b', 'No due',        'open', 'l1', NULL,         NULL,                  '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')
          """)
      XCTAssertEqual(try ReviewMetrics.overdueOpenCount(db, todayYmd: "2026-04-05"), 0)
    }
  }

  func testLoadTaskEstimateSummaryEmptyWindow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      let summary = try ReviewMetrics.loadTaskEstimateSummary(
        db,
        windowStartUtc: "2026-04-01T00:00:00Z",
        windowEndUtc: "2026-04-03T00:00:00Z")
      XCTAssertEqual(summary.completedTotal, 0)
      XCTAssertEqual(summary.completedWithEstimateCount, 0)
      XCTAssertNil(summary.estimateCoverageRatio)
    }
  }
}
