import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Benchmarks for the read hot paths: overview snapshot, today bucket,
/// filtered list (dynamic-WHERE), search (FTS + trigram/LIKE), calendar range,
/// and the dependency graph on a dense graph. Each runs at 1k and 10k.
///
/// Reads use XCTest `measure {}` (≈10 iterations, low setup cost since the
/// store is seeded once per method). The measured value is echoed via
/// `BenchResults`; XCTest's own average is also reported by the runner.
final class ReadBenchmarks: XCTestCase {
  private let ymd = IsoDate.YMD(year: 2026, month: 5, day: 27)

  /// Seed once, run `body` under a manual median-of-5 timer, record the row,
  /// then clean up the on-disk store.
  private func run(
    _ path: String, scale: Int, file: StaticString = #filePath, _ body: (Database) throws -> Void
  ) throws {
    let (store, dir) = try BenchSupport.freshOnDiskStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try BenchmarkSeeder.seed(store, taskCount: scale)
    var trials: [Double] = []
    for _ in 0..<5 {
      let ms = try BenchSupport.timeMs { try store.writer.read { db in try body(db) } }
      trials.append(ms)
    }
    BenchResults.shared.record(
      path: path, scale: scale, ms: BenchSupport.median(trials), method: "median/5")
  }

  // MARK: - overview snapshot

  func testOverviewSnapshot1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("overview-snapshot", scale: 1_000) { db in
      _ = try Overview.loadOverviewSnapshot(db, limits: .app())
    }
  }
  func testOverviewSnapshot10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("overview-snapshot", scale: 10_000) { db in
      _ = try Overview.loadOverviewSnapshot(db, limits: .app())
    }
  }

  // MARK: - today bucket

  func testLoadToday1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("load-today", scale: 1_000) { db in
      _ = try TaskRepo.Read.getTodayTasks(db, predicate: .init(date: ymd), page: .default)
    }
  }
  func testLoadToday10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("load-today", scale: 10_000) { db in
      _ = try TaskRepo.Read.getTodayTasks(db, predicate: .init(date: ymd), page: .default)
    }
  }

  // MARK: - filtered list (dynamic-WHERE: status + tag + text)

  private func filteredQuery() -> TaskRepo.ListTasksQuery {
    var q = TaskRepo.ListTasksQuery()
    q.status = .open
    q.tags = ["work0"]
    q.text = "report"
    q.limit = 50
    return q
  }
  func testListTasksFiltered1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("list-tasks-filtered", scale: 1_000) { db in
      _ = try TaskRepo.Read.listTasks(db, query: self.filteredQuery())
    }
  }
  func testListTasksFiltered10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("list-tasks-filtered", scale: 10_000) { db in
      _ = try TaskRepo.Read.listTasks(db, query: self.filteredQuery())
    }
  }

  // MARK: - search (FTS path, ASCII query)

  func testSearchFts1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("search-fts", scale: 1_000) { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "report"), page: .default)
    }
  }
  func testSearchFts10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("search-fts", scale: 10_000) { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "report"), page: .default)
    }
  }

  // MARK: - search (trigram path, CJK query forces trigram/LIKE)

  func testSearchTrigram1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("search-trigram", scale: 1_000) { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "报告会"), page: .default)
    }
  }
  func testSearchTrigram10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("search-trigram", scale: 10_000) { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "报告会"), page: .default)
    }
  }

  // MARK: - calendar timeline range query

  func testCalendarTimeline1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("calendar-timeline-range", scale: 1_000) { db in
      _ = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-05-20", to: "2026-06-03", accessMode: .fullDetails, anchorTimezone: "UTC")
    }
  }
  func testCalendarTimeline10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("calendar-timeline-range", scale: 10_000) { db in
      _ = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-05-20", to: "2026-06-03", accessMode: .fullDetails, anchorTimezone: "UTC")
    }
  }

  // MARK: - dependency graph on a dense graph

  func testDependencyGraph1k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("dependency-graph", scale: 1_000) { db in
      _ = try TaskRepo.DependencyGraph.getDependencyGraph(
        db, params: .init(limitNodes: 5_000, limitEdges: 10_000))
    }
  }
  func testDependencyGraph10k() throws {
    try BenchSupport.requireBenchEnabled()
    try run("dependency-graph", scale: 10_000) { db in
      _ = try TaskRepo.DependencyGraph.getDependencyGraph(
        db, params: .init(limitNodes: 5_000, limitEdges: 10_000))
    }
  }
}
