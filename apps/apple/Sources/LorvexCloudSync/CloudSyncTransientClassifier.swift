import Foundation
@preconcurrency import CloudKit

/// Classifies a push failure as a TRANSIENT transport outage versus a persistent
/// per-row error.
///
/// A transient failure — the network is down, the request was rate-limited, the
/// service or zone is momentarily busy, iCloud storage is full, or the server's
/// response was lost in transit — hits every pending outbox row identically. If
/// such a failure advanced `retry_count` (or tripped the outbox's same-error
/// escalation), a single outage would fast-forward a healthy backlog to
/// retry wait in a few cycles. So the transport records transient failures
/// without advancing the retry budget and reserves delayed recovery for genuinely
/// persistent per-row errors (malformed payload, schema mismatch, permission
/// revoked).
public enum CloudSyncTransientClassifier {
  /// True when `error` is a transient transport outage that must not push an
  /// outbox row toward retry wait. Handles `CKError`, `URLError`, and the
  /// bridged `NSError` shapes CloudKit can surface.
  public static func isTransient(_ error: any Error) -> Bool {
    if let partial = error as? CloudSyncPartialCycleFailure {
      return isTransient(partial.underlyingError)
    }
    if let failure = error as? CloudSyncPerRecordFetchFailure {
      return failure.kind == .transient
    }
    if let ckError = error as? CKError { return isTransient(ckError.code) }
    if let urlError = error as? URLError { return isTransient(urlError.code) }
    let ns = error as NSError
    if ns.domain == CKErrorDomain, let code = CKError.Code(rawValue: ns.code) {
      return isTransient(code)
    }
    if ns.domain == NSURLErrorDomain {
      return isTransient(URLError.Code(rawValue: ns.code))
    }
    return false
  }

  /// The CloudKit error codes that denote a transient outage rather than a
  /// permanent per-record rejection.
  ///
  /// `zoneNotFound` / `userDeletedZone` are deliberately excluded: they are not a
  /// plain retry-in-place but drive a dedicated recovery path (invalidate the zone
  /// cache, recreate the zone, re-pull from a nil token, then re-enqueue every live
  /// entity), so classifying them transient would keep the outbox re-pushing into a
  /// gone zone instead of triggering that recovery. `permissionFailure` is also
  /// excluded: it means access was genuinely revoked, a persistent per-record
  /// rejection rather than a momentary account state.
  public static func isTransient(_ code: CKError.Code) -> Bool {
    switch code {
    case .networkUnavailable, .networkFailure, .serviceUnavailable,
      .requestRateLimited, .zoneBusy,
      // iCloud storage full: a transient account state that clears once the user
      // frees space, so every push failing quotaExceeded during the outage must
      // NOT advance the whole outbox toward retry wait.
      .quotaExceeded,
      // The request's server-side outcome is ambiguous (the response was lost in
      // transit). CloudKit record saves are idempotent under
      // `.ifServerRecordUnchanged`, so an in-place retry is safe and correct.
      .serverResponseLost,
      // Auth-flavored account states CloudKit can surface WHOLESALE during an
      // iCloud token-refresh hiccup, AFTER the cycle's account gate already
      // passed. They clear on their own (the next cycle re-checks the account
      // gate), so every push failing during the hiccup must be retried in
      // place, not advanced toward retry wait.
      .notAuthenticated, .accountTemporarilyUnavailable:
      return true
    default:
      return false
    }
  }

  /// The server-mandated retry-after interval (seconds) CloudKit attaches to a
  /// `.requestRateLimited` or `.serviceUnavailable` response, or `nil` for any
  /// other error or when the server named no interval.
  ///
  /// These two codes are the ones CloudKit accompanies with `CKErrorRetryAfterKey`
  /// (surfaced as `CKError.retryAfterSeconds`): the server is explicitly telling
  /// the client the earliest instant it may retry. Honoring that instant holds
  /// the next cycle to the SERVER's deadline instead of the generic local backoff,
  /// which a user-driven trigger (`reset()`) would otherwise clear — letting the
  /// device stampede past an active server throttle and deepen the rate limit.
  /// Handles the bridged `NSError` shape CloudKit can surface too.
  public static func serverRetryAfter(_ error: any Error) -> TimeInterval? {
    if let partial = error as? CloudSyncPartialCycleFailure {
      return serverRetryAfter(partial.underlyingError)
    }
    if let failure = error as? CloudSyncPerRecordFetchFailure {
      return failure.retryAfter
    }
    let code: CKError.Code?
    let retryAfter: TimeInterval?
    if let ckError = error as? CKError {
      code = ckError.code
      retryAfter = ckError.retryAfterSeconds
    } else {
      let ns = error as NSError
      guard ns.domain == CKErrorDomain, let bridged = CKError.Code(rawValue: ns.code) else {
        return nil
      }
      code = bridged
      retryAfter = ns.userInfo[CKErrorRetryAfterKey] as? TimeInterval
    }
    switch code {
    case .requestRateLimited, .serviceUnavailable:
      guard let retryAfter, retryAfter > 0 else { return nil }
      return retryAfter
    default:
      return nil
    }
  }

  /// The URL-loading error codes CloudKit surfaces when the network transport
  /// itself failed, treated as transient for the same reason as their `CKError`
  /// equivalents.
  public static func isTransient(_ code: URLError.Code) -> Bool {
    switch code {
    case .notConnectedToInternet, .networkConnectionLost, .timedOut,
      .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
      .dataNotAllowed, .internationalRoamingOff:
      return true
    default:
      return false
    }
  }
}
