import Foundation
import XCTest

@testable import LorvexStore

/// CI-safe regression guard over the shared ``QueryPlanProbes`` hot reads.
///
/// Unlike `ExplainQueryPlanBenchmarks` (bench-gated, 10k, print-only), this runs
/// under an ordinary `swift test`: it seeds a small fixture, `EXPLAIN QUERY
/// PLAN`s each hot read, and FAILS if any does a full `SCAN` of a large table
/// (`tasks` / `calendar_events` / `task_dependencies`). SQLite plans the same
/// index choices on a small DB as on a large one as long as no `ANALYZE` stats
/// exist (the planner assumes ~1M rows per table), so a small seed catches an
/// index/predicate regression without the 10k bench seed.
///
/// If a probe legitimately must scan a large table, add it to
/// ``acceptedLargeScans`` with a justification — a deliberate, reviewed
/// exception rather than a silent regression.
final class ExplainQueryPlanCITests: XCTestCase {
  /// Probe names whose plan is allowed to do a full table scan — a reviewed,
  /// justified exception rather than a silent regression.
  ///
  /// - `search-trigram (CJK)`: the CJK substring-search fallback filters
  ///   `tasks` by `rowid IN (SELECT rowid FROM tasks_fts_trigram WHERE …)`;
  ///   SQLite plans this as a scan of `tasks` intersected with the
  ///   trigram-matched rowids. This is an inherent property of the trigram
  ///   fallback (FTS5 has no usable b-tree index for the outer COUNT/SELECT),
  ///   not a regression in the canonical index-bound reads this guard protects.
  /// - `dependency-graph`: loads the whole dependency edge set
  ///   (`SELECT … FROM task_dependencies td JOIN tasks …`) with no row-limiting
  ///   predicate — rendering the graph needs every edge — so a covering-index
  ///   scan of `task_dependencies` is the optimal plan, not a regression.
  private let acceptedLargeScans: Set<String> = ["search-trigram (CJK)", "dependency-graph"]

  /// The actionable day buckets must engage the
  /// `idx_tasks_action_date_actionable` partial expression index once planner
  /// statistics exist. That index's partial WHERE is byte-aligned with the
  /// callers' exact `status IN ('open', 'in_progress') AND archived_at IS NULL`
  /// guards; drift in either spelling silently demotes every day-bucket read to
  /// the broader status index plus a temp-B-tree sort over the whole open set.
  /// This guard turns that silent demotion into a test failure. `ANALYZE` runs
  /// first because index selection (unlike plan legality) is statistics-driven.
  func testActionDateBucketsEngageTheActionableExpressionIndex() throws {
    let (store, dir) = try BenchSupport.freshOnDiskStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try BenchmarkSeeder.seed(store, taskCount: 400)
    try store.writer.write { db in try db.execute(sql: "ANALYZE") }

    let rows = try QueryPlanProbes.auditPlans(store)
    for name in ["load-today", "upcoming (overview)"] {
      let plans = rows.filter { $0.query == name }
      XCTAssertFalse(plans.isEmpty, "probe \(name) captured no plans")
      XCTAssertTrue(
        plans.contains { $0.plan.contains("idx_tasks_action_date_actionable") },
        "probe \(name) no longer engages idx_tasks_action_date_actionable:\n"
          + plans.map { "  \($0.plan)\n    SQL: \($0.sql.prefix(160))" }
          .joined(separator: "\n"))
    }
  }

  func testHotReadsStayIndexBound() throws {
    let (store, dir) = try BenchSupport.freshOnDiskStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Small but non-empty: enough to populate every probe's tables (tag "work0",
    // a calendar window, dependency edges). Plan shape is size-independent
    // without ANALYZE, so this is a fast, faithful proxy for the 10k audit.
    try BenchmarkSeeder.seed(store, taskCount: 400)

    let rows = try QueryPlanProbes.auditPlans(store)
    XCTAssertFalse(rows.isEmpty, "audit captured no query plans — probe wiring is broken")

    let regressions = rows.filter {
      $0.hasFullTableScan && !acceptedLargeScans.contains($0.query)
    }
    let report = regressions
      .map { "  - \($0.query): \($0.plan)\n      SQL: \($0.sql.prefix(120))" }
      .joined(separator: "\n")
    XCTAssertTrue(
      regressions.isEmpty,
      "Hot read(s) regressed to a full SCAN of a large table "
        + "(tasks/calendar_events/task_dependencies). Add an index or fix the predicate; "
        + "if the scan is genuinely intended, allow-list the probe in acceptedLargeScans "
        + "with a justification.\n\(report)")
  }
}
