import Foundation
import Testing

@testable import LorvexCore

/// The EventKit change observers hand each notification to a coalescer. These
/// drive it directly, with a gate in place of timing.
@Suite("A burst of signals runs the work once, plus once for what arrived meanwhile")
struct BurstCoalescerTests {
  /// Counts runs and holds each one until released.
  private actor GatedWork {
    private(set) var started = 0
    private(set) var finished = 0
    private var releases = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
      started += 1
      if releases > 0 {
        releases -= 1
      } else {
        await withCheckedContinuation { waiters.append($0) }
      }
      finished += 1
    }

    /// Lets one run through: the one waiting now, or the next to arrive.
    func release() {
      if waiters.isEmpty {
        releases += 1
      } else {
        waiters.removeFirst().resume()
      }
    }
  }

  private func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<2_000 {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
  }

  @Test
  func aBurstDuringARunAddsOneRun() async {
    let coalescer = BurstCoalescer()
    let work = GatedWork()

    await coalescer.signal { await work.run() }
    #expect(await waitUntil { await work.started == 1 })
    // Twenty more while the first run is held.
    for _ in 0..<20 { await coalescer.signal { await work.run() } }
    #expect(await work.started == 1)

    await work.release()
    #expect(await waitUntil { await work.started == 2 })
    await work.release()
    #expect(await waitUntil { await work.finished == 2 })

    // Nothing was left pending: a third run never starts on its own.
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await work.started == 2)
  }

  @Test
  func aSignalAfterTheWorkSettledRunsItAgain() async {
    let coalescer = BurstCoalescer()
    let work = GatedWork()

    await work.release()
    await coalescer.signal { await work.run() }
    #expect(await waitUntil { await work.finished == 1 })

    await work.release()
    await coalescer.signal { await work.run() }
    #expect(await waitUntil { await work.finished == 2 })
  }
}
