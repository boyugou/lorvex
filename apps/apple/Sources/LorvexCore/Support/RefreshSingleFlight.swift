import Foundation

/// Single-flight coalescing for an async refresh body, shared by the macOS and
/// iOS stores. It owns the "run once, coalesce concurrent triggers into one
/// trailing rerun, resume waiters with the final result" sequencing so each
/// store keeps only its own `performRefresh` body.
///
/// While a run is in flight, another `run(body:)` call does NOT start a parallel
/// body: it records a pending trigger and registers as a waiter, and the
/// in-flight run reruns its body once after the current pass. Any number of
/// triggers arriving during a pass collapse into a single rerun, so a write that
/// committed after the run began its reads is still observed rather than stranded
/// until an unrelated later trigger. When the loop finally drains, `afterDrain`
/// runs exactly once, then every registered waiter is resumed with the run's
/// final result — so a coalesced `await run(...)` still means "a body that saw my
/// trigger has finished."
///
/// A reference type (not a value type) on purpose: a store holds it as a stored
/// property AND re-enters it mid-body — the tail of a `body` reads ``isRunning``
/// and calls ``requestRerun()`` while `run` is still on the stack. A struct would
/// make that a simultaneous-access-to-`inout-self` violation; a class lets the
/// re-entrant access just touch the same instance. `@MainActor`, so the flag
/// reads and writes are ordered with no intervening suspension before each guard,
/// which is what makes the coalescing race-free.
@MainActor
public final class RefreshSingleFlight<Result: Sendable> {
  private var running = false
  private var pending = false
  private var waiters: [CheckedContinuation<Result, Never>] = []
  private let combineResults: (Result, Result) -> Result

  /// `combineResults` folds the result of every trailing pass into the value
  /// returned to the leader and all coalesced callers. Refresh callers normally
  /// want the latest pass (the default); state-machine drains can instead retain
  /// progress made by an earlier pass while still running the required trailing
  /// pass.
  public init(
    combineResults: @escaping (Result, Result) -> Result = { _, latest in latest }
  ) {
    self.combineResults = combineResults
  }

  /// True while a `run(...)` loop is executing (including across its body's
  /// suspensions and its `afterDrain`). Read by callers that gate on "a refresh
  /// is in flight."
  public var isRunning: Bool { running }

  /// True when a rerun has been requested for the current loop but not yet
  /// consumed. After a loop drains this is always false. Primarily an
  /// observability hook for tests asserting the loop settled without a dangling
  /// pending rerun.
  public var isPendingRerun: Bool { pending }

  /// Arms a trailing rerun of the in-flight loop from an external trigger that
  /// mutated shared state mid-body and needs the loop to re-read it. Repeated
  /// calls collapse into a single rerun. Arming it while no loop is running is
  /// harmless: the next loop clears the flag before its first body, so a stale
  /// request never causes a spurious extra pass.
  public func requestRerun() { pending = true }

  /// Runs `body` under single-flight coalescing and returns its final result.
  ///
  /// If a loop is already running, this call records a pending rerun, registers a
  /// waiter, and returns that loop's final result once it drains — it never runs
  /// a parallel body. Otherwise this call is the leader: it clears any stale
  /// pending flag, runs `body`, and reruns `body` once for each pass that ended
  /// with a pending trigger set. After the loop drains it runs `afterDrain`
  /// exactly once and then resumes every registered waiter with the final result.
  ///
  /// `afterDrain` runs after ``isRunning`` is already cleared, so a re-entrant
  /// refresh it triggers becomes a fresh leader rather than coalescing into this
  /// (already finished) loop.
  public func run(
    body: () async -> Result,
    afterDrain: () async -> Void = {}
  ) async -> Result {
    if running {
      pending = true
      return await withCheckedContinuation { waiters.append($0) }
    }
    running = true
    pending = false
    var result = await body()
    while pending {
      pending = false
      result = combineResults(result, await body())
    }
    running = false
    let resumeList = waiters
    waiters = []
    await afterDrain()
    for waiter in resumeList { waiter.resume(returning: result) }
    return result
  }
}
