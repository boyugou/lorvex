import Foundation
import Synchronization
import Testing

@testable import LorvexCore

/// Smoke coverage for the cross-process change signal. Actual cross-process
/// Darwin delivery is integration-level (run-loop dependent); here we exercise
/// the public API and the broadcast gate without crashing.
@Suite(.serialized)
struct DatabaseChangeSignalTests {
  @Test
  func applicationProcessConfigurationEnablesLocalWriteDelivery() {
    let previousLocalDelivery = DatabaseChangeSignal.postsInProcessOnWrite
    DatabaseChangeSignal.postsInProcessOnWrite = false
    defer { DatabaseChangeSignal.postsInProcessOnWrite = previousLocalDelivery }

    DatabaseChangeSignal.configureApplicationProcess()

    #expect(DatabaseChangeSignal.postsInProcessOnWrite)
  }

  @Test
  func broadcastIsGatedAndDoesNotCrash() {
    DatabaseChangeSignal.startObserving()

    DatabaseChangeSignal.broadcastsOnWrite = false
    DatabaseChangeSignal.broadcastIfEnabled()  // disabled → no-op

    DatabaseChangeSignal.broadcastsOnWrite = true
    DatabaseChangeSignal.broadcastIfEnabled()  // enabled → posts cross-process

    DatabaseChangeSignal.broadcastsOnWrite = false
  }

  @Test
  func inProcessDeliveryCoalescesAWriteBurst() {
    let coalescer = InProcessDatabaseChangeCoalescer()
    let deliveries = Mutex(0)
    let scheduled = Mutex<[(@Sendable () -> Void)]>([])
    let schedule: (@escaping @Sendable () -> Void) -> Void = { post in
      scheduled.withLock { $0.append(post) }
    }

    // One UI operation may use several committed core transactions. The local
    // relay must invalidate peer stores once for the burst, not force one full
    // refresh per transaction.
    for _ in 0..<20 {
      coalescer.enqueue(
        schedule: schedule,
        deliver: { deliveries.withLock { $0 += 1 } })
    }
    #expect(scheduled.withLock { $0.count } == 1)
    let first = scheduled.withLock { $0.removeFirst() }
    first()
    #expect(deliveries.withLock { $0 } == 1)

    // Once that delivery starts, a new write burst must schedule exactly one
    // trailing invalidation rather than being swallowed by the completed burst.
    for _ in 0..<20 {
      coalescer.enqueue(
        schedule: schedule,
        deliver: { deliveries.withLock { $0 += 1 } })
    }
    #expect(scheduled.withLock { $0.count } == 1)
    let trailing = scheduled.withLock { $0.removeFirst() }
    trailing()
    #expect(deliveries.withLock { $0 } == 2)
  }

  @Test
  func startObservingRegistersAtMostOncePerProcess() {
    DatabaseChangeSignal.resetObservingForTesting()
    defer { DatabaseChangeSignal.resetObservingForTesting() }

    var registrations = 0
    for _ in 0..<3 {
      DatabaseChangeSignal.registerObserverIfNeeded { registrations += 1 }
    }

    #expect(registrations == 1)
  }
}
