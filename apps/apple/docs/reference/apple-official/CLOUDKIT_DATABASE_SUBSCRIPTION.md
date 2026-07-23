# CKDatabaseSubscription

Source: [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)

Last verified: 2026-07-10

## Apple Contract

- A database subscription is per user and indicates that something changed.
- CloudKit may coalesce notifications and omit payload detail. The notification
  must not be treated as the change itself; fetch changes using server tokens.
- Apple recommends recording successful installation on device to avoid an
  unnecessary server round trip on every launch.
- The modern async `modifySubscriptions(saving:deleting:)` API can complete the
  request successfully while returning a failure in an individual
  subscription's `Result`.
- CloudKit's subscription documentation also warns to create subscription
  definitions in development and promote them before relying on production.

## Lorvex Mapping

The convergence design is correct: a notification triggers a token-based zone
change fetch, and foreground refresh is a backstop.

The installation implementation has three weaknesses:

1. `CloudKitCloudSyncSubscriber.registerSubscription()` discards the returned
   `saveResults` dictionary. A per-subscription failure is therefore reported to
   callers as success.
2. Callers set `hasRegisteredSubscription = true` after that false success and
   do not retry again in the process session.
3. Outer request failures leave the flag false and retry on every refresh, with
   no subscription-specific backoff or server `retryAfterSeconds` handling.

The fixed subscription ID makes updates deterministic, but does not make it
safe to ignore the per-item result.

## Audit Conclusion

This is a new medium-severity correctness/reliability finding. It can silently
disable remote-change notifications for a session while the UI reports no
subscription error. Foreground activation still provides eventual convergence,
so it is not by itself permanent data loss.

Production release evidence should include one physical-device test that deletes
the subscription, cold-launches the production-entitled build, verifies the
server subscription exists, and then observes a peer-device change.
