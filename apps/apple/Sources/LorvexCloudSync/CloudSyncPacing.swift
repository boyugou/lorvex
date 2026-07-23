import Foundation

/// Failure-aware pacing for the invisible CloudKit sync cycle.
///
/// The cycle is best-effort and fires on user-visible triggers (refresh,
/// mutation, push notification, app activation) plus one app-owned scheduled
/// wake when durable or failed work remains. Without pacing a persistent failure
/// would retry at full trigger frequency, burning the CloudKit rate limiter and
/// battery. This type holds the small amount of failure state and exposes the
/// gate decision (`shouldRun`), wake calculation, and recording transitions
/// (`recordSuccess` / `recordFailure`) that the main-app store drives.
///
/// The decision is pure: `now` is always supplied by the caller, never read
/// from `Date()` inside, so it can be unit-tested deterministically. The
/// Main-app stores are `@MainActor`, so a plain mutable struct stored there is
/// the state home.
///
/// Backoff and the circuit breaker use a `Retryable` schedule of 30s doubling
/// per failure with the exponent capped at 5 (30s … 960s), under a 30-minute
/// `maxDelay` hard ceiling, with ±10% jitter, and a circuit breaker that opens
/// after 20 consecutive failures. The breaker stays open until an explicit
/// reset (`reset()`, wired to account change / app activation) or a successful
/// cycle.
public struct CloudSyncPacing: Equatable {
  /// Consecutive cycle failures since the last success or reset. A successful
  /// cycle returns this to zero; the breaker opens once it reaches
  /// `circuitBreakerThreshold`.
  public private(set) var consecutiveFailures = 0

  /// Wall-clock time of the most recent gated attempt (a cycle that the gate
  /// allowed to run), or nil before the first attempt. The backoff window is
  /// measured from this instant.
  public private(set) var lastAttemptAt: Date?

  /// A SERVER-mandated "do not retry before" instant, set from a CloudKit
  /// `retryAfterSeconds` on a `.requestRateLimited` / `.serviceUnavailable`
  /// response (see ``CloudSyncTransientClassifier/serverRetryAfter(_:)``), or nil
  /// when no server throttle is in effect.
  ///
  /// This is the server's own rate limit, distinct from the generic local backoff
  /// earned by consecutive failures. `reset()` (wired to push / app activation)
  /// deliberately clears ONLY the local backoff and leaves this intact, so a
  /// user-driven trigger cannot stampede past an active server throttle and
  /// deepen the rate limit. Held in memory only: the pacing lives on the store
  /// for the process lifetime, and a fresh process starts unthrottled and
  /// re-learns the server's limit from its next response.
  public private(set) var serverThrottleUntil: Date?

  /// First-failure backoff floor. The schedule starts here and doubles.
  public static let baseDelay: TimeInterval = 30

  /// Backoff ceiling. The doubling schedule saturates here.
  public static let maxDelay: TimeInterval = 30 * 60

  /// Consecutive-failure count at which the breaker opens and the gate stops
  /// allowing ordinary triggers through until a reset or success.
  public static let circuitBreakerThreshold = 20

  /// Short yield between coordinator-sized drain windows. One cycle already
  /// performs substantial bounded work; continuing on a fresh task keeps a very
  /// large backlog moving without monopolizing the app's refresh call forever.
  public static let drainContinuationDelay: TimeInterval = 1

  public init() {}

  /// Whether the breaker is open (too many consecutive failures). While open,
  /// `shouldRun` returns false regardless of the backoff window.
  public var isCircuitBreakerOpen: Bool {
    consecutiveFailures >= Self.circuitBreakerThreshold
  }

  /// The backoff delay earned by `failureCount` consecutive failures, before
  /// jitter. Zero failures means no delay.
  ///
  /// `Retryable` schedule: `base * 2^min(count-1, 5)`, then clamped at
  /// `maxDelay`: 30s, 60s, 120s, 240s, 480s, 960s, holding at 960s thereafter.
  /// The exponent cap at 5 keeps the schedule below the 30-minute `maxDelay`
  /// ceiling, which the clamp enforces as a hard upper bound.
  public static func backoffDelay(consecutiveFailures failureCount: Int) -> TimeInterval {
    guard failureCount > 0 else { return 0 }
    let exponent = min(failureCount - 1, 5)
    let raw = baseDelay * pow(2, Double(exponent))
    return min(raw, maxDelay)
  }

  /// Deterministic gate: may a cycle run at `now`?
  ///
  /// The effective gate is `max(generic local backoff, server throttle)`: a cycle
  /// runs only once BOTH windows have elapsed. Returns false when the breaker is
  /// open, when a server-mandated `serverThrottleUntil` is still in the future, or
  /// when the previous attempt is still inside its backoff window
  /// (now < lastAttempt + backoff(failures)). `jitterFraction` (0 by default; in
  /// [-1, 1]) widens or narrows the LOCAL backoff window by up to ±10% (the server
  /// throttle is honored exactly, no jitter); tests pass 0 for an exact boundary
  /// and the AppStore passes a per-attempt random fraction. A first attempt (no
  /// `lastAttemptAt`, zero failures) runs unless a server throttle gates it.
  public func shouldRun(now: Date, jitterFraction: Double = 0) -> Bool {
    if isCircuitBreakerOpen { return false }
    // A server-mandated throttle gates independently of, and survives, the local
    // backoff — honor it before the "first attempt always runs" shortcut so a
    // push/activation reset cannot slip a cycle past an active server rate limit.
    if let serverThrottleUntil, now < serverThrottleUntil { return false }
    guard let lastAttemptAt, consecutiveFailures > 0 else { return true }
    let base = Self.backoffDelay(consecutiveFailures: consecutiveFailures)
    let clampedFraction = max(-1, min(1, jitterFraction))
    let jittered = base + base * 0.1 * clampedFraction
    return now >= lastAttemptAt.addingTimeInterval(jittered)
  }

  /// The next wake a foreground app owner should arrange when CloudSync still
  /// has work but no external trigger is guaranteed.
  ///
  /// `retryCurrentWork` covers a failed active outbox row, a thrown cycle, or a
  /// safe account/generation-boundary abort that consumed no local result.
  /// `continueDraining` covers the coordinator's defensive page cap. A durable
  /// SQLite retry deadline covers parked outbox rows and audit-record physical
  /// deletes. The earliest work deadline is then raised to the latest pacing
  /// gate (maximum local jitter plus any server retry-after), guaranteeing that
  /// the scheduled attempt cannot wake only to lose a newly-randomized gate.
  /// An open circuit breaker deliberately returns nil; activation/account-change
  /// reset remains its explicit recovery boundary.
  public func automaticRetryWakeAt(
    now: Date,
    retryCurrentWork: Bool,
    continueDraining: Bool,
    nextDeferredRetryAt: Date?
  ) -> Date? {
    guard !isCircuitBreakerOpen else { return nil }

    var workAt = nextDeferredRetryAt
    if retryCurrentWork {
      // The pacing state below owns the retry delay relative to the original
      // attempt. Treat the work itself as ready now, then raise it to that
      // stable gate. Adding a fresh base delay here would let every unrelated
      // refresh/activation inside the backoff window push the wake farther into
      // the future and, under frequent triggers, starve the retry indefinitely.
      workAt = workAt.map { min($0, now) } ?? now
    }
    if continueDraining {
      let continuationAt = now.addingTimeInterval(Self.drainContinuationDelay)
      workAt = workAt.map { min($0, continuationAt) } ?? continuationAt
    }
    guard var wakeAt = workAt else { return nil }

    if let lastAttemptAt, consecutiveFailures > 0 {
      let latestLocalGate = lastAttemptAt.addingTimeInterval(
        Self.backoffDelay(consecutiveFailures: consecutiveFailures) * 1.1)
      wakeAt = max(wakeAt, latestLocalGate)
    }
    if let serverThrottleUntil {
      wakeAt = max(wakeAt, serverThrottleUntil)
    }
    return wakeAt
  }

  /// Stamp the attempt time. Call immediately before running a gated cycle so
  /// the next backoff window is measured from the attempt, not its completion.
  public mutating func recordAttempt(now: Date) {
    lastAttemptAt = now
  }

  /// A clean cycle ran: clear the failure count, close the breaker, and lift any
  /// server throttle — a successful cycle proves the server is accepting requests
  /// again.
  public mutating func recordSuccess() {
    consecutiveFailures = 0
    serverThrottleUntil = nil
  }

  /// Honor a CloudKit server retry-after: hold the next attempt until at least
  /// `now + retryAfter`. Extends an existing throttle but never shortens it, so a
  /// burst of rate-limited responses converges on the latest server deadline. A
  /// non-positive interval is ignored. Independent of the consecutive-failure
  /// backoff — the throttle survives ``reset()``, which clears only the local
  /// backoff.
  public mutating func recordServerThrottle(retryAfter: TimeInterval, now: Date) {
    guard retryAfter > 0 else { return }
    let deadline = now.addingTimeInterval(retryAfter)
    serverThrottleUntil = Swift.max(serverThrottleUntil ?? deadline, deadline)
  }

  /// A cycle failed (threw, or reported no progress with a push failure):
  /// advance the consecutive-failure count toward the breaker threshold.
  public mutating func recordFailure() {
    consecutiveFailures += 1
  }

  /// Explicit reset: close the breaker and clear the generic LOCAL failure state
  /// (consecutive-failure count and last-attempt window). Wired to iCloud account
  /// change and app activation so a wedged breaker recovers on a fresh identity or
  /// an explicit return-to-app without waiting on the cycle.
  ///
  /// A server-mandated ``serverThrottleUntil`` is LEFT INTACT: it is the server's
  /// rate limit, not a local wedge, so a push or activation must not clear it and
  /// let the next cycle stampede past an active throttle. It expires on its own
  /// deadline (or clears on the next successful cycle).
  public mutating func reset() {
    consecutiveFailures = 0
    lastAttemptAt = nil
  }
}
