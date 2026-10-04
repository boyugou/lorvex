# Lorvex Apple — Surface Design Spec

This document defines what each Apple surface *should be*, the role it plays in
the product, and the bar for "done." Lorvex is an AI-first planner: the MCP host
is the primary **write** interface; the apps are the **read / review / today /
capture** surfaces with low-friction human actions. Every surface is scoped to
what that device is genuinely good at — not a uniform port of the macOS app.

The right-hand "Status" column reflects the honest audit: ✅ done,
◑ partial, ✗ missing.

---

## macOS — the command center

The full instrument panel. This is where a user reviews everything, plans the
day, works through Today's list, and drives keyboard-first workflows.

- Sidebar with the active workspaces: Today, Calendar, All Tasks, Review, and
  Habits (⌘1 to ⌘5), then the user's lists as task scopes. A pinned footer
  holds Memory (⌘6), which shows its selection there while open, above
  Settings. ✅ The Lists catalog has no sidebar row: lists are managed inline,
  with the catalog reached via ⌘K and the Navigate menu. Today's schedule and
  its tasks live inside Today, not as a separate workspace.
- Multi-window: detached list windows, dedicated workspace windows, and floating
  task "stickies". ✅
- Menu bar extra: today and the week ahead — date, a Today / Next 7 Days
  switch, quick-add, today's schedule, tasks, and habits with one-click
  complete and check-in, the agenda of the next seven days, and Open / Quit. ✅
- Full command menus + keyboard shortcuts. ✅
- Command Palette (⌘K): fuzzy command and navigation palette. ✅
- Settings: a sidebar of seven panes (General, Permissions, Calendar, Cloud
  Sync, Assistant, Data, Diagnostics), the current one named in the window's
  single toolbar row. Every control, action buttons included,
  sits at its row's trailing edge, and the copy that explains a control is the
  footer under its group. ✅
- Habit inspector, built from the task inspector's kit: the check-in ring with
  the name and encouragement typed in place; the period's standing (or, for a
  habit counted several times a day, a stepper for today's count) beside a "…"
  menu; Repeat, Reminder, and Goal rows edited in popovers; then Progress
  (streaks, check-ins, the 30-day share, the next milestone), History (the
  newest weeks of a year of days, filling the panel's width), and By Weekday
  (each weekday's share of its plan over twelve weeks, with the strongest and
  weakest day named). ✅
- Habit milestone waypoints (streak/count auto-ladder + optional user target) with
  a progress bar, a goal picker, and a celebration when a waypoint is crossed on
  both macOS and the iPhone/iPad habit surfaces. ✅
- List and habit drag reordering with persistence. ✅
- Global transient error toast. ✅
- Calendar week/list navigation with Today/This Week reset. ✅
- The Calendar day and week grids draw the day's timed tasks on the clock: each
  task's saved time sits in the day's lanes beside the calendar's events, in
  the accent tint (the block the clock is inside on today gets a heavier rail;
  a completed task's block fades and strikes through). A task drawn on the clock
  leaves the all-day strip, so it appears once. Every day's header carries its
  load against the day hours: a short bar filled by the share its meetings and
  tasks take, or "45 min over" in the overdue tint, with the full sentence
  ("4 hr 35 min planned, 10 hr 25 min free") as the tooltip and VoiceOver
  label — the same arithmetic as the iPhone Calendar strip and Today's
  overrun headline. In the week that holds today, the days before it step
  back: their day numbers and bars take the secondary style, as their
  weekdays already do, and every word stays legible. Today's blocks follow
  the day's saved times, so setting or clearing times on Today updates the
  grid without a reload. ✅
- The task inspector's "Do on" value reads the task's saved time when it has
  one ("Today at 9:45 AM"), so a timed task never shows a bare "+ When". ✅
- Today is one column holding the whole day, every task on it once; the
  window's trailing panel opens only for a selected task's detail. The column
  opens with the date and a line of facts ("5 tasks left · about 3 hr 30 min
  of work · 2 events"; the estimate drops out while the overbooked decision
  below states it), then the day's briefing when the assistant wrote one
  (`set_daily_briefing`), in the system face under the sparkles glyph — the
  same line the widgets show under their title. When the day holds more
  estimated work than the free working time left, one decision follows,
  offering to move the least urgent work to tomorrow. Then the Schedule:
  calendar events and timed tasks in time order, a red line where the clock
  sits, and the finished rows that open the day folded behind "N earlier".
  A timed task is a full task row with its time leading the metadata; an
  event row puts a bar in its calendar's color where a task has its circle.
  Suggested times, while one waits, stand above it. Then Tasks: the ones
  without a time, started first, then the canonical order; the label shows
  only under a schedule. Then the quick-add field, then Done, which folds on
  request. A row reveals its Start (or Pause) button and its Defer button on
  hover. Arrow keys follow the rows in that on-screen order. ✅
- ⇧⌘S starts or pauses the selected task; ⇧⌘D defers it to tomorrow. Both also
  reach from the row's hover buttons, its context menu, and the task detail's
  action row. ✅
- The toolbar's Suggest Times control lays today's open tasks into the free
  working time from the clock onward, around meetings: each task, in Today's
  order, takes the earliest free time that holds it, so a short task can fill
  a gap a longer one did not fit; a timed task already under way keeps its
  place, a task without an estimate takes 30 minutes, and a task whose time
  passed unfinished is placed again. The suggestion waits
  above the schedule until accepted or dismissed. Once any task has a time,
  the control becomes a split button whose menu holds Clear Times, which
  removes the day's times without moving any task off the day (⌘Z undoes it). ✅
- Workspace loading states for async panes. ✅
- Review writes the day as a calm page, read top to bottom as the day's close:
  the sentence, what moved forward, the due tasks still open (complete, open,
  or move to tomorrow, one at a time or all at once), the habits as they stood
  that day (checked in on that day), dot-scale ratings that name the chosen
  level, tomorrow's events and tasks while the review is of today, one note,
  and optional wins/blockers/learnings; and the week as a calm page: the week's
  sentence, what moved forward, the days written about (each opens its day),
  one decision about the task pushed off most (park it in Someday), the other
  pushed tasks, and a Someday line. Past days outside the write window read
  back on the same dot scales. ✅

## iPhone — capture, glance, today

Thumb-first. The phone is for *getting things in* and *staying on today*, not
deep editing. Tab-first with `NavigationStack`.

- Tab bar is Today · Calendar · Tasks · Review plus a round ＋ — the daily-driver
  surfaces are first-class, not buried. Today's list and its optional schedule
  live inside Today (interleaved with EventKit). ✅
- Calendar has three modes, and a switch between them keeps the day. Day and
  Week are one time grid that differs only in how many days it shows: Day
  (the default) is one day on a phone held upright, swiped by day under a
  week strip, and three days on a phone on its side; Week is the seven days
  of a week, swiped by week, and tapping a day's header opens that day in
  Day. Month is six weeks of days, swiped by month, each day marked with a
  dot per event and a ring per task, over the agenda of the chosen day; a
  swipe chooses the month's first day (today in today's month), and a task
  dragged from the agenda onto a day is planned there. Above every grid sits
  one row: the month (or the week's range) and a Today button that keeps its
  slot, hidden while it has nothing to do, so nothing moves when it appears.
  The toolbar holds only the Day/Week/Month control, centered, and New Event,
  which on a phone stands at the bar's leading edge so the control has room
  in every language. ✅
- The grid draws each day's timed tasks as blocks beside the events — a dashed
  accent outline with a ring that completes the task, a solid frame while the
  block is running. A block opens its task; the day's times themselves are
  suggested, saved, and cleared on Today. ✅
- Today is one list read top to bottom: the date and a line of facts, the
  day's briefing when the assistant wrote one (`set_daily_briefing`), in the
  system face under the sparkles glyph — the same line the widgets show under
  their title — and the day strip, which opens the schedule sheet (calendar
  holds and the day's timed tasks). Then the list: started tasks first, then
  the rest in the canonical order, with no section headers, the day's habits
  as rings, and Done, which folds on request. Every task row swipes and
  long-presses as it does anywhere in the app. ✅
- Habits are listed by what is open. A habit pinned to weekdays rests on
  its other days; a monthly habit appears from its day of the month until it
  is done; a times-per-week habit stays until the week's quota is met. Each
  leaves the Today habit grid, the Mac menu bar, the widgets and the watch
  when it is not open, unless it was checked in that day
  (`LorvexHabit.isListed(on:)`). The day reviews' habit grid and count take
  the habits that were due that day or checked in that day
  (`LorvexHabit.isReviewed(on:)`), so a day a habit was not due never reads as
  that habit missed. The Habits pages keep listing every habit. ✅
- The leading swipe starts or pauses a task; the trailing swipe defers it to
  tomorrow. Both also reach from the context menu and the task detail. ✅
- The schedule sheet's ⋯ menu holds Suggest Times, which lays today's open
  tasks into the free working time from the clock onward around meetings by
  the same rule as on macOS (each task, in Today's order, takes the earliest
  free time that holds it; a timed task already under way keeps its place, an
  estimate-less task takes 30 minutes, and a task whose time passed
  unfinished is placed again), and,
  once a task has a time, Clear Times, which asks for confirmation and then
  removes the day's times without moving any task off the day. A suggestion
  waits above the schedule with its own Use and Dismiss controls. ✅
- The calendar agenda's task rows state the day's time fact: the task's saved
  time when it is planned that day, else its estimate, plus "Due" on its due
  day; nothing else. ✅
- Quick capture is the round ＋ in the tab bar (a sheet), also raised from the
  task empty-state and ⌘N — capture is an action, not a tab. ✅
- Settings › Data Export exports the events from today through the next 30
  days as an `.ics` file (Export Calendar, then Share Calendar). ✅
- Task detail lists the set fields as rows (icon, name, value; the same
  order and symbols as the macOS inspector), each opening that one field's
  editor, and ends with an Add Detail menu for unset fields, a checklist, and
  a reminder; the checklist and reminder sections appear once they have an
  item. Edit sheet for title and notes; create sheets for
  task/list/habit/event. ✅
- Memory opens from a row on the Tasks tab home, alongside Lists; Settings
  opens from a toolbar button on Today. ✅
- Settings, diagnostics, privacy and acknowledgments, data export/import, and notification toggles. ✅
- A read-only "Recent Diagnostics" list on Settings over the `error_logs` ring:
  the crash/hang/CPU/disk rows the MetricKit subscriber persists, plus the
  `error`-level rows Lorvex writes itself. A row names its origin, and tapping
  one expands its full sanitized detail. Background failures — a Cloud Sync
  cycle above all — keep their technical detail out of the user-facing status
  line and route it here, so this is where they become diagnosable. ✅
- The Diagnostics summary reports the outbox's pending depth, how much of it has
  already failed an upload attempt, and the newest transport error still
  attached to an unsynced row. ✅

## iPadOS — the middle instrument

Keyboard- and pointer-aware; closer to macOS than iPhone. Should exploit the
larger canvas, not stretch the phone.

- The same tab bar as iPhone (Today, Calendar, Tasks, Review, +), drawn as the
  floating bar at the top of the window. ✅
- Today is the iPhone list in a readable column with the day's schedule
  standing beside it as a pane: the same timeline as the macOS pane (calendar
  holds and the day's timed tasks in one order, each row a time and a title,
  the running task's block tinted, rows the clock has cleared folded under
  "N earlier"), a proposed set of times above it while one waits, and the ⋯
  menu for Suggest Times and Clear Times. iPhone's schedule sheet is the same
  list under a title. ✅
- Tasks workspace uses a query-backed status/search browser; on iPad regular
  width it presents a persistent task list and detail pane instead of stretching
  the phone push flow. ✅
- Calendar's Day mode uses a regular-width agenda workspace: the 2- or 3-day
  time grid remains primary while a pinned agenda inspector lists the visible
  days that have something on them (and today whenever it is visible), with
  quick create/edit affordances. Week mode is the seven-day grid across the
  whole window. Month mode stands the chosen day's agenda beside a grid whose
  days name their events and tasks, as many as fit and then "+N"; in a
  window narrower than 860pt the agenda sits under the grid. ✅
- A list opens as the Tasks workspace scoped to it, the same screen whether
  the Tasks home, a deep link, Handoff, or a newly created list opens it: the
  list's description reads under its title, and a List Actions menu holds Edit
  List and Delete List (never for the Inbox; disabled, with the reason, while
  the list holds tasks). At regular width it keeps the task list beside the
  selected task's detail. A link to a list that no longer exists says List Not
  Found. ✅
- Habits uses a regular-width split workspace with the active habit catalog
  pinned beside progress metrics and completion/edit/delete controls. ✅
- Memory uses a regular-width split workspace with save controls and a complete
  memory catalog pinned beside selected content, metadata, and delete controls. ✅
- Hardware-keyboard shortcuts: ⌘R, ⌘N, ⌘1-⌘4 for the tabs in bar order, ⌘5 Habits, ⌘6 Memory,
  and ⌘, Settings, numbered as on the Mac. ✅
- **Bar for done:** keep tuning density, visual hierarchy, and pointer/keyboard
  ergonomics across the shipped iPad workspaces.

## Apple Watch — wrist glance + one-tap actions

Glanceable Today list and one-tap actions (complete, defer, capture).
Complications on the face.

- Root view: Today's list led by its lead task, then habits and capture as
  further pages; each task completes, starts or pauses, defers, or cancels. ✅
- Complication (circular/rectangular/inline/corner). ✅
- On device, the watch reads the App Group snapshot and forwards mutations to
  the phone through `WCSession`; the phone applies the write and publishes a
  fresh snapshot. ✅ Snapshot-only previews remain read-only by design.
- Phone-pushed snapshots write into the watch App Group and reload WidgetKit
  timelines immediately; complication providers also use periodic refresh
  policies when no push arrives. ✅
- The Digital Crown moves through the watch's pages — Today, then habits, then
  capture — and scrolls each page's list, so every task is reachable without
  hidden gestures. ✅
- The lead is the phone's: a task whose saved time contains the clock, else
  the first task on Today, so the wrist and Today's page agree on what leads.
  While the lead's time runs, it heads the page with its title, "Until" and
  the time it ends, and a ring that fills as the time passes and completes the
  task when tapped; every other task is a row whose circle completes it.
  Tapping a task's title opens its actions — Start or Pause, Tomorrow, and
  Cancel — forwarded to the phone over `WCSession`; a row's swipes reach the
  same actions, leading Start or Pause and trailing Tomorrow. With nothing
  left, the page says so and counts what got done. ✅
- Headless QA: `script/watch_sim_build.sh` builds the watch app for the
  simulator and `script/watch_sim_screenshots.sh <outdir> today habits
  capture actions` launches it with `-lorvexUIPreview`, a DEBUG sample day the
  app writes itself, so no paired phone has to push a replica (`actions` is
  Today with the lead task's actions sheet open, not a separate page). Run it
  on its own: under load the watch simulator misses launches. ✅

## Widgets — multiple kinds, configurable, interactive

A productivity app earns its home screen with more than one widget.

- Today widget (small, medium, large, and the Lock Screen families) in the
  calm page grammar. Small shows the lead task alone: its circle (the Done
  control, a filling ring while its time runs) beside the task's line, the
  task's title under them, and one quiet line for how many follow. Medium
  opens with the lead's circle and title over a line naming the widget and
  the task's time ("Today · Until 10:30 AM"), then the tasks after it in
  Today's order, each with its own circle on the ring's axis and its time or
  estimate at the trailing edge. Large opens with the widget's name and the
  assistant's briefing in its serif voice, then the lead and the tasks after
  it, and closes with how much got done today. When no task leads (nothing
  runs, is started, or is timed later today), every size names the widget,
  says how many tasks are left and the work they hold, and lists Today from
  its top; small names the top two. A widget configured with a list is
  titled with the list's name. Where a size cannot hold every row (a larger
  text size, a long briefing), the last rows give way to an "N more today"
  line that counts them. The Mac desktop widgets set the same layouts in
  macOS's larger text styles (`WidgetType`). The timeline carries an entry at every saved time's edge and every ten minutes
  inside one, so the ring advances between snapshot refreshes. The Lock
  Screen accessoryCircular fills the lead's ring and holds its minutes left
  while its time runs, else holds how many tasks are left, with a checkmark
  once nothing is left; accessoryRectangular shows a small ring beside the
  lead's title, its line, and the task after it; accessoryInline shows one
  line — the lead's short line, then its title. A snapshot that cannot be
  read shows an explicit unavailable glyph rather than stale data. ✅
- ControlWidget (iOS and macOS) names the task at the top of Today — a
  task whose time is running, else the first task on Today — shows "All
  clear" with nothing left, and opens the app to Today when tapped. ✅
- Today, Habits/streak, and daily-progress widgets, with `accessoryCircular`
  gauges and deep links. ✅ The Today widget's `AppIntentConfiguration` takes
  an optional list that narrows it to that list's tasks; filtered widgets use
  list-scoped counts. ✅

## Menu bar (macOS) — Today at a glance

- A `.window`-style menu-bar extra. Its top stays put: the date with a
  Today / Next 7 Days switch (remembered across openings), the day's sentence,
  and a one-line quick-add (Return creates an inbox task). Under it a body that
  grows with its content and scrolls past about 440pt, which keeps the panel
  near 600pt tall. ✅
- Today reads the same `LorvexCalmToday` value and schedule as the Today
  workspace: the task happening now with its ring (the ring completes it, the
  title opens it in the main window) and its clock line, then Schedule (the
  all-day events, the events not yet over, and the open timed tasks, by
  start), Overdue and Tasks (the tasks without a time), and Habits, each habit
  with a ring in its color that checks it in (a habit counted several times a
  day adds one per click and is cleared only in the Habits workspace), then
  "N done today". An event row (a bar in the calendar's color, the title, the
  time) opens the event in Today's inspector. Section labels show only when
  more than one section is listed. When nothing is left on the day, the sun's
  arc shows where the day is. ✅
- Next 7 Days lists each of the seven days after today that has something on
  it — "Tomorrow", then the spelled-out date — with its events (the same rows,
  which open the event on its day in the Calendar) and its open scheduled
  tasks (ring and title, which opens the task in Tasks). A free week reads
  "Nothing planned for the next 7 days." ✅
- The footer holds Open Lorvex and Quit. The status-item glyph carries the
  due-today/overdue count. ✅

## CarPlay — hands-free Today

Zero text entry. The car screen shows Today the way the Today page does, read
against the clock: the lead task first when one leads, then the rest of
Today's list in Today's order. A row tap opens a short action sheet — Done, Tomorrow instead,
Open on iPhone (Handoff) — so a single tap can never accidentally close a
task. Siri-driven voice intents are a tracked follow-up.

**Status:** Code present, provisioning required. The controller and scene
delegate are implemented and fully tested; the CarPlay scene is silently ignored
at runtime until Apple approves the CarPlay entitlement for the Lorvex App ID.
No further code changes are needed to activate CarPlay once the entitlement
is granted and merged into the iOS app target.

### What the driver sees

One `CPListTemplate` titled Today, with one section: Today's list in Today's
order, the lead task first when one leads.

| Row state | Detail |
|---|---|
| A saved time is running | "Until 11:00 AM" |
| Timed, not yet running | "9:00 AM – 10:00 AM" |
| Overdue | "Overdue" |
| Started, untimed | "Started" or "Started · about 25 min" |
| Neither, with an estimate | "About 25 min" |

The lead task is a task whose saved time is running, else a started task,
else the task whose saved time starts next; otherwise Today's order stands. Every row carries a state glyph with the meaning colors have
everywhere else in Lorvex: blue once the task is started, a red exclamation
mark when it is overdue, grey otherwise. Rows are capped to
`CPListTemplate.maximumItemCount`, so the lead row always shows and the
list's tail is what gets cut. A clear day uses the template's empty view
("All clear" / "Nothing left for today.") rather than a fake row. The list
re-renders at every minute boundary so a running time's "Until" detail and
the lead row follow the clock without a database read, and refreshes
(debounced 2 s) after every local database change.

### What is built

- `CarPlayTaskListController` (Sources/LorvexCarPlay/) — platform-independent
  controller (no CarPlay import). `refresh()` reads Today's list and the day's
  times through `LorvexCoreServicing` into `todayRows`, each task carrying its
  time on the day when the schedule gives it one; `rows` orders them with the
  lead task first, read against an injectable clock (`now`) in the day's
  timezone. Mutations: `complete(id:)` and `deferToTomorrow(id:)` (defers to
  the local next day, UTC-anchored per `PlannedDayBridge`). `CarPlayRowCopy
  .detail(for:nowMinutes:)` produces each row's second line from the CarPlay
  catalog. Fully tested headlessly (`CarPlayTaskListControllerTests`).
- `LorvexCarPlaySceneDelegate` (Sources/LorvexCarPlay/) — `CPTemplateApplicationSceneDelegate`
  presenting the list above plus a retry/error section when a load fails. A
  row tap presents a `CPActionSheetTemplate` (Done / Tomorrow instead / Open
  on iPhone / Cancel) whose message is the row's clock detail, rather than
  mutating on tap. Failures map to driver-safe retry text and refresh the
  template. Each CarPlay callback hops to the main actor explicitly because
  `CPListItem`/`CPAlertAction` handlers are not `@MainActor`-isolated. Guarded
  by `#if canImport(CarPlay) && os(iOS)`, so only the iOS build
  (`script/ios_sim_build.sh`) compiles it; the source-level copy check is
  `CarPlayLocalizationSourceTests`.
- `Config/LorvexCarPlay.entitlements` — entitlement template; see provisioning
  note below.
- `Config/LorvexMobileApp-Info.plist` — documents the `CPSupportsTemplateApplicationScene`
  and `UIApplicationSceneManifest` keys (in a comment block); uncomment once
  the entitlement is approved.
- `script/carplay_sim_enable.sh` — makes a simulator build CarPlay-capable
  without Apple's approval and installs it on the iPhone simulator. It builds
  with `LORVEX_IOS_CARPLAY=1` (`script/ios_sim_build.sh` then passes
  `Config/CarPlaySimulator.xcconfig`, which signs only the `LorvexMobileApp`
  target with `Config/LorvexMobileAppCarPlaySimulator.entitlements`), adds the
  scene manifest and `CPSupportsTemplateApplicationScene` to the built app,
  and re-signs it ad hoc with the empty entitlement dictionary Xcode uses for
  simulator apps. The entitlement has to come from the build: a simulator
  app's entitlements are read from the binary's `__TEXT,__entitlements`
  section, and an entitlement placed inside the code signature instead makes
  launchd refuse to spawn the process. The CarPlay display itself is opened
  from Simulator.app (I/O → External Displays → CarPlay); a machine whose
  Xcode ships without Simulator.app can verify the scene only through the
  controller tests and the iOS build.

### Provisioning checklist (Apple approval required)

1. At developer.apple.com → Certificates, Identifiers & Profiles → App ID
   `com.lorvex.apple.mobile` → Additional Capabilities, request CarPlay
   (choose the category Apple approves — Navigation / Maps, or General).
2. Once approved, merge `Config/LorvexCarPlay.entitlements` keys into
   `Config/LorvexMobileApp.entitlements`.
3. Uncomment the `CPSupportsTemplateApplicationScene` block in
   `Config/LorvexMobileApp-Info.plist`.
4. Set `UISceneDelegateClassName` to
   `LorvexCarPlay.LorvexCarPlaySceneDelegate` (module-qualified) or expose
   the class into the app module.
5. Rebuild and re-sign with an approved provisioning profile.

Without step 1 the CarPlay scene is silently ignored. The code compiles and
all tests pass without the entitlement.

### SiriKit voice path (follow-up, not built)

Wire `INCompleteTaskListIntentHandling` in a separate `LorvexSiriIntents` app
extension target. The intent handler delegates to `CarPlayTaskListController`
to resolve tasks by voice-matched title and calls `complete(id:)`. Phrases:
"complete [task name] in Lorvex", "what's next in Lorvex". Tracked here; not
blocked by the CarPlay entitlement.

## Notifications & permissions — clear request, denied fallback, escape hatch

- Reminder scheduling + rich notification actions (complete/defer/snooze) on
  macOS and iOS. ✅ Rich actions route complete/defer/snooze on both app
  shells. ✅
- Onboarding permission steps for Calendar/Notifications. ✅
- Permissions status panel with denied-state Open Settings recovery. ✅
- App-icon badge for overdue/due-today tasks on macOS and iOS app
  entry points. ✅
- `EKEventStoreChanged` observer refreshes external calendar edits without a
  manual refresh. ✅

## EventKit — macOS write-back, read-only ingest elsewhere

- Calendar import (read), Lorvex-native calendar create, and ICS export on every
  platform. ✅
- **Write-back to the system Calendar is macOS-only.** On macOS, Lorvex-
  originated calendar events are written into a dedicated Lorvex EventKit
  calendar and create/update/delete propagate back to the matching `EKEvent`.
  iPhone/iPad are read-only: they ingest the system calendar for
  display and planning and create Lorvex-native events only — they never write
  to Apple Calendar. ✅
- External provider-owned EventKit events remain read-only mirrors on every
  platform by design. ✅
- The external EventKit mirror (`provider_calendar_events`) is a device-local,
  rebuildable cache and is never CloudKit-synced — the system Calendar syncs
  itself. ✅
- `EKEventStoreChanged` observer refreshes the local mirror. ✅
- EventKit ingest honors persisted per-calendar include/exclude filters before
  provider events enter the local mirror. ✅
- Calendar settings expose a native calendar picker with all-except
  and only-selected modes for EventKit mirroring. ✅

### Field-fidelity limits (current behavior, not overclaimed)

- **Recurrence:** macOS ingest maps only an event's first recurrence rule, and
  write-back emits a single recurrence rule; iPhone/iPad ingest does
  not map recurrence rules at all (recurring external events mirror as their
  individual occurrences).
- **Attendees:** participants without a parseable email address are dropped
  (the attendee projection keys on email).
- **Privacy tier:** each device defaults to Busy Only — provider events
  contribute occupancy for planning without storing or showing event detail.
  Settings exposes Off / Busy Only / Full Details explicitly; Full Details is
  never selected implicitly. The tier applies to Lorvex and connected
  assistants on that device. It is device-local, while the per-calendar filter
  separately chooses which Apple calendars are mirrored.

---

## Build priority (highest user-visible impact first)

1. **Apple Watch polish** — writes and live snapshot push are shipped; continue
   improving glance navigation and on-device ergonomics.
2. **iPhone/iPad full workspace reach** — shipped; continue polishing iPad
   workspace-specific layouts and keyboard ergonomics.
3. **Widgets** — Today + Habits + progress widgets, configurable, interactive
   complete.
4. **CarPlay** — new surface.
5. **UI/UX polish** — loading states, error toast, reordering, calendar date
   nav, habit streaks.
6. **Notifications/permissions** — denied-state recovery, iOS scheduling parity,
   badge.

---

## CloudKit two-way sync — production requirements

The sync layer is implemented and settings-driven (Settings > iCloud Sync Mode).
The following remain as external provisioning or on-device verification tasks
and cannot be tested in the local simulator:

### CloudKit container provisioning (App Store Connect)

- Container `iCloud.com.lorvex.apple` must be registered and associated with
  the App ID before the `.live` mode can write to it.
- Deploy the checked-in `cloudkit/schema.ckdb` template. The app reads and
  writes one record type, `LorvexEntity`, which carries encrypted envelope
  fields (`entity_type`, `entity_id`, `operation`, `version`,
  `payload_schema_version`, `payload`, `device_id`). The template also
  declares record types the app neither reads nor writes; CloudKit never
  removes record types deployed to Production, so they stay declared.
- Development may learn record types while exercising a provisioned build, but
  an App Store build cannot rely on runtime schema creation. Promote the tested
  Development schema to Production in CloudKit Console before submission and
  retain the exported Production schema as release evidence.
- Domain records live in one custom zone named `Lorvex` in the private
  database. `CKSyncEngine` saves the zone before the first record batch; no
  zone is provisioned manually.

### Entitlements and capabilities

- Production macOS builds targeting iCloud sync must use
  `LorvexAppleCloudKitAppStore.entitlements` (see `docs/DISTRIBUTION.md`), which
  declares the CloudKit container, `Production` iCloud environment, and
  production APS environment. `LorvexAppleCloudKit.entitlements` is the
  development-only on-device template and must never be used for the final
  Developer ID DMG or Mac App Store candidate.
- The Push Notifications capability is required for silent-push delivery of
  remote-change notifications (APNs). Without it, the engine's push
  subscription (`lorvex-sync-engine`) is registered but no pushes arrive; sync
  then runs on launch, foreground activation, and local writes.

### What the local simulator validates

- `CloudSyncMode` persistence and factory wiring: verified by tests.
- `CloudSyncStatusReport` aggregation: verified by tests.
- HLC comparator correctness: verified by tests.
- Tombstone encoder/decoder/applicator round-trip: verified by tests.
- `CloudSyncController` event handling, driven by simulated `CKSyncEngine`
  events: fetched records, sent batches with each error class, account
  changes, zone deletions, apply failures, and replays after a crash between
  steps: verified by tests.
- Settings import with sync live: one best-effort sync pass, then the import,
  then a refresh, with the imported rows uploading through the outbox:
  verified by macOS/Mobile composition tests.
- Record encoding and decoding: verified by existing tests.

### Entity coverage

`CloudSyncController` sends the Swift sync outbox through `CKSyncEngine` and
applies inbound envelopes through the same `Apply.applyEnvelope` registry used
by the core sync tests. Core planning entities (`task`, `list`, `habit`,
`calendar_event`, `memory`) have outbound upsert/delete enqueue coverage and
registered inbound appliers; child rows and edges travel either as independent
sync entities or as embedded aggregate payloads.
`script/verify_cloudkit_sync_readiness.py` checks that this core entity
coverage stays wired.

Production live sync remains gated on Apple Developer provisioning: the app ID
must own the `iCloud.com.lorvex.apple` container and the CloudKit schema must be
deployed before real private-database writes can succeed.
