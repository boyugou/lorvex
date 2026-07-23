# Pushing Background Updates to Your App

Source: [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

Last verified: 2026-07-10

## Apple Contract

- Background notifications are low priority, may be throttled, and are not
  guaranteed to arrive.
- The system may coalesce them and retain only the newest pending notification.
- On iOS, the app has 30 seconds to finish its work and call the background-fetch
  completion handler.
- The completion result should reflect whether data arrived, no data arrived, or
  the fetch failed.

## Lorvex Mapping

`LorvexMobileAppDelegate` correctly validates that the payload is a Lorvex
CloudKit notification, preserves a durable handoff when no store is attached,
and maps the store result to `UIBackgroundFetchResult`.

The attached-store path awaits a full `MobileStore.refresh()`. That path can:

- register a subscription;
- drain as many as 64 CloudKit pages;
- run local snapshot reads;
- publish widget data;
- reschedule reminders; and
- update the badge.

It has no deadline, timeout, cancellation handoff, or use of the remaining
background execution budget. It can also wait behind an already-running refresh
and its coalesced rerun.

## Audit Conclusion

This is a new medium-severity reliability issue. A large backlog or slow network
can exceed Apple's 30-second budget, causing termination before the completion
handler and reducing the system's willingness to deliver later background
notifications.

A future fix should make the background entry point bounded independently of
the foreground refresh: durably record pending work first, drain only within a
short deadline (for example, leave several seconds of safety margin), call the
completion handler, and resume any remaining pages on a later foreground or
background opportunity.
