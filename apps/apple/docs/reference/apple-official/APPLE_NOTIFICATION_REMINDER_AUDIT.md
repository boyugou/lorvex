# Apple Notification and Reminder Audit

This is a read-only source and contract audit. It does not change product code.

Last verified: 2026-07-10 against repository `HEAD` `84ab7de532` plus the
concurrent working-tree state present during review. The notification scheduler,
planner, budget, and delivery-state files cited below were read directly; another
agent was editing unrelated and lifecycle files at the same time. The intervening
commits from `dfaeab0e3e` to `84ab7de532` did not change the notification,
reminder-state, preference, or routing files on which these findings depend.

## Primary Apple Sources

- [Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [UNCalendarNotificationTrigger](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [UNNotificationSettings](https://developer.apple.com/documentation/usernotifications/unnotificationsettings)
- [getDeliveredNotifications](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29)
- [User Notifications](https://developer.apple.com/documentation/usernotifications/)
- [Calendar.MatchingPolicy](https://developer.apple.com/documentation/foundation/calendar/matchingpolicy)
- [Using background tasks to update your app](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)
- [Choosing background strategies for your app](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [UILocalNotification](https://developer.apple.com/documentation/uikit/uilocalnotification) — deprecated API documentation, used only to identify the historical 64-request statement; it is not treated as a current `UNNotificationRequest` contract.

Apple's current documentation establishes several important boundaries:

- adding a request can fail and must be handled;
- a pending request remains active until it fires or the app cancels it;
- notification delivery is best effort, not guaranteed;
- authorization and individual alert/sound/badge settings can change at any
  time, so Apple recommends reading `UNNotificationSettings` before scheduling;
- `deliveredNotifications()` returns only notifications still visible in
  Notification Center, not a durable complete delivery ledger;
- invalid local times require an explicit calendar matching policy if the app
  needs strict skip/adjust semantics;
- periodic background refresh is opportunistic and must be registered and
  requested explicitly.

## Current Lorvex Design

Lorvex has a thoughtfully factored notification subsystem:

- task and habit candidates are budgeted together by earliest fire date;
- stable identifier prefixes allow stale requests to be reaped;
- task notifications include deep-link metadata and localized rich actions;
- task notes are excluded from notification bodies unless the user opts in;
- snoozes use a separate identifier namespace and are removed when a task is no
  longer active;
- the onboarding gate avoids an out-of-context first permission prompt;
- macOS exposes the latest task/habit scheduling reports in diagnostics;
- habit occurrence planning has injected timezone tests and explicit cadence
  logic rather than relying on repeating notification triggers.

Those are good foundations. The remaining problems are composition and truth-
model problems rather than an absence of notification infrastructure.

## Findings

### N1 — HIGH: elapsed time is recorded as actual delivery even when no request was armed or shown

Both shells run delivery reconciliation before rebuilding the schedule:

- task reconciliation marks every due, live, pending reminder as `delivered`
  solely because `reminder_at <= now`;
- habit reconciliation stamps `last_delivered_at` for an elapsed occurrence solely
  from wall-clock time and period progress.

This happens independently of notification authorization, budget selection,
`UNUserNotificationCenter.add` success, pending-request presence, or actual OS
delivery. Therefore all of these become false “delivered” rows:

1. a reminder excluded by the 60-request budget;
2. a reminder never armed because permission was denied;
3. a reminder removed during replacement and not re-added after an error;
4. a reminder beyond the rolling window when the app never ran again;
5. a request the OS did not deliver.

For tasks, the false stamp then removes the row from `getDueTaskReminders`, whose
query accepts only `delivery_state = 'pending'`. For habits, it can suppress the
rest of a week or month through same-period debounce. This converts an uncertain
OS outcome into authoritative local data and hides misses from assistant/MCP
queries and diagnostics.

Relevant code:

- `Sources/LorvexApple/Stores/AppStoreAppleSurfacePublishing.swift`
- `Sources/LorvexMobile/MobileStoreNotificationActions.swift`
- `core/Sources/LorvexStore/TaskRepoReminders.swift`
- `Sources/LorvexCore/Services/SwiftLorvexCoreService+HabitDueReminders.swift`

Apple does not provide a durable, exhaustive local-notification delivery
receipt. `deliveredNotifications()` is useful evidence only while a notification
remains visible. Lorvex therefore needs an honest state model such as
`pending -> armed -> elapsed/observed`, with “delivered” reserved for evidence the
product can actually support. At minimum, budgeted-out, denied, and add-failed
rows must never be stamped delivered.

### N2 — HIGH: the 60-request/14-day rolling windows are not self-replenishing

Each re-plan arms only the earliest 60 task-plus-habit requests. Habit occurrences
are generated for 14 days. When a one-shot request fires, the OS frees a pending
slot, but no Lorvex code necessarily runs to fill it. iOS declares only the
`remote-notification` background mode; no `BGAppRefreshTask` registration or
request was found. A CloudKit silent push is change-driven and best effort, not a
timer that can be relied upon to replenish local reminders.

If the user does not open the app, mutate data, or receive a useful remote-change
wake before the window is exhausted:

- request 61 and later remain unarmed;
- habit reminders beyond day 14 remain unarmed;
- the next eventual refresh can incorrectly classify their elapsed times as
  delivered through N1.

The budgeter returns `truncated`, but neither macOS nor iOS preserves or surfaces
that value. The comments promise that truncation can be surfaced; the caller
discards it. macOS diagnostics therefore show only the post-budget requested
count, and iOS discards both schedule reports entirely.

The release contract needs one explicit strategy:

- prove that the supported product maximum fits a single durable pending set;
- or add an opportunistic background refill plus visible “next N armed” state;
- or use a different server-backed/OS-supported delivery design for reminders
  outside the local pending window.

`BGAppRefreshTask` can improve refill opportunities but Apple controls when it
runs, so it is not by itself a guarantee.

### N3 — HIGH: weekly habit debounce is computed after delivery, but later notifications are already armed

The habit planner's intended same-period debounce depends on
`habit_reminder_delivery_state.last_delivered_at`. Reconciliation updates that value
only when Lorvex next runs. During the preceding re-plan, a weekly habit with a
daily schedule and no stored `last_delivered_at` can contribute multiple future days
in the same week. All of those one-shot requests are armed immediately.

When Monday's request fires in the background, it does not execute Lorvex
reconciliation or cancel Tuesday through Sunday. Unless the user opens or
otherwise wakes the app, the already-armed same-week requests continue to fire.
The existing test demonstrates that a later same-week occurrence is suppressed
*after* an explicit reconciliation call, but does not test the actual system
sequence in which the later requests were already submitted.

This must be resolved as a product semantic before schema freeze:

- if the promise is one nudge per cadence period, plan at most the first eligible
  occurrence per policy/period before submitting requests;
- if the promise is “remind on every scheduled day until completed,” remove the
  misleading same-period delivery debounce and model that behavior explicitly.

Current comments and tests describe the former, while scheduling behavior can
produce the latter.

### N4 — HIGH: task reminder timezone-anchor columns promise a re-anchor path that does not exist

The schema and `ReminderAnchor` state that `original_local_time` and
`original_tz` preserve the user's local wall-clock intent so a later `timezone`
preference change can re-materialize `reminder_at`. Writers correctly populate
the columns, and import/export/sync preserve them.

However, the preference write path only upserts the preference, enqueues sync,
and writes the changelog. No source path was found that walks active task
reminders and recomputes `reminder_at` when `timezone` changes, either for a
local preference mutation or an inbound synced preference. The anchor fields are
therefore currently write-only metadata for this promised behavior.

This is exactly the kind of pre-launch contract debt that becomes expensive
after schema and sync semantics freeze. Either implement the re-anchor invariant
atomically with timezone changes and specify conflict behavior, or remove/change
the promise and define reminders as absolute instants. Do not ship a schema that
claims both semantics.

Relevant code:

- `Sources/LorvexCore/Resources/schema.sql`
- `core/Sources/LorvexWorkflow/ReminderAnchor.swift`
- `Sources/LorvexCore/Services/SwiftLorvexCoreService+Preferences.swift`

### N5 — MEDIUM-HIGH: overlapping re-plans can let an older pass re-arm stale data

`AppStore` and `MobileStore` are `@MainActor`, and their full refresh loops are
coalesced. That does not make `rescheduleReminders` non-reentrant: it contains
multiple suspension points, and direct task/habit mutations, notification-action
refreshes, scene activation, database-change signals, and CloudKit refreshes can
request re-plans through different paths.

There is no reminder-specific generation token, single-flight loop, or serial
actor. A valid interleaving is:

1. pass A reads an old candidate set containing reminder R and suspends;
2. pass B reads the new set without R, removes old requests, and arms the new set;
3. pass A resumes, performs its own prefix replacement, and re-arms R.

Stable identifiers make a single pass idempotent but do not prevent a stale pass
from reintroducing a removed identifier. The same race can overwrite macOS's
latest diagnostic report with an older result.

A scheduler-level serialized “latest desired set wins” transaction/generation is
needed. This should be tested with controllable suspension points, not inferred
from `@MainActor` isolation.

### N6 — MEDIUM-HIGH: replacement destroys the last known-good schedule before the new one is known to be viable

Both live schedulers implement replacement as:

1. fetch every pending request;
2. remove every Lorvex request under that prefix;
3. request/check authorization;
4. add the desired requests sequentially and stop on first error.

Consequences:

- an authorization API error can erase an otherwise valid pending set;
- an add failure leaves an arbitrary partial set;
- the operation has no automatic durable retry;
- macOS records a report, while iOS discards it;
- task and habit replacement are separate, so the combined desired set is not
  committed as one logical generation.

The system API has no multi-request transaction, so Lorvex must supply its own
failure policy. A diff-based update or generation-based two-phase strategy can
preserve unaffected requests and make partial failure observable.

### N7 — MEDIUM: transient read failures intentionally shrink or erase pending reminders

On macOS, a habit occurrence-read error is converted to an empty occurrence
list, which removes every pending habit reminder. On iOS the same error is
silently converted to empty and also clears the set. Conversely, an iOS failure
of the bounded upcoming-task query falls back to `snapshot.today.tasks`; the
replacement then removes valid reminders for tasks outside that partial
snapshot.

This is inconsistent with the macOS task-read policy, which preserves the
existing pending set when the authoritative task read fails. A transient SQLite
or decoding failure should not turn into destructive notification cancellation
unless staleness is known to be more dangerous than missed reminders. Whatever
policy is chosen must be symmetric, visible, and retried.

### N8 — MEDIUM: the “64 cap with four spare slots” invariant is neither current-contract-backed nor enforced

`ReminderBudget` states that iOS and macOS keep at most 64 pending requests and
silently drop the rest. Apple's currently published `UserNotifications`
documentation reviewed for this audit does not state that `UNNotificationRequest`
limit. Apple's deprecated `UILocalNotification` page does state that the system
kept the soonest 64. Treating that historical statement as a conservative
engineering assumption is reasonable; presenting it as a current cross-platform
public contract is not.

The four-slot headroom is also unenforced. Each active task can have one stable
snooze request, and snoozes are deliberately outside the shared budget. Five
simultaneously snoozed tasks produce 60 regular requests plus five snoozes. If
the historical limit still applies, the invariant is already broken; if it does
not, Lorvex is unnecessarily truncating without reporting it.

Release validation should measure the exact signed builds on every supported OS,
record pending requests after submitting more than the assumed limit, and make
all Lorvex notification namespaces participate in one observable budget.

### N9 — MEDIUM: DST-gap behavior contradicts the planner's documented contract

`HabitReminderOccurrencePlanner.fireInstant` says it returns `nil` when a local
wall time is unrepresentable during a DST gap. It constructs `DateComponents`
and calls `Calendar.date(from:)`, which is lenient.

A read-only Foundation probe on the review machine used
`America/Los_Angeles`, 2026-03-08 02:30. The current code path returned
2026-03-08 03:30 PDT; strict calendar matching returned `nil`. There is no
spring-gap or fall-back ambiguity test in the habit reminder planner suite.

Apple explicitly exposes matching and repeated-time policies for these cases.
Lorvex must choose and test one product rule:

- skip nonexistent local times;
- shift to the next valid time;
- or use another documented adjustment.

The current behavior happens to be “shift forward while claiming to skip.” A
fall-back 01:30 also needs an explicit first-versus-last occurrence decision.

### N10 — LOW-MEDIUM: scheduling does not follow Apple's current settings-first recommendation

After onboarding, each nonempty replacement calls `requestAuthorization` and
uses only its Boolean result. It does not first inspect the live authorization
status and alert/sound/badge settings or adapt content for provisional,
scheduled-summary, alert-disabled, or sound-disabled configurations.

The OS enforces the settings, so this is not a permission bypass. It does make
the scheduling report less truthful: “scheduled” does not mean the requested
banner/sound/badge presentation is possible. A settings-first preflight would
also avoid conflating denied authorization with request API failures and could
feed useful diagnostics on both platforms.

## Missing Tests and Release Evidence

The existing unit coverage is substantial, but it mainly verifies pure
candidate selection, cadence math, and store-to-scheduler calls. Before release,
add evidence for:

1. denied permission + elapsed reminder does not become delivered;
2. add failure after N successful requests preserves/retries an honest state;
3. budget truncation is persisted or surfaced and later requests refill;
4. 61+ task/habit requests plus 5+ snoozes on physical devices;
5. a weekly habit does not fire several already-armed same-period requests;
6. app not opened for more than 14 days;
7. concurrent old/new re-plans where the old pass resumes last;
8. timezone preference change on the writing device and via CloudKit;
9. travel after scheduling a task reminder;
10. spring-forward nonexistent and fall-back repeated local habit times;
11. transient task/habit read failure;
12. final signed iOS and macOS archive behavior under authorized, denied,
    provisional, alerts-off, sound-off, Focus, and Scheduled Summary settings.

## Freeze Recommendation

Do not call reminder delivery state or timezone semantics frozen until N1–N4
have explicit product contracts and tests. N5–N9 should be closed before App
Store release because they affect missed, duplicated, stale, or shifted reminders
without necessarily producing a visible app error.

The schema need not necessarily gain more columns, but the meanings of
`delivery_state`, `last_delivered_at`, `reminder_at`, `original_local_time`, and
`original_tz` must be decided now. Those meanings cross local persistence,
CloudKit payloads, MCP reads, notification scheduling, and future migrations.
