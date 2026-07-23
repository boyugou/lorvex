import Foundation
import XCTest

@testable import LorvexStore

/// A deterministic, seedable PRNG (SplitMix64) so benchmark datasets are
/// byte-identical across runs and machines. `SystemRandomNumberGenerator` is
/// not seedable; the whole point of the harness is comparability, so seeding
/// is mandatory.
struct SeededRNG: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { self.state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform integer in `0..<bound`.
  mutating func int(_ bound: Int) -> Int {
    precondition(bound > 0)
    return Int(next() % UInt64(bound))
  }

  mutating func bool(_ probability: Double) -> Bool {
    Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) < probability
  }

  mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
}

/// Shared helpers for the benchmark target.
enum BenchSupport {
  /// Benchmarks are gated behind `LORVEX_BENCH` so an ordinary `swift test`
  /// pass never seeds large datasets. Call this as the FIRST line of every
  /// benchmark method (not in `setUp`) so the skip fires before any work.
  static func requireBenchEnabled() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["LORVEX_BENCH"] != nil,
      "benchmarks gated behind LORVEX_BENCH; set LORVEX_BENCH=1 to run")
  }

  /// Load the authoritative root `schema/schema.sql`, mirroring
  /// `LorvexStoreTests/TestSupport`. Layout:
  /// `apps/apple/core/Tests/LorvexBenchmarks/<file>.swift` →
  /// `<repo-root>/lorvex/schema/schema.sql` (5 levels up).
  static func loadSchemaSQL(file: StaticString = #filePath) throws -> String {
    var path = (String(describing: file) as NSString).deletingLastPathComponent
    for _ in 0..<5 {
      path = (path as NSString).deletingLastPathComponent
    }
    let schemaPath = (path as NSString).appendingPathComponent("schema/schema.sql")
    return try String(contentsOfFile: schemaPath, encoding: .utf8)
  }

  /// Fresh on-disk store in a unique temp directory. On-disk (not in-memory)
  /// so query plans, WAL, and page-cache behavior match production. Caller is
  /// responsible for cleanup via the returned URL's parent directory.
  static func freshOnDiskStore(file: StaticString = #filePath) throws -> (LorvexStore, URL) {
    let sql = try loadSchemaSQL(file: file)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-bench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbURL = dir.appendingPathComponent("bench.sqlite")
    let store = try LorvexStore.open(at: dbURL, schemaSQL: sql)
    return (store, dir)
  }

  /// Median of a small set of trial durations (seconds), for manual timing.
  static func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    let m = s.count / 2
    return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
  }

  /// Time a closure once, returning milliseconds.
  static func timeMs(_ body: () throws -> Void) rethrows -> Double {
    let start = Date()
    try body()
    return Date().timeIntervalSince(start) * 1000.0
  }
}

/// Collects one measured row per hot path and prints a single markdown table
/// at process teardown so the numbers land together in test output. Shared as
/// a process-global so each test class can append regardless of run order.
final class BenchResults: @unchecked Sendable {
  struct Row {
    let path: String
    let scale: Int
    let ms: Double
    let method: String
    let note: String
  }

  static let shared = BenchResults()
  private let lock = NSLock()
  private var rows: [Row] = []

  func record(path: String, scale: Int, ms: Double, method: String, note: String = "") {
    lock.lock()
    defer { lock.unlock() }
    rows.append(Row(path: path, scale: scale, ms: ms, method: method, note: note))
    // Echo immediately so partial runs still show numbers.
    print(String(format: "[BENCH] %@ @ %d: %.3f ms (%@) %@", path, scale, ms, method, note))
  }

  func printTable() {
    lock.lock()
    defer { lock.unlock() }
    guard !rows.isEmpty else { return }
    // Group by path, columns 1k / 10k.
    var byPath: [String: [Int: Double]] = [:]
    var methodByPath: [String: String] = [:]
    var order: [String] = []
    for r in rows {
      if byPath[r.path] == nil { byPath[r.path] = [:]; order.append(r.path) }
      byPath[r.path]?[r.scale] = r.ms
      methodByPath[r.path] = r.method
    }
    print("\n=== BENCHMARK RESULTS TABLE ===")
    print("| Hot path | 1k (ms) | 10k (ms) | 10k/1k | method |")
    print("|---|---:|---:|---:|---|")
    for p in order {
      let one = byPath[p]?[1_000]
      let ten = byPath[p]?[10_000]
      let ratio: String
      if let a = one, let b = ten, a > 0 { ratio = String(format: "%.1fx", b / a) } else { ratio = "—" }
      let oneStr = one.map { String(format: "%.3f", $0) } ?? "—"
      let tenStr = ten.map { String(format: "%.3f", $0) } ?? "—"
      print("| \(p) | \(oneStr) | \(tenStr) | \(ratio) | \(methodByPath[p] ?? "") |")
    }
    print("=== END BENCHMARK RESULTS TABLE ===\n")
  }
}
