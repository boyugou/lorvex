# TN3162: Understanding CloudKit Throttles

Source: [TN3162: Understanding CloudKit throttles](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles)

Last verified: 2026-07-10

## Apple Contract

When CloudKit returns `requestRateLimited` or `serviceUnavailable`, read
`CKError.retryAfterSeconds` (also available under `CKErrorRetryAfterKey`) and do
not retry before that interval expires. CloudKit may reject every request until
the throttle expires. Apple also recommends minimizing bursts and deferring work
that is not needed in the current session.

## Lorvex Mapping

Lorvex has a useful local exponential schedule (`CloudSyncPacing`), transient
classification, jitter, and a circuit breaker. It does not preserve or honor the
server-provided retry time:

- per-record push failures are reduced to an error string plus a transient bit;
- wholesale push failures are converted into outbox failure records;
- fetch/account errors reach the app layer, but pacing records only a generic
  failure count; and
- subscription registration retries are outside the main pacing gate.

On iOS, a CloudKit notification also resets `CloudSyncPacing` before refresh.
That is reasonable for an ordinary stale local backoff, but it would override a
server-mandated throttle unless the two concepts are separated.

## Audit Conclusion

This is a new medium-severity operational issue. The future model should carry a
`notBefore` deadline derived from the maximum applicable server retry interval,
persist it if work may survive process death, and never clear it merely because
another push or foreground trigger arrives. Local exponential backoff can remain
as an additional floor for errors without a server interval.
