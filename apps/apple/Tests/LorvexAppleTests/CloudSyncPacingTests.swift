import Foundation
import Testing
import LorvexCloudSync
@preconcurrency import CloudKit

@testable import LorvexApple

// Deterministic clock: every decision is taken at an explicit `now` passed in,
// never `Date()`, so the schedule boundaries are exact.
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: - First attempt

@Test
func freshPacingRunsImmediately() {
  let pacing = CloudSyncPacing()
  #expect(pacing.shouldRun(now: t0))
  #expect(!pacing.isCircuitBreakerOpen)
}

// MARK: - Backoff schedule

@Test
func firstFailureWaitsBaseDelay() {
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()

  // Just before the 30s floor: still gated. At the floor: allowed. Jitter 0 for
  // an exact boundary.
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(29), jitterFraction: 0))
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(30), jitterFraction: 0))
}

@Test
func backoffDelayGrowsExponentiallyTowardCap() {
  // The exponent is capped at 5 (matching the oracle's `(count-1).min(5)`):
  // 30s, 60s, 120s, 240s, 480s, 960s, then the schedule saturates at 960s.
  // The 30-minute (`maxDelay`) clamp is a safety ceiling the exponent cap keeps
  // the schedule below — exercised by `backoffDelayNeverExceedsMaxDelay`.
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 0) == 0)
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 1) == 30)
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 2) == 60)
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 3) == 120)
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 6) == 960)
  // Past the 6th failure the exponent stays clamped, so the delay holds at 960s.
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 7) == 960)
  #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: 20) == 960)
}

@Test
func backoffDelayNeverExceedsMaxDelay() {
  for failures in 0...100 {
    #expect(CloudSyncPacing.backoffDelay(consecutiveFailures: failures) <= CloudSyncPacing.maxDelay)
  }
}

@Test
func backoffWindowMeasuresFromLastAttempt() {
  var pacing = CloudSyncPacing()
  // Two failures earns the 60s window, measured from the second attempt.
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()
  let secondAttempt = t0.addingTimeInterval(100)
  pacing.recordAttempt(now: secondAttempt)
  pacing.recordFailure()

  #expect(!pacing.shouldRun(now: secondAttempt.addingTimeInterval(59), jitterFraction: 0))
  #expect(pacing.shouldRun(now: secondAttempt.addingTimeInterval(60), jitterFraction: 0))
}

@Test
func jitterWidensAndNarrowsTheWindowByTenPercent() {
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()  // 30s base window.

  // +10% jitter pushes the boundary out to 33s: 30s is still gated.
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(30), jitterFraction: 1))
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(33), jitterFraction: 1))
  // -10% jitter pulls the boundary in to 27s: 27s is now allowed.
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(27), jitterFraction: -1))
}

@Test
func automaticRetryWakeUsesTheLatestPossibleGate() {
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()
  pacing.recordServerThrottle(retryAfter: 90, now: t0)

  #expect(
    pacing.automaticRetryWakeAt(
      now: t0, retryCurrentWork: true, continueDraining: false,
      nextDeferredRetryAt: nil)
      == t0.addingTimeInterval(90))
}

@Test
func repeatedTriggersDoNotPostponeTheExistingRetryGate() {
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()
  let gate = t0.addingTimeInterval(CloudSyncPacing.baseDelay * 1.1)

  #expect(
    pacing.automaticRetryWakeAt(
      now: t0.addingTimeInterval(10), retryCurrentWork: true,
      continueDraining: false, nextDeferredRetryAt: nil) == gate)
  #expect(
    pacing.automaticRetryWakeAt(
      now: t0.addingTimeInterval(20), retryCurrentWork: true,
      continueDraining: false, nextDeferredRetryAt: nil) == gate)
}

@Test
func automaticRetryWakeCarriesDurableDeadlinesAndBoundedDrainContinuation() {
  let pacing = CloudSyncPacing()
  let deferred = t0.addingTimeInterval(3_600)

  #expect(
    pacing.automaticRetryWakeAt(
      now: t0, retryCurrentWork: false, continueDraining: false,
      nextDeferredRetryAt: deferred) == deferred)
  #expect(
    pacing.automaticRetryWakeAt(
      now: t0, retryCurrentWork: false, continueDraining: true,
      nextDeferredRetryAt: deferred)
      == t0.addingTimeInterval(CloudSyncPacing.drainContinuationDelay))
}

@Test
func automaticRetryWakeStopsAtTheCircuitBreaker() {
  var pacing = CloudSyncPacing()
  for _ in 0..<CloudSyncPacing.circuitBreakerThreshold {
    pacing.recordAttempt(now: t0)
    pacing.recordFailure()
  }

  #expect(
    pacing.automaticRetryWakeAt(
      now: t0, retryCurrentWork: true, continueDraining: true,
      nextDeferredRetryAt: t0.addingTimeInterval(60)) == nil)
}

// MARK: - Circuit breaker

@Test
func circuitBreakerOpensAtThreshold() {
  var pacing = CloudSyncPacing()
  for _ in 0..<(CloudSyncPacing.circuitBreakerThreshold - 1) {
    pacing.recordAttempt(now: t0)
    pacing.recordFailure()
  }
  #expect(!pacing.isCircuitBreakerOpen)

  pacing.recordAttempt(now: t0)
  pacing.recordFailure()
  #expect(pacing.isCircuitBreakerOpen)
  // Open breaker gates even far past any backoff window.
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(60 * 60 * 24), jitterFraction: 0))
}

@Test
func successResetsFailureCountAndClosesBreaker() {
  var pacing = CloudSyncPacing()
  for _ in 0..<CloudSyncPacing.circuitBreakerThreshold {
    pacing.recordAttempt(now: t0)
    pacing.recordFailure()
  }
  #expect(pacing.isCircuitBreakerOpen)

  pacing.recordSuccess()
  #expect(!pacing.isCircuitBreakerOpen)
  #expect(pacing.consecutiveFailures == 0)
  // With the failure count cleared, the next trigger runs immediately.
  #expect(pacing.shouldRun(now: t0))
}

@Test
func resetClearsBackoffAndBreaker() {
  var pacing = CloudSyncPacing()
  for _ in 0..<CloudSyncPacing.circuitBreakerThreshold {
    pacing.recordAttempt(now: t0)
    pacing.recordFailure()
  }
  #expect(pacing.isCircuitBreakerOpen)

  pacing.reset()
  #expect(!pacing.isCircuitBreakerOpen)
  #expect(pacing.consecutiveFailures == 0)
  #expect(pacing.shouldRun(now: t0))
}

// MARK: - F3: server retry-after (notBefore) throttle

@Test
func serverThrottleGatesFreshPacingUntilDeadline() {
  var pacing = CloudSyncPacing()
  pacing.recordServerThrottle(retryAfter: 60, now: t0)

  // Even with no failures (a first attempt would otherwise run), the server
  // throttle gates while `now` is before its deadline. The deadline instant
  // itself is the earliest allowed attempt — the same boundary convention as the
  // local backoff, whose window opens AT `lastAttempt + backoff`.
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(59), jitterFraction: 0))
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(60), jitterFraction: 0))
}

@Test
func serverThrottleSurvivesReset() {
  // The CRITICAL invariant: a server-mandated retry-after must outlive reset()
  // (wired to push / app activation), so a user-driven trigger cannot stampede
  // past an active server rate limit.
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()  // earns a local backoff too
  pacing.recordServerThrottle(retryAfter: 120, now: t0)

  pacing.reset()

  // The local backoff is cleared…
  #expect(pacing.consecutiveFailures == 0)
  #expect(pacing.lastAttemptAt == nil)
  // …but the server throttle is intact and still gates until its deadline.
  #expect(pacing.serverThrottleUntil == t0.addingTimeInterval(120))
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(119), jitterFraction: 0))
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(121), jitterFraction: 0))
}

@Test
func shouldRunHonorsLaterOfLocalBackoffAndServerThrottle() {
  var pacing = CloudSyncPacing()
  pacing.recordAttempt(now: t0)
  pacing.recordFailure()  // 30s local backoff
  pacing.recordServerThrottle(retryAfter: 90, now: t0)  // 90s server throttle

  // Past the 30s local window but still inside the 90s server throttle: gated.
  #expect(!pacing.shouldRun(now: t0.addingTimeInterval(45), jitterFraction: 0))
  // Past both windows: allowed.
  #expect(pacing.shouldRun(now: t0.addingTimeInterval(91), jitterFraction: 0))
}

@Test
func recordServerThrottleExtendsButNeverShortens() {
  var pacing = CloudSyncPacing()
  pacing.recordServerThrottle(retryAfter: 100, now: t0)
  // A shorter subsequent throttle must not pull the deadline in.
  pacing.recordServerThrottle(retryAfter: 10, now: t0)
  #expect(pacing.serverThrottleUntil == t0.addingTimeInterval(100))
  // A longer one extends it.
  pacing.recordServerThrottle(retryAfter: 200, now: t0)
  #expect(pacing.serverThrottleUntil == t0.addingTimeInterval(200))
  // A non-positive interval is ignored.
  pacing.recordServerThrottle(retryAfter: 0, now: t0)
  #expect(pacing.serverThrottleUntil == t0.addingTimeInterval(200))
}

@Test
func recordSuccessLiftsServerThrottle() {
  var pacing = CloudSyncPacing()
  pacing.recordServerThrottle(retryAfter: 300, now: t0)
  pacing.recordSuccess()
  #expect(pacing.serverThrottleUntil == nil)
  #expect(pacing.shouldRun(now: t0))
}

@Test
func transientClassifierExtractsServerRetryAfterOnlyForThrottleCodes() {
  // A CloudKit-domain NSError bridges to CKError, so the classifier reads its
  // `retryAfterSeconds`. The two rate-limit codes surface the interval…
  let rateLimited = NSError(
    domain: CKErrorDomain, code: CKError.Code.requestRateLimited.rawValue,
    userInfo: [CKErrorRetryAfterKey: 42.0])
  #expect(CloudSyncTransientClassifier.serverRetryAfter(rateLimited) == 42)
  let unavailable = NSError(
    domain: CKErrorDomain, code: CKError.Code.serviceUnavailable.rawValue,
    userInfo: [CKErrorRetryAfterKey: 15.0])
  #expect(CloudSyncTransientClassifier.serverRetryAfter(unavailable) == 15)

  // …but an unrelated transient code carrying a retry-after does NOT (only the
  // two throttle codes are honored)…
  let zoneBusy = NSError(
    domain: CKErrorDomain, code: CKError.Code.zoneBusy.rawValue,
    userInfo: [CKErrorRetryAfterKey: 20.0])
  #expect(CloudSyncTransientClassifier.serverRetryAfter(zoneBusy) == nil)
  // …and a throttle code with NO retry-after yields nil (falls back to local backoff).
  #expect(CloudSyncTransientClassifier.serverRetryAfter(CKError(.requestRateLimited)) == nil)
  // A non-CloudKit error is never a server throttle.
  #expect(CloudSyncTransientClassifier.serverRetryAfter(URLError(.timedOut)) == nil)
}
