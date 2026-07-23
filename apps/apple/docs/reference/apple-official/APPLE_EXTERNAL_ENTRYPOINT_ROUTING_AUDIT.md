# Apple External Entrypoint Routing Audit

This is a read-only audit of navigation entrypoints. It covers custom URLs,
notification default taps, typed `NSUserActivity` continuations, Spotlight
result continuations, and iOS Home Screen quick actions. It deliberately excludes
App Intent execution code, file/archive imports, and the managed-storage / MCP
helper trust boundary; those are separate trust-boundary audits.

Last verified: 2026-07-10 against repository `HEAD` `84ab7de532` plus the
concurrent working-tree state present during review. The intervening commits from
`dfaeab0e3e` to `84ab7de532` did not change the route/parser files on which these
findings depend. No product code was changed.

## Primary Apple Sources

- [Defining a custom URL scheme for your app](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [onOpenURL(perform:)](https://developer.apple.com/documentation/swiftui/view/onopenurl%28perform%3A%29)
- [NSUserActivity](https://developer.apple.com/documentation/foundation/nsuseractivity)
- [NSUserActivity.userInfo](https://developer.apple.com/documentation/foundation/nsuseractivity/userinfo)
- [CSSearchableItemActionType](https://developer.apple.com/documentation/corespotlight/cssearchableitemactiontype)
- [CSSearchableItem](https://developer.apple.com/documentation/corespotlight/cssearchableitem)

Apple explicitly warns that custom URL schemes are an attack vector. Apps must
validate every parameter, discard malformed URLs, and limit URL actions so they
cannot endanger user data. Apple also recommends universal links over custom
schemes because another app can register the same scheme and the selected target
is undefined.

For Spotlight, Apple delivers `CSSearchableItemActionType` plus the indexed
item's unique identifier in `NSUserActivity.userInfo`; the app is responsible
for restoring the corresponding state. Apple also says indexes should be kept in
step with content so results continue to refer to valid objects.

## Architecture That Is Already Sound

The shared `LorvexDeepLinkContract` and `LorvexDeepLinkRoute` are a strong base:

- URL creation percent-encodes the complete entity ID as one path component;
- decoding deliberately round-trips IDs containing spaces, `%`, and `/`;
- foreign schemes, unknown hosts, empty IDs, unknown activity types, and unknown
  Spotlight prefixes are rejected;
- notification `userInfo` accepts an explicit URL only after the shared route
  parser validates it, then safely falls back to a task route;
- custom URLs perform navigation only; they do not directly delete, complete,
  defer, or expose entity contents;
- Home Screen quick-action identifiers are a closed enum, and an unknown
  identifier is ignored;
- task route loads are parameterized core reads, not SQL interpolation;
- stable route cases are shared by URL, activity, and Spotlight decoders.

The most important security property is therefore already present: an arbitrary
app can ask Lorvex to show a screen, but the public URL scheme is not a mutation
API. The remaining findings are parity, state restoration, validation depth, and
scheme ownership problems.

## Entrypoint Matrix

| Logical target | Shared URL | macOS URL | iOS/vision URL | Typed activity | Spotlight continuation | Actual detail restoration |
| --- | --- | --- | --- | --- | --- | --- |
| Workspace | `lorvex://open/<destination>`; the bare-host form `lorvex://<destination>` is also accepted | Yes | Yes | Yes | Calendar events map to Calendar | Workspace only, as intended |
| Task | `lorvex://task/<id>` | Yes | Yes | Yes | Yes | macOS and mobile load detail; stale ID handling differs |
| List | `lorvex://list/<id>` | Yes | **No** | Yes | Yes | macOS/mobile activity and Spotlight restore list detail |
| Habit | `lorvex://habit/<id>` | Parsed | **No** | No typed activity | Parsed | Both shells currently discard the ID |
| Daily review | `lorvex://review/<date>` | Parsed | **No** | No typed activity | Parsed | Both shells currently discard the date |
| Quick capture | closed quick-action ID | In-process command / Tasks fallback | Opens capture sheet | Not applicable | Not applicable | Correctly requires user interaction |

“Parsed” means the shared resolver preserves the payload. It does not mean the
platform navigation layer consumes it correctly.

## Findings

### E1 — HIGH: habit notification default taps are unroutable on iOS and visionOS

Habit notification content stores
`LorvexDeepLinkRoute.habit(habitID).url`, producing
`lorvex://habit/<id>`. The mobile/vision app delegate validates that URL through
`LorvexNotificationRoute` and asks the system to open it. SwiftUI then delivers
it to `MobileStore.openDeepLink`.

`MobileDeepLinkRoute`, however, supports only `.task` and `.tab`; it recognizes
the `task` and `open` hosts but not `list`, `habit`, or `review`. The habit URL is
therefore rejected after the user taps the notification. No habit screen or
detail opens.

Relevant code:

- `Sources/LorvexCore/Support/HabitReminderScheduling.swift`
- `Sources/LorvexMobileApp/LorvexMobileAppDelegate.swift`
- `Sources/LorvexMobile/MobileSystemEntrypoints.swift`
- `Sources/LorvexMobile/MobileDeepLinkRouting.swift`

This should be treated as a release blocker for iPhone notification parity. An
end-to-end test must begin with `ScheduledHabitReminder.notificationRequest`,
extract its user-info route, feed the URL to the mobile store, and assert that
the matching habit detail route/selection is visible. Resolver-only tests cannot
prove this composition.

### E2 — MEDIUM-HIGH: habit IDs and review dates survive parsing but are discarded by navigation

The shared resolver correctly produces `.habit(id)` and `.review(date)`. The
macOS `AppStore.applyRouteNavigation` switches on `.habit` and `.review` without
binding their associated values; it selects only the Habits or Reviews
workspace. Mobile Spotlight routing does the same.

Consequences:

- a Spotlight result for a specific habit opens the habit catalog, not that
  habit's inspector/detail;
- a Spotlight result for a specific daily review opens Reviews but leaves the
  previously selected date in place;
- a macOS `lorvex://habit/<id>` or `lorvex://review/<date>` URL behaves the same;
- when mobile entity URLs are added, simply accepting their hosts will still be
  incomplete unless the payload reaches `MobileRoute.habit(id)` or
  `selectReviewDay(date)`.

This contradicts the shared resolver's “single entity-open” contract and
Spotlight's state-restoration purpose. The route enum should have one explicit
platform mapping per case, and every associated value should either be consumed
or the case should be documented as workspace-only and lose the misleading ID.

### E3 — MEDIUM-HIGH: the shared URL contract and the mobile URL contract have diverged

`LorvexDeepLinkContract` publicly constructs list, habit, and review URLs. Those
URLs are used by system surfaces and are described as cross-platform. The mobile
parser implements a smaller, separate enum rather than mapping the full shared
route enum to mobile navigation.

Typed open-list activity and Spotlight happen to bypass that parser and route
lists correctly, which masks the divergence. A URL delivered by a widget,
notification, another app, a pasted link, or a future `contentURL` takes the
broken path instead.

The durable simplification is:

1. parse every external URL exactly once into `LorvexDeepLinkRoute`;
2. map that exhaustive enum into a platform-specific navigation target;
3. make compiler exhaustiveness expose a new shared route that a shell has not
   implemented.

Keeping a second parser with a subset of hosts is what allowed E1.

### E4 — MEDIUM: stale or not-yet-synced entity restoration has no unified policy

Entity IDs can arrive from a different device, an old Spotlight index, a prior
database, or the same CloudKit account before the entity has reached this
device. Current outcomes vary:

- macOS task routes try a direct load, show an error, and clear selection when
  the entity is absent;
- macOS list routes leave the requested list selected while the load error is
  surfaced;
- mobile tasks try a direct load and then show “Task Not Found”;
- habit/review routes currently avoid the question by dropping their payload;
- no route path explicitly performs/awaits a sync catch-up and retries once.

An external continuation should not be allowed to mutate the selected database,
but it should distinguish at least:

- malformed identifier;
- valid identifier absent in the current database;
- current database unavailable;
- CloudKit catch-up pending/failed;
- entity deleted or archived;
- entity exists but is outside the currently loaded projection.

Define one restoration policy and one user-facing “not available on this device”
state. For cross-device Handoff, a bounded sync-and-retry is preferable to an
immediate permanent-looking 404, while still handling offline use promptly.

### E5 — MEDIUM: custom-scheme ownership is not guaranteed, and the release plan does not record the collision policy

Apple says custom URL scheme ownership is not exclusive. Lorvex relies on
`lorvex://` for notifications, widgets, Handoff-adjacent routing, Spotlight
content URLs, macOS Dock fallbacks, and external links. If another app claims the
scheme, the system target is undefined.

There is also a Lorvex-specific distribution question: native macOS, iOS/iPadOS,
and visionOS apps all declare the same scheme. Normally they live on different
device families, but “Designed for iPad” availability on Apple-silicon Macs and
iPad-app compatibility on visionOS can create two Lorvex bundles capable of
claiming the same scheme unless App Store availability is deliberately
controlled.

This does not require universal links immediately, especially if Lorvex has no
stable web domain yet. It does require a recorded choice:

- adopt an HTTPS universal-link namespace with Associated Domains;
- or keep the custom scheme, prevent same-device Lorvex bundle collisions in
  App Store distribution settings, and accept third-party scheme hijacking for
  navigation-only links.

Never put credentials, secrets, exported content, or destructive commands in
this scheme.

### E6 — LOW-MEDIUM: parameter validation is structural but not semantic or bounded

URL/activity/Spotlight parsers generally require only a recognized prefix and a
nonempty string. They do not bound length, reject control/whitespace-only values,
validate canonical entity IDs, or parse review dates as `LorvexDate` before
creating a route. Query strings and fragments are ignored rather than rejected.

Because public URLs only navigate and core reads use parameters, this is not a
direct data-corruption vulnerability. It is still short of Apple's explicit
instruction to validate every URL parameter and test malformed input. It can
also produce confusing selections, expensive oversized state strings, and
misleading not-found errors.

Validation should occur in the shared resolver, before platform state changes:

- enforce a documented maximum encoded and decoded URL length;
- validate task/list/habit ID shape according to the actual persisted contract;
- parse review dates strictly and reject impossible/future dates according to
  product rules;
- reject unexpected extra path structure, query items, or fragments unless they
  become part of a versioned contract;
- trim/reject empty Unicode whitespace and control characters.

Do not over-constrain legacy/imported IDs unless the database contract already
guarantees UUIDv7; route validation and persisted-data compatibility must agree.

### E7 — MEDIUM: tests prove decoders, not end-to-end system-surface parity

The test suite has strong round-trip and malformed-happy-path coverage for the
shared resolver, task Handoff, list Handoff, Spotlight identifiers, and workspace
mobile links. It does not maintain an exhaustive matrix from each producer to
each platform consumer.

Missing composition tests include:

- every notification request's `userInfo` through macOS and mobile default-tap
  handling;
- every shared URL route through macOS and mobile navigation state;
- every Spotlight document identifier through both continuation handlers and
  final entity/date selection;
- stale/deleted/not-yet-synced IDs;
- whitespace, control characters, very long IDs, invalid percent escapes,
  unexpected queries/fragments, and unencoded extra slashes;
- cold launch versus already-running app;
- multiple windows/scenes and which one receives `onOpenURL`;
- two installed Lorvex-capable bundles on an Apple-silicon Mac or Vision Pro.

An exhaustive route-producer/consumer table should be data-driven so adding a
new enum case fails every platform test until it has a mapping.

## Related Existing Findings

`CORE_SPOTLIGHT_DATA_PROTECTION.md` already records that:

- the default Spotlight index is not the intended production protection design;
- delete-then-index replacement is non-atomic;
- mobile has result handlers but no real index donation;
- indexed documents are not unified with AppEntity/IndexedEntity models.

Those findings are not duplicated here. They amplify E2 and E4: a routing
handler cannot make iOS Spotlight functional without donation, and a perfectly
indexed result is still broken if its identifier payload is discarded.

## Release Recommendation

Fix E1 and E2 before calling notifications or Spotlight complete. Resolve E3 by
making the shared route enum the only URL parser. Decide E4/E5 before publishing
cross-device Handoff and external-link promises. E6/E7 should be closed in the
same refactor because centralized validation and an exhaustive matrix are what
keep route parity from drifting again.

No SQLite or CloudKit schema change is inherently required. The important
compatibility artifact is the public URL/activity identifier contract: once
third-party automation, widgets, notifications, and user-authored links depend
on it, removing or changing a route becomes an external backward-compatibility
commitment.
