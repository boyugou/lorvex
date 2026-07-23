import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync
@testable import LorvexWorkflow

/// Benchmarks for the write hot paths (task create / update / complete, each
/// including the workflow orchestration + enqueue), and the sync
/// `applyEnvelope` batch (1k inbound task-upsert envelopes).
///
/// These use a manual median-of-3 timer rather than `measure {}` because a
/// write benchmark's setup (seed 10k rows) must not be paid per-iteration, and
/// because the operation count per trial is fixed and meaningful.
final class WriteSyncBenchmarks: XCTestCase {

  /// A monotonic, deterministic HLC source — no wall clock, fully reproducible.
  /// The physical-ms field starts high so generated versions always exceed the
  /// versions stamped on freshly created targets (so update/complete don't trip
  /// the LWW stale-version gate).
  private final class SeqHlcHandle: HlcStateHandle, @unchecked Sendable {
    private var counter: UInt64 = 1_000_000
    func generate() -> Hlc {
      defer { counter += 1 }
      return try! Hlc(physicalMs: counter, counter: 0, deviceSuffix: "abcdef0123456789")
    }
  }
  /// One shared handle per test instance so HLC versions advance monotonically
  /// across the setup-create phase and every timed update/complete trial.
  private let sharedHlc = SeqHlcHandle()
  private func session() -> HlcSession { HlcSession(handle: sharedHlc) }

  /// Deterministic UUIDv7 from a counter (canonical form the sync appliers and
  /// FK preflight accept).
  private func uuid(_ n: Int) -> String {
    var rng = SeededRNG(seed: UInt64(0xABCD_0000) ^ UInt64(n))
    return EntityID.newEntityIDString(nowMilliseconds: UInt64(1_716_768_000_000 + n)) {
      (0..<10).map { _ in UInt8(rng.int(256)) }
    }
  }

  private func seeded(_ scale: Int) throws -> (LorvexStore, URL) {
    let (store, dir) = try BenchSupport.freshOnDiskStore()
    try BenchmarkSeeder.seed(store, taskCount: scale)
    return (store, dir)
  }

  // MARK: - task create (N inserts through TaskCreate.createTask)

  private func benchCreate(_ scale: Int) throws {
    let (store, dir) = try seeded(scale)
    defer { try? FileManager.default.removeItem(at: dir) }
    let opCount = 200
    var trials: [Double] = []
    for t in 0..<3 {
      let hlc = session()
      let ms = try BenchSupport.timeMs {
        try store.writer.write { db in
          for i in 0..<opCount {
            let input = CreateTaskInput(
              task: TaskCreateInput(title: "bench create \(t)-\(i)"),
              includeAdvice: false)
            _ = try TaskCreate.createTask(db, hlc: hlc, input: input)
          }
        }
      }
      trials.append(ms / Double(opCount))  // per-op ms
    }
    BenchResults.shared.record(
      path: "task-create", scale: scale, ms: BenchSupport.median(trials),
      method: "median/3, per-op")
  }
  func testTaskCreate1k() throws { try BenchSupport.requireBenchEnabled(); try benchCreate(1_000) }
  func testTaskCreate10k() throws { try BenchSupport.requireBenchEnabled(); try benchCreate(10_000) }

  /// Create `n` fresh open tasks with canonical UUIDv7 ids (the workflow
  /// update/complete paths validate id shape, which the seeder's `task-NNNN`
  /// ids would fail). Returns the ids. Not timed — pure setup.
  private func createUpdateTargets(_ store: LorvexStore, _ n: Int) throws -> [String] {
    let hlc = session()
    var ids: [String] = []
    ids.reserveCapacity(n)
    try store.writer.write { db in
      for i in 0..<n {
        let id = String(format: "01966a3f-7c8b-7d4e-8f3a-%012x", i)
        ids.append(id)
        let input = CreateTaskInput(
          id: id, task: TaskCreateInput(title: "target \(i)"), includeAdvice: false)
        _ = try TaskCreate.createTask(db, hlc: hlc, input: input)
      }
    }
    return ids
  }

  // MARK: - task update (title edit; each call is its own transaction)

  private func benchUpdate(_ scale: Int) throws {
    let (store, dir) = try seeded(scale)
    defer { try? FileManager.default.removeItem(at: dir) }
    let opCount = 200
    let ids = try createUpdateTargets(store, opCount)
    var trials: [Double] = []
    for t in 0..<3 {
      let hlc = session()
      let ms = try BenchSupport.timeMs {
        for (i, id) in ids.enumerated() {
          let input = TaskUpdateInput(id: id, title: .set("updated \(t)-\(i)"))
          _ = try TaskUpdate.updateTask(
            store.writer, hlc: hlc, input: input)
        }
      }
      trials.append(ms / Double(opCount))
    }
    BenchResults.shared.record(
      path: "task-update", scale: scale, ms: BenchSupport.median(trials),
      method: "median/3, per-op")
  }
  func testTaskUpdate1k() throws { try BenchSupport.requireBenchEnabled(); try benchUpdate(1_000) }
  func testTaskUpdate10k() throws { try BenchSupport.requireBenchEnabled(); try benchUpdate(10_000) }

  // MARK: - task complete (status transition + side effects)

  private func benchComplete(_ scale: Int) throws {
    let (store, dir) = try seeded(scale)
    defer { try? FileManager.default.removeItem(at: dir) }
    let opCount = 200
    let ids = try createUpdateTargets(store, opCount)
    let hlc = session()
    // Each id is completed exactly once; a single timed pass.
    let ms = try BenchSupport.timeMs {
      for id in ids {
        let input = TaskUpdateInput(id: id, status: .set("completed"))
        _ = try TaskUpdate.updateTask(
          store.writer, hlc: hlc, input: input)
      }
    }
    BenchResults.shared.record(
      path: "task-complete", scale: scale, ms: ms / Double(opCount),
      method: "single pass, per-op")
  }
  func testTaskComplete1k() throws { try BenchSupport.requireBenchEnabled(); try benchComplete(1_000) }
  func testTaskComplete10k() throws { try BenchSupport.requireBenchEnabled(); try benchComplete(10_000) }

  // MARK: - sync applyEnvelope batch (1k inbound task-upsert envelopes)

  private func benchApply(_ scale: Int) throws {
    let (store, dir) = try seeded(scale)
    defer { try? FileManager.default.removeItem(at: dir) }
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    let batch = 1_000
    var trials: [Double] = []
    for t in 0..<3 {
      // Pre-build envelopes so envelope construction isn't timed.
      let envelopes: [SyncEnvelope] = (0..<batch).map { i in
        let id = uuid(t * batch + i)
        let payload =
          (try? SyncCanonicalize.canonicalizeJSON(
            .object([
              "title": .string("inbound \(t)-\(i)"),
              "status": .string("open"),
              "list_id": .string(inboxListId),
              "created_at": .string(BenchmarkSeeder.todayStartUtc),
              "updated_at": .string(BenchmarkSeeder.todayStartUtc),
            ]))) ?? "{}"
        return SyncEnvelope(
          entityType: .task, entityId: id, operation: .upsert,
          version: try! Hlc(
            physicalMs: UInt64(1_716_768_000_000 + t * batch + i), counter: 0,
            deviceSuffix: "fedcba9876543210"),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
          deviceId: "remote-device")
      }
      let ms = try BenchSupport.timeMs {
        try store.writer.write { db in
          for env in envelopes {
            _ = try Apply.applyEnvelope(db, registry: registry, envelope: env)
          }
        }
      }
      trials.append(ms)
    }
    BenchResults.shared.record(
      path: "sync-apply-1k-batch", scale: scale, ms: BenchSupport.median(trials),
      method: "median/3, 1k envelopes")
  }
  func testApplyEnvelope1k() throws { try BenchSupport.requireBenchEnabled(); try benchApply(1_000) }
  func testApplyEnvelope10k() throws { try BenchSupport.requireBenchEnabled(); try benchApply(10_000) }
}
