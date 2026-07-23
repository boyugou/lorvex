import Foundation
import Testing

@testable import LorvexCore

/// Counts how many times a body closure runs, on the main actor so the flight's
/// `@MainActor` closures can mutate it without crossing an isolation boundary.
@MainActor private final class RunCounter { var runs = 0 }

/// Ordered event log, used to pin the afterDrain-before-waiter-resume ordering.
@MainActor private final class EventLog { var events: [String] = [] }

/// Parks its `wait()` caller until `release()` is called, signalling entry first
/// so a test can hold one `run` body in flight and then fire coalesced triggers.
/// Mirrors the store coalescing tests' gate.
@MainActor private final class BodyGate {
  private var released = false
  private var entered = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var enteredContinuation: CheckedContinuation<Void, Never>?

  func wait() async {
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    if released { return }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

@MainActor
@Suite("RefreshSingleFlight")
struct RefreshSingleFlightTests {
  /// A lone call (no coalescing) runs the body exactly once and returns its value.
  @Test func loneCallRunsBodyOnceAndReturnsItsResult() async {
    let flight = RefreshSingleFlight<Int>()
    let counter = RunCounter()
    #expect(flight.isRunning == false)

    let result = await flight.run(body: {
      counter.runs += 1
      return 42
    })

    #expect(counter.runs == 1)
    #expect(result == 42)
    #expect(flight.isRunning == false)
    #expect(flight.isPendingRerun == false)
  }

  /// Several `requestRerun()` calls fired during a body pass collapse into exactly
  /// one trailing rerun — the shape of the macOS inbound-apply mid-refresh trigger.
  @Test func requestRerunDuringBodyCausesExactlyOneTrailingRerun() async {
    let flight = RefreshSingleFlight<Int>()
    let counter = RunCounter()

    let result = await flight.run(body: {
      counter.runs += 1
      if counter.runs == 1 {
        flight.requestRerun()
        flight.requestRerun()
        flight.requestRerun()
      }
      return counter.runs
    })

    #expect(counter.runs == 2)  // initial pass + exactly one rerun, not one per request
    #expect(result == 2)
    #expect(flight.isPendingRerun == false)
  }

  /// A caller can retain progress from an earlier pass instead of accepting
  /// only the trailing pass's value (used by the Cloud sync cycle flight).
  @Test func customResultCombinerFoldsEveryPass() async {
    let flight = RefreshSingleFlight<Int>(combineResults: +)
    let counter = RunCounter()

    let result = await flight.run(body: {
      counter.runs += 1
      if counter.runs == 1 { flight.requestRerun() }
      return counter.runs
    })

    #expect(counter.runs == 2)
    #expect(result == 3)
  }

  /// A rerun requested while no loop is running is cleared before the next loop's
  /// first body, so it never causes a spurious extra pass.
  @Test func requestRerunWhileIdleDoesNotCauseSpuriousRerun() async {
    let flight = RefreshSingleFlight<Int>()
    let counter = RunCounter()

    flight.requestRerun()
    #expect(flight.isPendingRerun == true)

    let result = await flight.run(body: {
      counter.runs += 1
      return counter.runs
    })

    #expect(counter.runs == 1)  // the stale request was cleared before the first body
    #expect(result == 1)
    #expect(flight.isPendingRerun == false)
  }

  /// A call arriving while a run is in flight does not start a parallel body; it
  /// registers as a waiter and is resumed with the in-flight run's final result.
  @Test func coalescedCallerGetsTheInFlightRunsFinalResultWithoutRunningAParallelBody() async {
    let flight = RefreshSingleFlight<Int>()
    let gate = BodyGate()
    let counter = RunCounter()

    let leader = Task { () -> Int in
      await flight.run(body: {
        counter.runs += 1
        let pass = counter.runs
        if pass == 1 { await gate.wait() }
        return pass
      })
    }
    await gate.waitUntilEntered()

    // A second trigger lands while the leader is parked mid-body.
    let coalesced = Task { () -> Int in
      await flight.run(body: {
        counter.runs += 1  // must never run — a coalesced caller starts no parallel body
        return counter.runs
      })
    }
    // Wait until the coalesced caller has registered (pending set, still running).
    for _ in 0..<1000 where !flight.isPendingRerun { await Task.yield() }
    #expect(flight.isPendingRerun == true)
    #expect(flight.isRunning == true)

    gate.release()
    let leaderResult = await leader.value
    let coalescedResult = await coalesced.value

    #expect(counter.runs == 2)  // leader body ran twice; the coalesced body never ran
    #expect(leaderResult == 2)
    #expect(coalescedResult == 2)  // coalesced caller received the FINAL result
    #expect(flight.isRunning == false)
    #expect(flight.isPendingRerun == false)
  }

  /// `afterDrain` runs exactly once, after the loop drains and before any waiter
  /// is resumed with the final result.
  @Test func afterDrainRunsOnceAfterLoopAndBeforeWaitersResume() async {
    let flight = RefreshSingleFlight<Int>()
    let gate = BodyGate()
    let counter = RunCounter()
    let log = EventLog()

    let leader = Task { () -> Int in
      await flight.run(
        body: {
          counter.runs += 1
          let pass = counter.runs
          if pass == 1 { await gate.wait() }
          log.events.append("body\(pass)")
          return pass
        },
        afterDrain: { log.events.append("afterDrain") })
    }
    await gate.waitUntilEntered()

    let coalesced = Task { () -> Int in
      let value = await flight.run(body: {
        counter.runs += 1
        return counter.runs
      })
      log.events.append("waiterResumed")
      return value
    }
    for _ in 0..<1000 where !flight.isPendingRerun { await Task.yield() }
    #expect(flight.isPendingRerun == true)

    gate.release()
    _ = await leader.value
    _ = await coalesced.value

    #expect(log.events == ["body1", "body2", "afterDrain", "waiterResumed"])
  }
}
