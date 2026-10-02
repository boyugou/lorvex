# Apple UX Polish — Design Rationale

Why the non-obvious product, visual, and interaction choices on the Apple
surfaces are what they are. It complements two neighbours:
[`SURFACE_DESIGN.md`](../SURFACE_DESIGN.md) states the intended end state per
platform, and [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) states the color, type, and
component contract. This file holds the reasoning that neither of those records
— the judgment calls a reader would otherwise have to reconstruct from a diff.

It is not a changelog. Shipped work lives in git history. The open, evidence
backed, code-level findings live in [`POLISH_BACKLOG.md`](POLISH_BACKLOG.md),
and as-built layout wireframes in [`wireframes/`](wireframes/INDEX.md).

## Priorities

1. **macOS and iOS** — the two primary surfaces; polish these first.
2. **iPadOS** — iPad-native design (principles below), never the macOS layout
   ported verbatim.
3. watchOS, CarPlay, and widgets after the above.

## iPad-native design principles

iPad differs from a Mac in ways the layout has to honor:

- **Orientation is first-class.** iPad rotates between portrait and landscape at
  runtime. Portrait is much narrower, so a Mac-style sidebar, content list, and
  detail (three columns) is cramped there and should collapse — the sidebar as
  an overlay through `.automatic` column visibility, or a two-column list and
  detail — while landscape can afford more columns. Verify both orientations
  rather than assuming a fixed column count.
- **Size class is not device.** Split View, Slide Over, and Stage Manager set
  `horizontalSizeClass` to `.compact` at runtime even on a large iPad. Today
  switches between a schedule sheet (compact) and a standing schedule pane
  (regular) on the size class, and the list-and-detail workspaces and the
  Calendar measure the actual width, so a half-screen iPad window degrades
  gracefully to the phone layout. Keep every iPad layout driven by size class or
  width, never by device idiom.
- **Dual input.** Touch targets stay at least 44 points while pointer
  affordances (hover highlights, `.pointerStyle`, context menus) and hardware
  keyboard shortcuts coexist. Density gained by dropping touch ergonomics is not
  worth having.
- **Canvas, not stretch.** Spend the extra width on genuinely useful secondary
  content — list and detail, inspectors — not on a stretched single column.
- **Drag and drop plus multi-select** are expected iPad idioms for a task app,
  which is why Tasks, Habits, Lists, and Memory each carry a selection mode with
  a batch action bar rather than row-at-a-time actions alone.

## Standing decisions

### Regular width mirrors the phone, laid out for the width

At regular width the Today page keeps the phone's decomposition of the day (the
briefing, the task list, Habits) as a capped column under the same title and
date subtitle, and stands the schedule beside it instead of behind the day
strip. The iPad also uses the phone's tab bar, so a destination is reached the
same way on both. Two different decompositions of the same day made the
product feel like two apps.

### Blocking spinners are for the first load only

A full-view spinner on every refresh fights the list's own `.refreshable`
indicator, so the blocking state is gated on the first load — the store is
loading *and* the snapshot is still empty. Later refreshes keep content on
screen and animate the native indicator. The first-load skeleton is shaped like
the surface it stands in for, so the layout does not jump when real content
arrives.

### A batch action is offered only when the core would accept it

Lists can be batch-deleted only when every selected list is empty, because the
core rejects deleting a list that still holds tasks. Memory's batch delete
enables only when every selected entry is AI-owned, and the store repeats that
guard before calling the core, so the human-memory boundary holds even if UI
state is stale. An action that opens a destructive confirmation and then fails
is worse than an action that is visibly unavailable.

### Reversible removal is one tap; erasing history always asks

Archiving a habit takes it off the active list, Today, the widgets, and its
reminders but keeps its completion history, and the archived section below the
catalog restores it with one tap. Archive therefore asks for no confirmation
and is drawn untinted (the system's neutral gray in a swipe action), not in a
color that implies loss. Deleting erases the history, so Delete is red and
always confirmed, including for a habit that is already archived. On a pushed
habit detail page both actions pop the page before the mutation lands: the page
slides away intact and the row then leaves the list beneath it, which shows the
user where the habit went. The archived section is folded by default and counts
its habits only while folded, because an open section's rows are their own
count.

### In-flight mutations are gated in the store, not in the view

Schedule mutations, habit reminders, calendar subscriptions, and task mutations all
reject a duplicate submission while one async mutation is active, and the
control disables off that same state so the rejected tap has visible feedback.
The guard lives in the store because menu shortcuts, quick actions, and the
workspace control all reach the same mutation. Task mutations track in-flight
task IDs rather than one global flag, so a mutation on one row does not block a
tap on another.

### The Today inspector closes when its task leaves today

A task the user completes, defers, or replans leaves today's pool, and
`reconcileSelectedTaskAfterRefresh` drops the inspector selection with it rather
than holding the pane open on a row the surface no longer lists. The `.tasks`
surface keeps a loaded-but-off-pool selection (a deep link or Spotlight hit
opens a task the workspace never listed) and the calendar keeps a tap-selection
while the task is still scheduled in the window; Today deliberately makes
neither exemption, and `appStoreRefreshClearsStaleTodayInspectorSelection` pins
that by loading the task's record first and still expecting the selection to
clear.

The cost is that the pane closes at the next refresh rather than at the moment
of the action, so completing a task from the Today inspector leaves it open
until a sync lands. The task's own actions are not lost with it: complete
registers its reopen against the captured id, so ⌘Z still reopens the task after
the pane has closed.

### A tip must say something the surface does not

A TipKit popover on a workspace the user opens every day is a recurring
interruption, and TipKit only records a tip as dismissed when the close button
itself is used — walking away re-shows it on the next visit. That is the
default, not a defect, so a tip earns its place only by carrying information the
surface cannot. The Reviews workspace tip did not: its title repeated the
section header below it and its body was a general sentence about syncing, while
the panel already asks "What changed today?" and answers the bar-lowering
question with "One honest paragraph is enough." It also covered the evidence
column. The Assistant settings page carries its one non-deducible sentence,
"Lorvex is built for an assistant to do most of the work", in its own blurb
rather than in a tip: a popover that repeats the paragraph beneath it while
covering the rows beside it adds nothing. No tips remain, so neither app
configures TipKit.

### A placeholder asks, a subtitle nudges

A panel header already names its field, so an editor placeholder that repeats it
spends the one line a writer reads before typing on something they just read.
The question goes in the placeholder ("What moved forward?") and the subtitle
carries the encouragement that lowers the bar to starting ("Small ones count.").
The accessibility label keeps the header word, because VoiceOver announces a
field by its name and not by its prompt.

### Data-integrity invariants behind UI actions

These are the non-obvious ones, worth stating because a plausible-looking
simplification breaks each:

- **A permanent-delete tombstone must be atomic with the delete.** The
  pre-delete payload snapshot reader throws; guarding it with `try?` silently
  nils it on a transient read failure and deletes the row with no tombstone,
  which resurrects it on peers. Catch `EnqueueError.entityNotFound` and map it
  to nil for the benign-absent case, and let every other error propagate so the
  write transaction rolls delete and tombstone back together.
- **A one-shot flag is set only after the read it gates succeeds.** Flagging
  `seedIfNeeded` before its `MAX(version)` read loses the HLC monotonicity
  backstop across a transient failure.
- **A best-effort failure the user would care about is surfaced.** An EventKit
  access-mode preference that fails to save is reported through the calendar
  import report rather than swallowed.
- **A row whose creation instant drives a statistic carries it through the
  archive.** A habit's 30-day adherence window opens on its creation day, so a
  restore that stamped the row with the import instant would score every
  restored habit over a single day and show 100% beside a long streak read from
  the same archive. `ExportHabit.createdAt` is optional: an archive without it
  still restores, at the import instant.

### MCP read-tool fencing is per tool, and claimed only where applied

A read tool's catalog description may not advertise prompt-injection fencing
unless its handler actually applies `SecurityFencing.fenceValue`. Fencing
changes the output every MCP client sees, so it is adopted tool by tool rather
than blanket-enabled, and the catalog text follows the handler. Rule 6 in
[`../../CLAUDE.md`](../../CLAUDE.md) is the binding contract; the per-tool
policy lives in each domain's `*ToolDefinitions.swift`.

### A background failure the user cannot see is a failure nobody can diagnose

Generic user-facing copy for a background failure is right — "Something went
wrong. Please try again." is what a Cloud Sync error should say in Settings,
because CloudKit's own wording is implementation detail and not validated user
copy. What is not right is that being the *only* thing anyone can read. A
release build routes the real detail to `error_logs` and logs it to OSLog as
private, so a queue stuck behind a rejected push looked identical to one merely
waiting for a cycle, and neither the user nor the developer could tell which.

Settings → Diagnostics is the surface that answers it, and it answers in the
transport's own words: the failure feed carries every `error`-level row Lorvex
logged, not only the crashes the system reported, each labeled with its origin
and expandable to its full sanitized detail; and the summary reports how much of
the outbox has already failed an attempt alongside the newest error still
attached to an unsynced row. The split is deliberate — the user-facing line
stays generic, the technical surface stays exact — and it is what makes a
screenshot of Diagnostics a usable bug report.

The feed keeps `error` rows by level rather than by an allowlist of sources: an
allowlist stops covering each new subsystem that starts logging, and would go
quiet exactly where the panel was needed.

## Wireframes and the analysis method

For each surface there is an ASCII wireframe of the as-built layout, the data
each region shows, and notes on the ideal interaction. Writing the layout out in
text documents the current design and gives a spatial frame for reasoning about
changes without a running device. The wireframes live in
[`wireframes/`](wireframes/INDEX.md), each region citing the file and type that
renders it. Three surfaces are captured — the macOS shell, the macOS calendar
week grid, and the iPhone tab shell — and the index lists the rest.

Pixel-level judgment still happens on a screenshot, not in the head: capture the
affected screens headlessly, review them critically, and note here anything the
capture revised.

## Open design questions

Items that need on-device visual judgment rather than a code pinpoint. The
code-level open findings are in [`POLISH_BACKLOG.md`](POLISH_BACKLOG.md).

- **Density retune (macOS and iOS).** Whether dense secondary rows should move
  up from `tertiaryText` toward `secondaryText`, per the calmer-and-larger
  philosophy. The token tier is centralized, so the change is cheap; the call
  needs an on-device read.
- **Dynamic Type for the remaining fixed-point fonts.** A few sites are still
  fixed — the macOS calendar block at 9 points, the macOS onboarding hero glyph
  — and a long tail of raw `.font(...)` calls still bypasses the `Typography`
  tokens.
- **Per-platform audits not yet run:** watchOS, CarPlay, and widgets,
  each of which needs the device.
- **Calendar MCP metadata parity.** Create and update carry recurrence,
  timezone, URL, color, event type, person name, and attendees; scoped recurring
  edits and deletes plus batch-create dry runs remain.

## Handoff notes

**Hotspot line cap.** `script/verify_hotspots.py` caps every app and core Swift
source file at 800 lines, with three cohesive core files grandfathered at a
bounded higher ceiling. It is a god-file guardrail, not a fragmentation nudge:
never split a cohesive file or trim explanatory comments just to satisfy it.

**Exported symbols without callers.** `core/` exports parity primitives that
have no static caller inside this repo and are retained deliberately; see
[`../../core/PORT_STATUS.md`](../../core/PORT_STATUS.md) before treating any of
them as dead code.
