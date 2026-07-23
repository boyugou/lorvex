import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Bench-gated, print-only `EXPLAIN QUERY PLAN` audit at 10k scale: runs the
/// shared ``QueryPlanProbes`` against a large seeded DB and prints a markdown
/// table (query → uses-index? → flagged-if-SCAN-large → plan) for the
/// optimization phase to triage. The CI-safe regression assertion over the same
/// probe set lives in `ExplainQueryPlanCITests`.
final class ExplainQueryPlanBenchmarks: XCTestCase {
  func testExplainQueryPlanAudit() throws {
    try BenchSupport.requireBenchEnabled()
    let (store, dir) = try BenchSupport.freshOnDiskStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try BenchmarkSeeder.seed(store, taskCount: 10_000)

    let rows = try QueryPlanProbes.auditPlans(store)

    print("\n=== EXPLAIN QUERY PLAN AUDIT (10k) ===")
    print("| Query | uses index? | flagged | plan |")
    print("|---|---|---|---|")
    for r in rows {
      let idx = r.usesIndex ? "yes" : "no"
      let flag = r.hasFullTableScan ? "⚠️ SCAN" : ""
      let plan = r.plan.replacingOccurrences(of: "|", with: "/")
      print("| \(r.query) | \(idx) | \(flag) | \(plan) |")
    }
    print("=== END EXPLAIN QUERY PLAN AUDIT ===\n")

    BenchResults.shared.printTable()
  }
}
