import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Probe: how long a Mac task completion takes through AppStore, its whole
// awaited tail included, with N tasks in the store (measured on 2026-10-12: about
// 40 ms at 100 tasks, 140 ms at 1000, 430 ms at 3000). PERF_N = task count;
// does nothing without it. Prints one `PERF n=… refresh=… complete avg=…` line.
@MainActor
@Suite("Mutation latency probe")
struct ZZMutationLatencyProbeTests {
  @Test("complete latency")
  func completeLatency() async throws {
    guard let n = ProcessInfo.processInfo.environment["PERF_N"].flatMap(Int.init) else { return }
    let core = try makeInMemoryCore()
    let today = LorvexDateFormatters.ymd.string(from: Date())
    let due = try #require(LorvexDateFormatters.ymdUTC.date(from: today))
    var ids = [String]()
    for i in 0..<n {
      let t = try await core.createTask(
        TaskCreateDraft(title: "Task \(i)", priority: .p2, plannedDate: i % 3 == 0 ? due : nil))
      ids.append(t.id)
    }
    let store = AppStore(core: core)
    let r0 = Date()
    await store.refresh()
    let refreshMs = Date().timeIntervalSince(r0) * 1000
    var samples = [Double]()
    for id in ids.prefix(12) {
      let s = Date()
      await store.completeTask(id: id)
      samples.append(Date().timeIntervalSince(s) * 1000)
    }
    let avg = samples.reduce(0, +) / Double(samples.count)
    print("PERF n=\(n) refresh=\(Int(refreshMs))ms complete avg=\(Int(avg))ms max=\(Int(samples.max() ?? 0))ms first=\(Int(samples[0]))ms")
  }
}
