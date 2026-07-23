import Foundation
import GRDB
import LorvexDomain

@testable import LorvexStore
@testable import LorvexWorkflow

/// Shared hot-read query set + `EXPLAIN QUERY PLAN` capture, used by both the
/// bench-gated 10k audit (`ExplainQueryPlanBenchmarks`, print-only) and the
/// CI-safe regression assertion (`ExplainQueryPlanCITests`). Keeping the probe
/// list in one place means the two can never drift apart.
enum QueryPlanProbes {
  /// A hot read to plan-check: a name and the closure that runs the real query
  /// (so the emitted SQL is whatever production actually issues).
  struct Probe {
    let name: String
    let run: (Database) throws -> Void
  }

  /// One captured-and-explained statement from a probe.
  struct PlanRow {
    let query: String
    let sql: String
    let plan: String
    let usesIndex: Bool
    /// `true` when any plan step is a full `SCAN` of a real (base) table —
    /// `SEARCH … USING INDEX` is fine. FTS5/trigram `SCAN … VIRTUAL TABLE`
    /// steps are the search index itself, not a base-table scan, so they don't
    /// count.
    let hasFullTableScan: Bool
  }

  static let ymd = IsoDate.YMD(year: 2026, month: 5, day: 27)

  /// The canonical hot reads — the queries that must stay index-bound as the
  /// schema and indexes evolve. Computed (not stored) so the non-`Sendable`
  /// query closures don't form shared mutable global state under Swift 6.
  static var probes: [Probe] {
    [
    Probe(name: "load-today") { db in
      _ = try TaskRepo.Read.getTodayTasks(db, predicate: .init(date: ymd), page: .default)
    },
    Probe(name: "upcoming (overview)") { db in
      _ = try TaskRepo.Read.getUpcomingTasks(
        db, predicate: .init(fromDate: ymd, days: 7), page: .default)
    },
    Probe(name: "open-by-priority (overview)") { db in
      _ = try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-07-01", limit: 10)
    },
    Probe(name: "list-tasks-filtered") { db in
      var q = TaskRepo.ListTasksQuery()
      q.status = .open
      q.tags = ["work0"]
      q.text = "report"
      _ = try TaskRepo.Read.listTasks(db, query: q)
    },
    Probe(name: "search-fts") { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "report"), page: .default)
    },
    Probe(name: "search-trigram (CJK)") { db in
      _ = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: SearchPredicate(query: "报告会"), page: .default)
    },
    Probe(name: "calendar-timeline-range") { db in
      _ = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-05-20", to: "2026-06-03", accessMode: .fullDetails,
        anchorTimezone: "UTC")
    },
    Probe(name: "dependency-graph") { db in
      _ = try TaskRepo.DependencyGraph.getDependencyGraph(
        db, params: .init(limitNodes: 5_000, limitEdges: 10_000))
    },
    ]
  }

  /// FTS5 emits internal shadow-table statements that aren't independently
  /// EXPLAIN-able; skip them rather than fail.
  private static func isFtsShadow(_ sql: String) -> Bool {
    for marker in ["_fts_idx", "_fts_data", "_fts_docsize", "_trigram_idx", "_trigram_data",
      "_trigram_docsize"]
    {
      if sql.contains(marker) { return true }
    }
    return false
  }

  /// Run every probe against `store`, capturing the SELECTs each emits and
  /// `EXPLAIN QUERY PLAN`-ing them. Pure measurement — no seeding, no gating.
  static func auditPlans(_ store: LorvexStore) throws -> [PlanRow] {
    var rows: [PlanRow] = []
    for probe in probes {
      var captured: [String] = []
      try store.writer.read { db in
        db.trace(options: .statement) { event in
          if case let .statement(stmt) = event {
            let sql = stmt.expandedSQL
            let upper = sql.uppercased()
            if upper.contains("SELECT") && !upper.hasPrefix("PRAGMA") {
              captured.append(sql)
            }
          }
        }
        try probe.run(db)
        db.trace(options: []) { _ in }
      }

      try store.writer.read { db in
        for sql in captured where !isFtsShadow(sql) {
          let planRows: [Row]
          do {
            planRows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql)
          } catch {
            continue
          }
          let steps = planRows.compactMap { $0["detail"] as String? }
          let detail = steps.joined(separator: " | ")
          let usesIndex =
            detail.contains("USING INDEX") || detail.contains("USING COVERING INDEX")
          // A real full table scan: a `SCAN` step against a base table. Exclude
          // virtual tables (FTS5/trigram MATCH reports `SCAN … VIRTUAL TABLE`,
          // the search index doing its job) and materialized subqueries /
          // co-routines (`SCAN (subquery-N)` — a small intermediate result, not a
          // base table; the subquery's own table access is planned and flagged
          // separately if it scans).
          let fullScan = steps.contains {
            $0.contains("SCAN ")
              && !$0.contains("VIRTUAL TABLE")
              && !$0.contains("SCAN (")
          }
          rows.append(
            PlanRow(
              query: probe.name, sql: sql, plan: detail, usesIndex: usesIndex,
              hasFullTableScan: fullScan))
        }
      }
    }
    return rows
  }
}
