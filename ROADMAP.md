# Roadmap

Organized by lane: **Apple** (`apps/apple`) and **Shared** (`schema/`, `spec/`,
`cloudkit/`). The Apple core port has landed; its decision record is
`docs/decisions/pure-swift-core-port.md`.

Apple Swift is the only shipping line: macOS App Store, direct macOS builds,
iOS, iPadOS, watchOS, WidgetKit, App Intents, EventKit, CloudKit/iCloud, and
other Apple-native capabilities. visionOS is out of scope for now. The former
cross-platform Tauri line was removed from this repository on 2026-09-17.

## Next up

### Apple (Swift)
- **Daily workflows, in priority order (Mac product review, 2026-11-20).**
  1. Daily Review now opens on the entry and includes every open task planned
     for or due on the reviewed day. Mac and iPhone offer individual date
     changes, Someday, counted bulk moves across folded rows and undo.
     Available in [TestFlight build 146](docs/releases/1.0.0-146.md).
     Follow up on real use: can someone finish an evening review and trust
     next morning's plan without reopening the task list?
  2. Mac Today now brings the current task and a Start or Continue action
     below the briefing. Continue opens the task's notes and checklist.
     The task shows the time until the next event. A conflicting upcoming
     task stays in the schedule and names the calendar event. Available in
     [TestFlight build 147](docs/releases/1.0.0-147.md). Evaluate the return
     from a meeting during daily use, including days without time slots.
  3. Today now supports ordered morning and evening routines on Mac, iPhone,
     and iPad. Each routine opens around its chosen start time and can be
     folded or opened manually. Counted habits and excused days share their
     records with Habits and Daily Review. Available in
     [TestFlight build 148](docs/releases/1.0.0-148.md). Evaluate whether the two-hour
     window suits actual mornings and evenings, especially with unusual
     schedules or a habit that belongs to both routines.
  4. Weekly Review opens on the journal, including entries with no summary.
     Filter the week by wins, blockers or learnings. Plan a dated task from
     one blocker and find it in Calendar. Available in
     [TestFlight build 149](docs/releases/1.0.0-149.md).
  5. Tasks now show the day set aside for work and the deadline. Mobile
     Scheduled finds a Weekly Review follow-up even when it has only a
     planned day. Collection counts and searches cover every page.
     [TestFlight and Mac download, build 150](docs/releases/1.0.0-150.md).
  6. Past daily entries open with their saved writing and ratings on iPhone,
     iPad and Mac. From the weekly journal you can read yesterday's blocker
     and return to today's editor. Verified with a saved note across relaunch.
     [TestFlight build 151](docs/releases/1.0.0-151.md).
  7. A first task entered on Welcome appears on Today. People with an
     existing plan can choose iCloud sync directly. Skipping opens the
     workspace, with the same task field on an empty mobile Today.
     [TestFlight build 152](docs/releases/1.0.0-152.md).
  8. Quick capture lets people keep a title containing a date or another
     recognized detail. An iPhone walkthrough saved the movie name “Watch The
     Day After Tomorrow” and scheduled a second task for tomorrow. Mac quick
     capture respects the list or Today where the task was entered.
     [TestFlight and Mac download, build 155](docs/releases/1.0.0-155.md).
  9. A mobile quick capture now confirms its title and destination. Open a
     single task or the just-saved batch on the current tab. An iOS 27
     VoiceOver walkthrough read the saved title and list, reached Open in the
     next step and opened the task after the usual timeout. Verified on iPhone
     and iPad mini. [TestFlight build 156](docs/releases/1.0.0-156.md).
  10. Active tasks now show **When → Set Date** at the top of their properties.
      iPhone and iPad put Share, Cancel Task and Delete Permanently in More.
      Mac inspector and persistence checks, plus iPhone and narrow iPad
      walkthroughs verified scheduling with a separate deadline.
      [TestFlight and Mac download, build 157](docs/releases/1.0.0-157.md).
  11. Mac workspace navigation keeps the native search field on its window.
      The sample-data tour now completes all 64 views, including the
      Calendar → Today → Calendar path where AppKit previously threw a
      duplicate search-item exception. Rapid workspace switches, ⌘F, typing,
      Escape and scoped prompts passed in the regular window.
      [Build 158](docs/releases/1.0.0-158.md).
  12. Tomorrow in Daily Review shares Today's chronological order on Mac,
      iPhone and iPad. An iPhone walkthrough opened a morning task between an
      all-day event and an evening meeting and returned to the saved journal.
      [Build 158](docs/releases/1.0.0-158.md).
  13. Two mobile rating menus below the journal show the saved feeling and
      energy. They stack at larger text sizes. Native iPhone and iPad mini
      walkthroughs checked setting, clearing, returning to saved values and
      VoiceOver reading order. A second edit during a save survives a day
      switch. [TestFlight build 159](docs/releases/1.0.0-159.md).
      [Build 160](docs/releases/1.0.0-160.md) aligns the controls and saves
      the mobile journal while its keyboard stays open. The note shows when
      the write has completed.
  14. An empty Today on iPhone and iPad offers a searchable choice of existing,
      visible work without a planned day. Choosing keeps the task’s list and
      deadline. Cancel and Undo were verified on both devices, as was opening
      the saved task from Today after relaunch.
      [Build 161](docs/releases/1.0.0-161.md).
  15. Compact Today names the current or next appointment. Its title opens
      the event directly. On wide iPad the agenda remains beside the tasks.
      Verified on a two-meeting morning, during a meeting, after the last
      event, and on an all-day schedule. [Build 162](docs/releases/1.0.0-162.md).
  16. iPhone and iPad can write a blank recent day or edit a past entry from
      the weekly journal. Mac and mobile save independent journal fields
      against the latest local row. Verified a note edit after another writer
      saved a win. [Build 163](docs/releases/1.0.0-163.md).
  17. Mac Daily Review previews tomorrow’s work before moving a selection.
      It counts timed commitments within working hours, merges overlaps,
      and identifies unestimated tasks. Verified a partial move, Cancel and
      Undo in the native window and an agenda with more than fifty tasks.
      [Build 164](docs/releases/1.0.0-164.md).
  18. iPhone and iPad Daily Review now preview a selection against tomorrow’s
      existing work and appointments. Cancel, subset moves, Undo, and large
      text passed native walkthroughs. [Build 165](docs/releases/1.0.0-165.md).
  19. An overbooked Today previews the effect on both working days. Users
      can keep a suggested task, choose an alternative and undo the move.
      Mobile cold launch now reads the saved workday after storage is ready.
      [Build 166](docs/releases/1.0.0-166.md).
  20. Mobile Today can start work in its scheduled time and resume a started
      task after a meeting. The time until the next meeting opens the event.
      The current day stays available when browsing another calendar week.
      [Build 167](docs/releases/1.0.0-167.md).
  21. A started task on iPhone and iPad puts its remaining checklist just below
      the title. Completed steps can be reopened and the next step carries
      back to Today. Verified alongside a deadline edit, an app relaunch, and
      Chinese at the largest text size. [Build 168](docs/releases/1.0.0-168.md).
  22. Mac Review finds a phrase across journal entries and opens the day it
      came from. Returning restores the phrase, loaded pages, and position.
      [Build 169](docs/releases/1.0.0-169.md).
  23. Review on iPhone and iPad finds writing across dated entries. Reading
      preserves the working day, query and scroll position. Edit opens the
      correct recent day. [Build 170](docs/releases/1.0.0-170.md).
  24. Keep the Mac journal open while inspecting a task. Currently a title in
      Still open or Tomorrow switches the workspace to All Tasks. Someone
      double-checking a deadline should be able to close the task and carry on
      with the same entry. Verify a pending note and the reading position
      after editing a task in both a wide and a narrow window.
- Platform adaptation sprint (owner, 2026-11-16; queued after the current UX
  fixes): iPhone Duo and useful capabilities in macOS 27.2 and newer iOS
  releases. Begin with Apple's [Duo preparation guide](https://developer.apple.com/iphone-duo/prepare/),
  [Duo design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo),
  and [macOS SDK release notes](https://developer.apple.com/documentation/macos-release-notes).
  Today now sizes its columns to the available task width and text size.
  Rotating an iPad mini kept the schedule sheet open, preserved the selected
  task, and let an unsaved title survive the round trip. Available in
  [build 153](docs/releases/1.0.0-153.md).
  The mobile Week agenda now gives each appointment and task a readable row
  and keeps the same week when switching back to the time grid. The largest
  text size opens the agenda on the focused day. Overlapping appointments,
  an empty week, rotation with a draft and the handoff to Day were checked
  on iPad mini. Available in [build 154](docs/releases/1.0.0-154.md).
  Journal search and recent-day editing passed on the outer display of the
  iPhone Duo simulator in dark mode. [Build 170](docs/releases/1.0.0-170.md).
  Validate continuity across displays, folding, rotation, Split View, side-mounted
  navigation and toolbars, and reserved regions. Keep the current navigation,
  selection, scroll position, and unsaved draft through layout changes. Cover
  Today, calendar grids, task details, Review, capture, and settings, with large
  text and light/dark appearances. Then evaluate system integration changes
  against specific user benefits and the supported deployment and SDK/compiler
  floors; existing integrations need a compatibility pass before adopting new APIs. Record
  device/simulator evidence and prioritize improvements that simplify an
  everyday action.
- Calendar duplicate display (shipped 2026-11-16 in TestFlight and GitHub build
  145; [release record](docs/releases/1.0.0-145.md)): conservative,
  configurable display grouping, preserving every source event. Levels: off,
  strict (default), and matching title plus exact start/end times (explicit
  opt-in; may ignore location and other detail differences). Strict also
  compares location, notes, link, organizer, attendees and response states,
  and recurrence context, without treating calendar color as event content.
  Require distinct, known origin calendars and full event details; redacted
  busy blocks or unknown provenance do not prove equality. Compare timed
  occurrences by exact instants, keep floating clocks distinct from fixed
  instants, and compare all-day events by civil date spans. Never fuzzy-match
  names or merge overlapping time ranges. Keep each copy accessible, make
  edit targets explicit, and preserve all storage and synchronization records.
  The provider cache now retains full-detail origin metadata; imported keys
  distinguish copies sharing one server UID across calendars. Migration 006
  rebuilds only the disposable device mirror, keeping owned events and task
  links. Verified unique legacy links are reassociated; ambiguous ones are not
  assigned to an arbitrary copy. The source picker opens each copy's details.
- Daily Review ratings (shipped 2026-11-16 in TestFlight and GitHub build 145):
  replace growing circles with five equal, named choices and a single selected
  checkmark. Keep unanswered distinct from neutral and let tapping the selected
  choice clear it. Adapt columns to translated labels and use vertical choices
  for large text. Verified native iPhone light/dark and large-text layouts,
  narrow German and Arabic layouts, the app tests, and the iOS/Watch build.
  Also run the scene's database-resume callback on its initial active value,
  instead of requiring a later foreground transition.
- CloudKit live sync on devices: the container `iCloud.com.lorvex.apple` is
  provisioned and its schema is deployed to Production. The `.live` mode runs
  `CloudSyncController`, an actor wrapping `CKSyncEngine` over one `Lorvex`
  zone (`docs/decisions/cksyncengine-transport.md`). Still owed: two-device
  proof on TestFlight builds, including the iOS sync pass that runs inside a
  background task before the database suspends, and silent-push wakes.
- Standing maintenance and its dates (TestFlight build expiry, certificates,
  toolchain, dependencies): `apps/apple/docs/release.md`, "Standing
  maintenance".
- watchOS / Widgets design audits on hardware (the Watch read-through of
  2026-11-11 below used the simulator).
- Widget sprint (owner, 2026-11-11: the widgets' design, design language,
  UI/UX, user experience, and what they should do). Begins with a capture of
  every family on iPhone, iPad, the Mac, the Lock Screen, Control Center, and
  the Watch complications, and a read of the widget code, against the
  design language ("a row is neutral until something on it needs
  attention"); then the findings, and changes. Design and development,
  new capabilities included, are delegated (owner, 2026-11-12). First round
  (2026-11-11), captured on the iPhone gallery (light, dark, XXXL, German,
  Thai) and the Mac gallery:
  - Fixed: no widget read `widgetRenderingMode`. The Mac desktop renders
    its widgets desaturated whenever a window is in front, as the tinted
    iPhone Home Screen and StandBy at night do, and there a High task's red
    circle, the only mark of its priority, read as Normal. Outside full color
    a circle now carries the priority's mark, as with Differentiate Without
    Color (`WidgetPriorityMarking`); a task with no recorded priority reads
    as Normal, where its glyph had read as Low. Habit tiles and the
    progress ring already tell done, partial, open, and skipped apart by
    shape. The gallery cannot show the system's desaturation; it is covered
    by tests.
  - Fixed: the small Today widget with no lead listed two tasks whose
    titles kept about eight characters on an iPhone. Its titles now take up
    to two lines, the circle beside the first, with a gap between tasks; the
    day's count, which the rows and the foot already say, gave way. Where
    two such rows do not fit (Thai, XXXL) one readable task is shown.
  - Left as is: habit names in the tiles lose two to six characters on the
    small and medium widgets. The tile keeps every name at one size and
    tightens before truncating, two-line names do not fit two rows of
    tiles, and the habit's symbol and color name it too.
  - Fixed 2026-11-12, verified by tests with stand-in schedulers and four
    mutation checks, not yet on a device: a widget's Complete and check-in
    ran in the widget extension, and a repeat's next occurrence had no
    reminder until the app next ran. The widget now re-plans the reminders
    itself with the app's pass (`WidgetReminderReplan` over `ReminderReplan`:
    one budget, the armed and delivered stamps), once notifications are
    allowed, without re-registering the app's notification categories. It
    and the earlier withdrawal assume the extension's notification center is
    the app's; if it were not, the pass would read the permission as
    unanswered and do nothing. The pass removes every pending reminder
    before arming up to 60 again, so an extension stopped midway leaves
    none until the app runs; adding first (the same identifiers replace in
    place) and then removing only the stale ones would close that. Still
    open, an architecture item: the extension cannot read the badge setting
    (the app's own defaults) or reach the Watch (no WatchConnectivity in an
    extension); both wait for the app's next run (see the audit entry
    below).
  - Done 2026-11-12: a task handed to the assistant carries its marker on
    the widget rows and the lead's line, as on the app's rows: the sparkles
    glyph, neutral while the assistant holds the task, and "Replied" in the
    accent once it handed the task back, which reads before the task's time
    (a running time still reads first). The word, not only the tint, tells
    a reply apart, so it survives the desktop's and the tinted Home Screen's
    desaturation. The snapshot carries it as an optional `delegation` key
    on a task, absent for the person's own; the Watch replica leaves it out.
    The small widget's rows and the Lock Screen show no glyph.
  - Decided against: a capture button on the Home Screen widgets. Capture
    is already one tap away in Control Center, on the Lock Screen, on the
    Action button, and in the app icon's quick action; a ＋ on a glance would
    repeat it (rule 12 of `apps/apple/CLAUDE.md`) and add chrome to a
    surface that stays neutral until something needs attention.
  - Done 2026-11-12: the large Today widget lists up to three of the day's
    calendar events still ahead under its tasks, in the agenda's order (an
    all-day event first, then by start), each with a bar in its calendar's
    color where a task has its circle and its time at the trailing edge
    ("Until" its end, in the accent, while it runs). The events stay while
    two tasks fit above them, so the third task onward gives way first,
    counted by the foot line; at the largest text sizes the events give way
    too. They are read in the same transaction as the rest of the snapshot,
    through the same read as the app's calendar, so the widget shows what
    the app shows, carried as an optional `events` key, titled "Busy" while
    titles are hidden, left out of a list-configured widget and the Watch
    replica, and the timeline redraws at each event's start and end, so a
    finished meeting leaves without a reload. A change to the calendar alone
    republishes the widget: a Lorvex event the person or the assistant
    writes (the database-change signal's full refresh), one that arrives
    through sync (the calendar now counts among the widget's domains), and
    the EventKit mirror, which writes without that signal, so each app
    republishes after mirroring a window that holds today; a mirrored event
    alone changes no revision, and the reload check compares the events.
    Medium has no room for them
    beside its two rows; whether it should show the next event in place of
    a row is open, to settle with the widgets in use.

- Hand a task to the assistant (owner approved the idea 2026-11-10;
  released in build 141). A task can be handed to the user's own assistant,
  which works on it with its other tools and hands it back with what it did;
  the list becomes a queue the person and the assistant share. Decisions:
  - Storage is a new synced edge, `task_delegation`, keyed `(task_id,
    assignee)` with a `state` (`assistant` while the assistant holds the
    task, `returned` once it handed it back); deleting the row takes the task
    back. It mirrors `habit_completion` (an edge whose left half is an
    aggregate id, whose right half is a plain string, with one value column),
    because `schema/sync_payload/README.md` rejects a new field on `task`
    without a merge adapter. `assignee` is `assistant` for now; the column is
    a lowercase identifier so named agents can follow without a migration.
    It needs migration 004 (the table, and `sync_tombstones` rebuilt with the
    new type), payload manifest 003, and every site that names `habitSkip`
    (about forty files: `git grep -l habitSkip`), plus the task merge and
    hard-delete paths.
  - The assistant's result goes in the task's existing `ai_notes`. The
    assistant never completes a task it was handed unless the task says it
    may; the person confirms.
  - MCP: task objects carry `delegation`; `list_tasks` filters on it;
    `delegate_task`, `return_task` (result and state in one transaction), and
    `clear_task_delegation`; `get_overview` counts the tasks waiting for the
    assistant. `write_memory`'s description gains the key `routines` (how the
    person wants a recurring job done), which is the whole of "routines as
    data": a preference note, not a new entity and not MCP prompts.
  - Apps: one action beside Complete and Defer ("Hand to Assistant", "Take
    Back"), a marker on the row ("With assistant", "Assistant replied"), on
    the Mac and the iPhone; four new strings in every language.
  - The assistant drives the lifecycle (owner, 2026-11-10): a personal
    assistant is always on and wakes on its own to check mail, chat, and
    apps, Lorvex among them. Lorvex never starts or calls an agent; it makes
    "is anything waiting for me" one cheap read with stable states, so a
    second wake does not redo work, and keeps the result on the task. The
    tasks an assistant has handed back are the person's decisions to make.
  - Done so far (unreleased): migration 004, payload manifest 003, the sync
    appliers, merge, delete, and backfill paths, the service operations
    (`delegateTask`, `returnDelegatedTask`, `clearTaskDelegation`,
    `delegatedTaskCount`), and `delegation` on every task the core returns.
    A backup leaves delegations out (`BackupWholeStoreRoundTripTests`): a
    restored task is the person's own. The MCP surface is in too:
    `delegate_task`, `return_task`, `clear_task_delegation`, the `delegation`
    filter on `list_tasks`, `delegation` on every task object (its `request`
    fenced as user text), two counts in `get_overview`'s compact stats, one
    line in the server instructions, and `routines` among `write_memory`'s
    typical keys. The apps have the action ("Hand to Assistant", "Take
    Back") in a task's menus and the marker ("With assistant", "Assistant
    replied", the reply in the accent) on its row and in its detail, on the
    Mac and the iPhone, in every language; a task the assistant handed back
    opens with what it wrote. Not covered yet: the Mac's table mode, the menu
    bar panel and the Watch show no marker (the widgets show it since
    2026-11-12, see the widget sprint); the request can be set
    only through the assistant, since the apps have no field for it; and the
    two sample replies in the preview data are English in every language.
    The convergence simulation now hands tasks over, returns them, and takes
    them back; soaks of 200 seeds from 2000 on the log transport and 120 from
    3000 on the chaos transport (2026-11-10) ended with no `task_delegation`
    row diverging, the divergences being the older classes below.
- Undo an assistant's change: the tool shipped (`undo_ai_change`, 2026-10-13):
  an assistant takes back its own update to a task or a one-off calendar event
  from the `ai_changelog` snapshots, restoring only the fields that still hold
  what that change set. Still open: an in-app Undo on a Settings > Activity row
  (a new control needs strings in every shipped language), rows of a batch (each
  batch row records the batch, not one task's snapshot), repeating events and
  series edits (their occurrence bookkeeping is not a field restore), and
  habits and lists. A record whose snapshot exceeds the 4000-byte log cap (long
  notes) cannot be undone from the log alone.
- Open UI/UX work, each verified against the code but not yet done:
  - Quick add misreads lines typed in decomposed Unicode in about fifteen
    languages (`ZZCaptureParserFuzzProbeTests`, `FUZZ_NFD`). Low priority in
    practice: keyboards, dictation, and most pasteboards give composed text;
    decomposed text comes from file names and a few apps, and only a keyword
    that carries an accent is affected.
  - Locale follow-ups: weekday and Siri list joins, a few English strings
    outside the catalogs, and the week's first day.
- Known code gaps, each confirmed by a probe or a test but not yet fixed:
  - Quick add: the decomposed-Unicode fix keeps the typed text and matches on
    a composed view with an offset table, composing per grapheme rather than
    with full NFC (NFC splits composition-excluded letters such as Devanagari
    U+0958 to U+095F); eight language suites pin the current behavior and flip
    with the fix. The fuzz probe at its default seed reports the same gap as 18
    lines where a combining accent glued onto a keyword's last letter
    ("tomorroẅ") still reads as the keyword and leaves the mark in the title.
    "[pl,de] 15h" reads as 900 minutes; Vietnamese "3 giờ 15
    phút" reads as 195 minutes; the Romanian reader drops English "in 15 min". (A parenthesized phrase used to
    leave "( )" in the title in every language; the title cleanup now removes
    the pair.)
  - The device's day, not the planner's: when Settings > Time Zone differs from
    the device's, the task editors' day presets (Today, Tomorrow, This Weekend,
    Next Monday) and the Mac picker's month calendar count from the planner's
    day (fixed 2026-11-09). Fixed 2026-11-15: both iPhone task
    editors now propose Add Time from the planner's clock, including when its
    day differs from the device's; the Mac custom snooze chip reads and saves
    its date in the planner's zone. Calendar grids and week strips now mark
    the planner's today; their now line and initial scroll use its clock,
    including fractional offsets and DST. All-day task overdue markers agree
    with Today. Mobile page caches include the logical day and zone so a
    setting change refreshes even an otherwise unchanged page.
  - Time Zone selection (2026-11-15): both settings pickers wait for a saved,
    refreshed choice before closing, show the pending choice, and reject
    repeated taps while saving. A failed write or read keeps the picker open.
    The Mac waits for a trailing refresh if another one is already running.
    Search also matches the displayed GMT offset and full-width city text;
    a saved non-geographic zone such as GMT retains a selectable row.
  - Calendar editing across time zones (2026-11-15): forms show their clock's
    zone, retain exact projected instants across a repeated DST hour, and save
    edits and grid moves back in the event's source zone. Scoped recurrence
    edits compare source days so a projected overnight occurrence cannot
    re-anchor its series accidentally. Undo keeps its instants across a
    product-zone change. New-event defaults, grid selections, and date/time
    controls use the product zone; a draft retains that zone through save.
    Both surfaces reload projected rows after writes instead of displaying
    returned source clocks. Creates no longer append an out-of-window raw
    event, including after a failed reload. A save and a page turn in either
    order retain the last requested window and its matching tasks; a one-day
    Mac window also keeps its exact inclusive range.
    The Mac Repeat defaults now use the event's Gregorian source day, including
    month boundaries and fractional offsets, and identify a source zone that
    differs from the displayed clock. New grid drafts clear the edited event's
    source-zone baseline; returning to that edit restores it.
    Repeat interval and month-day steppers show their current numbers beside
    the arrows, with localized values and explicit accessibility labels.
    Repeat summaries use the source weekday even across the date line, with
    the recurrence zone named in event details. The iPhone editor also shows
    the stored repeat rule. Clearing an opaque rule moves Custom to None
    immediately while preserving the explicit clear in the save patch.
  - Advanced calendar recurrence presentation (2026-11-15): the basic Mac
    editor shows Custom for month-end, multiple month days, ordinal weekdays,
    and other patterns its controls cannot express. The shared summary names
    every supported date filter, including months, signed days, positions,
    and explicit week starts. Interval edits preserve the complete pattern;
    choosing a basic frequency explicitly replaces it while retaining its
    interval and ending condition. Unknown fields keep a rule opaque so a
    partial decode cannot erase them. Core-backed tests check saved rules and
    future dates after title and interval edits.
  - Calendar sharing across zones (2026-11-15): copied/shared text includes
    years, the displayed clock's zone and the source-zone note for a differing
    repeat. Offsets follow event instants, including the second reading of a
    fall-back hour. A change in offset formats both endpoints separately;
    midnight ends name the following date. All-day and floating values stay
    civil, and an event without an end never gains one from editor defaults.
  - Calendar offset transitions (2026-11-15): positive spans with equal or
    reversed fall-back clocks survive projection without weakening source
    timing validation. Grids split occupied clocks at offset changes and name
    each offset; details, forms and agendas retain both real endpoints. Split
    events edit in the sheet. Agenda order, past-state checks and elapsed
    durations use instants. Planning and load use the union of occupied civil
    pieces; Apple Calendar export keeps the real endpoints. Regressions cover
    New York, Lord Howe, spring gaps, exact transitions, provider mirrors and
    recurring identity. No drawn-height or open-end placeholder leaks into a
    reported end time. Headless captures cover Mac and mobile grid geometry.
    Editor no-ops retain repeated-hour instants. Moves use elapsed duration
    when wall duration is nonpositive, and minute edits keep the current
    reading when it remains valid before considering an overnight end.
  - EventKit import instants (2026-11-15): both device mappers retain zoned
    endpoints; migration 005 adds a device-local occurrence cache. Mac series
    retain source rules, anchor dates and zones alongside enumerated instants,
    with stable event/occurrence identities. Exact observations drive timeline
    and occupancy; no master UTC recurrence drift or inferred unseen slots.
    Busy-only redaction preserves occupancy only. Window refreshes merge other
    cached weeks and clear missing in-window occurrences. Legacy rows retain
    their existing projection until refreshed; floating/all-day remain civil.
  - Provider coverage remains a follow-up: expose which queried days were
    actually fetched, so MCP/planning can distinguish an uncached range from
    a confirmed empty range. iOS already mirrors enumerated occurrences;
    precise Mac imports now follow that same observation-based contract.
  - Calendar MCP time context (2026-11-15): clock fields carry their actual
    display/source zone, with response-only `time_context` identifying civil
    values and known UTC endpoints. Full/time-detail canonical rows preserve
    source coordinates for editing, including intended clocks in recurrence
    gaps. Timeline envelopes name the queried zone even when empty. Repeated
    hours page in real-time order with stable identity ties; floating values
    remain civil. Linked provider rows share the precise timeline decoder and
    existing privacy gates. Search remains a source-definition read; tool
    guidance distinguishes master edits from projected occurrence edits.
  - Human editor source-clock preservation (2026-11-16): Mac/iOS scoped saves
    patch changed fields and retain source clocks for unchanged endpoints,
    including spring gaps. Existing gap occurrences can be edited, cancelled,
    restored, and split without admitting a newly invalid start. Floating
    zones survive scoped edits and can be explicitly cleared. Editors expose
    optional ends through add/clear controls; details, grid moves, and undo
    preserve a missing end instead of saving a placeholder duration.
  - Optional-end external fidelity: the Mac's `CalendarEventExport` still
    supplies a fallback duration and a minimum span for system-calendar
    writes. Audit that adapter's point-event semantics and external validation
    before changing the mirror contract; the human editor now retains an
    absent canonical end explicitly.
  - Zero-length timing alignment: core validation accepts equal endpoints,
    while the human editor requires a positive duration. Cover explicit point
    events and recurrence intervals collapsed by a DST gap so their details
    remain editable without forcing a new duration.
  - CloudKit traffic and scale (read-only review against Apple's CKSyncEngine
    guidance, 2026-11-09; none loses data): every local write and every push
    runs a full fetch-then-send pass (`runCloudSyncCycle`), where Apple's
    pattern is to register the change and let the engine send; the
    system-fields cache (`FileCloudSyncRecordSystemFieldsStore`) is one JSON
    file rewritten whole, now at most once per two seconds of changes and at
    the end of each explicit pass (a separate SQLite file in the cache
    directory would write only what changed). A queued write the server
    already holds is confirmed when it is fetched, but a full re-upload still
    sends each record whose fetch has not arrived yet.
  - A task's tag and dependency caps (`maxTaskTags`, `maxTaskDependencies`) are
    held by the local writers only. Sync applies edges one by one and unions
    concurrent additions, so two devices that each added tags can merge a task
    above the cap; that task's tags (or dependencies) can then be changed
    only by one update that leaves at most the cap.
  - A task repeating on the 29th or 30th skips the months that lack that day,
    as RFC 5545 says (`CalendarRecurrence.injectBymonthday`); only an anchor
    that is its month's last day becomes `BYMONTHDAY=-1` and follows month
    ends. Clamping the 29th and 30th would need a multi-day `BYMONTHDAY` with
    `BYSETPOS` that the repeat summary cannot word plainly, so it stays as is
    unless a simpler stored shape is found.
  - Sync convergence limits found by `SyncConvergenceSimulationTests`: a task
    hard-delete racing a concurrent edit when child edges arrive first; a tag
    delete cascading a newer live edge before a resurrecting upsert; alias
    deletes reordered before their redirects; no `habit_completion` fold. A
    soak (`LORVEX_SYNC_SIM_SEEDS=300 LORVEX_SYNC_SIM_FIRST_SEED=2000`, 120 steps,
    the log transport) still diverges on about 7 seeds in 300, after a tag's
    delete stopped cascading its edges away before its redirect's fold, in the
    same batch (`orderedForApply`) and while the redirect waits for its winner
    (`gateLwwAndFk`). The rest are other classes: a `task_tag` edge held by one replica only where one replica
    authored the alias and the edge under the same clock value (seed 2000), a
    lost `task_checklist_item` (seed 1037: a child authored after its task's
    hard delete is discarded as `fk_unresolved` before the task upsert that
    resurrects the task arrives; keeping such children parked leaves entries
    that never resolve when the task stays deleted, so 104 of 300 seeds then
    end with pending entries, and the change was backed out), and a `habit_completion` tombstone with a
    different death version (a note, not a divergence). A parent's hard delete cascades its children on the
    replicas that apply it, while a replica whose own newer upsert wins keeps
    them, and the resurrecting upsert then reaches the others without them. A
    delete that loses to a newer local habit or task now re-emits that parent's
    surviving children at fresh versions (`reassertChildrenAfterLostDelete`):
    checklist items no longer diverge in the soak, and 150 seeds from 1000 fell
    from 10 to 3. A habit completion still diverges in seed 1030's shape: with
    record-slot coalescing the parent's newer upsert replaces the delete in the
    log, so the replica that authored the upsert never sees the delete to lose
    to it and re-emits nothing, while the others cascaded the child and then
    apply the resurrecting upsert (fixing it needs the upsert to carry or
    request its children). A
    child that reaches a replica before the upsert that resurrects its parent is
    still discarded (keeping it parked leaves entries that never resolve when
    the parent stays deleted). The `chaos` transport, which reorders even one device's own emissions and
    so is harsher than CloudKit, diverges on 37 of 200 seeds from 3000, 31 of them
    on `task_tag` edges (a deleted alias source's edges cascading before its
    redirect arrives), and leaves no pending entries. A soak of 100 seeds from 5000 on the log transport (2026-10-13) diverged on 4,
    all in the child-edge classes above. It also flagged two seeds as
    "undecodable envelopes": that was the cycle-break tiebreak dropping a
    dependency edge on purpose (two replicas each added an edge that together
    close a cycle; the loser is dropped everywhere), which the harness now
    recognizes and names. The runs are not bit-for-bit repeatable (ids and
    clocks come from the wall clock), so a seed names a shape, not an exact run.
  - Mac performance, measured in a release build of the core
    (2026-10-12, in-memory store, no dependencies): completing a task takes
    about 2 ms at 100 tasks, 10 ms at 1000, and 29 ms at 3000; reading the
    widget snapshot takes 4, 32, and 123 ms. Two fixes took it there: the
    blocked-task lookup was a join that probed the dependency index once per
    listed task (440 ms at 3000 tasks, now 2 ms), and the task decoder parsed
    two day keys per task with a `DateFormatter` (now a direct parse). What is
    left is one pass per task through the core's JSON enrichment (about 24 µs
    per task), read for Today, for the widget snapshot and the badge, and for
    the Spotlight index. The Spotlight index now adds only the items whose
    title, link, or dates changed since the last replace in the run, so a
    refresh that changed nothing writes nothing to the system index. Each
    external database signal still triggers a full refresh that reads the
    tasks and the calendar window again. The debug-build
    probe (`ZZMutationLatencyProbeTests`) reads about 7 times slower than
    release, mostly unoptimized GRDB row decoding.
  - Mac keyboard: list cards show Edit and Delete only on hover.
  - Mac focus ring on task rows: a row that was clicked or reached with the
    arrow keys draws the system focus ring around its selection fill, which
    reads as a focused text field (owner's screenshot, 2026-11-10). A lighter
    outline of its own (a hairline in the accent drawn by the row, with the
    system ring kept under Full Keyboard Access) was written and taken out
    again unverified: it needs a capture of a focused row, the preview tour
    never takes the keyboard focus, and a synthetic click from a script
    missed because the preview window was not on the active desktop. The way
    to prove it is a DEBUG launch option that makes the preview window key
    and puts the focus on a row itself.
  - Polish: Settings > Diagnostics and the activity log show English changelog summaries; German
    Memory sheet titles truncated at 375 pt (rechecked 2026-10-12 at 402 pt:
    "Neuer Gedächtniseintrag" wraps to two lines in the title bar's three-step
    fit, so only a 375 pt device could still show it; none is installed here); the Urdu Today medium widget shows
    one row.
- Read-only audit of data saving and sync (2026-11-09). Each item was traced
  to the code named and none is reproduced by a test. Fixed since: the Mac's
  snooze and the iPhone's plan-for-a-day write only their own field, a refresh
  that fails keeps a task editor with unsaved edits (and on the iPhone a
  refresh met by the background suspension changes nothing), suspending the
  iOS store waits for the operations in flight to give up their locks, a
  process whose database a newer build has migrated since it opened refuses
  to write (the MCP helper across an app update), and a quarantine is
  remembered by the fresh database until its notice is seen, and
  `get_sync_status` tells the assistant whether the Lorvex app is running and
  what it last reported about sync. The rest is open.
  Checked and found sound: the CloudKit transport's change tags, conflict
  classes, zone deletion, account binding, and end-to-end encrypted fields; the
  HLC lanes; the outbox coalescing; the task editors, which write only the
  fields the user changed; a habit day that holds both a skip and a check-in
  after a merge (reads count it as kept).
  - Lists and habits merge as whole rows: `ApplyList.applyListUpsert` and
    `ApplyHabit` take the whole row of the newer version, so when two devices
    change different fields of one list or habit while apart, one change is
    lost. A reorder no longer widens this: it writes only the rows that have to
    move, one for a single drag (`ReorderPositions`). Tasks and calendar events
    merge field by field. Giving lists and habits the same registers would end
    it.
  - A set-aside database is not salvaged. When the open path quarantines a
    corrupt file (`LorvexStore.open`, `recoverManagedByQuarantine`), nothing
    readable is copied into the new database and the unsent outbox rows stay in
    the set-aside file. The fresh database remembers the quarantine until the
    user has seen the notice, whichever process met the bad file, but on an
    iPhone the file cannot be reached and no surface exports it. A salvage pass
    and an export of the set-aside file would cover it.
  - A long restore on an iPhone can still be cut short. The import holds the
    store while the system allows background time, about half a minute after
    the app is left; past that every later record fails. The tasks already
    created have not had their deferred pass (`applyDeferredTaskWork`:
    dependencies, the cancelled or in-progress status, the original dates), and
    a second run skips them because they exist. Finishing the deferred pass for
    a task the same archive created earlier would cover it.
  - Scale, none measured on a large store: the first upload queues the whole
    database in one transaction inside `startEngine()`
    (`Outbox.enqueueAllLiveForFullResync`), during which another process's
    write waits at most five seconds, and an iOS suspension midway starts it
    over. Sent outbox rows keep their payload for seven days
    (`outboxRetentionDays`), so the database holds two copies of everything for
    a week after a first upload, and rows queue while sync was never on although
    the first start queues everything again. The retention sweep
    (`runPostApplyGC`, more than ten statements and `PRAGMA optimize` in a
    write transaction) runs inside every fetched batch and after every refresh. The
    engine state is rewritten as base64 text in `sync_checkpoints` on every
    state update and lists every pending record. `nextBatch` reads up to 1,000
    outbox rows with their payloads, in a write transaction, for each batch of
    200. Each process has one connection (`DatabaseQueue`), so the refresh's
    parallel reads run one at a time and wait behind an inbound apply;
    `DatabasePool` would let them run beside it. `PRAGMA quick_check` runs on
    every open.
- Read-only audit of how the two apps save what the user types (2026-11-09),
  same standing: traced to the code, not reproduced. Fixed since: the Mac
  inspector's unsaved edits are written when the selection leaves their task
  (another row, a closed inspector, another workspace), Start, Pause, and
  Reopen keep them, a write that fails returns the editor to the task with the
  text, Quit writes edited checklist rows and does not stall on an emptied
  title, a sticky note autosaves once typing pauses, a space typed at the end
  of a title or a checklist row is not an edit and survives the autosave, the
  Mac's inline quick add and the iPhone's checklist composer keep text whose
  write failed, accepting suggested times keeps a time set since they were
  suggested, and the list, habit, and event edit sheets write only the fields
  the user changed, Quit writes a habit's name or encouragement being
  typed, and an error alert on either platform stays up until it is
  acknowledged instead of closing when another action succeeds, and the
  iPhone's Undo waits for another task's write to end instead of doing
  nothing, a new memory under a name another memory holds is refused
  instead of replacing it, and every iPhone and iPad editor sheet refuses a
  swipe-down while it holds unsaved changes. Found sound:
  the daily review on both platforms, capture, the Mac quit handshake for the
  drafts it covers, dirty-draft preservation across refreshes, and no write
  error swallowed with `try?`.
  - Smaller: on the Mac Edit on a memory row replaces unsaved composer
    text.
- Read-only audit of notifications, calendar mirroring, widgets, the Watch,
  and App Intents (2026-11-09), same standing: traced to the code, not
  reproduced. Fixed since: a push that reaches a locked iPhone re-plans the
  reminders, the badge, and the widgets from what it applied; the refresh
  after a reminder's Complete or Defer, or after a Shortcuts write, takes the
  store back, and the app starts its observers on a background launch; a
  habit on chosen weekdays is reminded on each of them; the task entity
  queries take background access; a burst of calendar change notices runs one
  refresh; a change of the device's time zone re-plans reminders; a widget
  snapshot reloads the widgets only when it changes what they show; a widget
  that reloads after midnight rebuilds the snapshot for the new day itself; a
  task completed from a widget takes back its pending reminders and snooze, and
  a habit met from one its later nudges that day; on the
  Mac a repeating Calendar series is mirrored from its first occurrence, so a
  series that ends after a count ends where Calendar ends it, and a series
  Calendar no longer has is removed once Calendar confirms it, as is a one-off
  event deleted after it began. Found sound: reminder triggers as true instants and
  the shared 60-request budget, the widget snapshot file (atomic write, lock,
  ordering), the Watch replica ordering and command journal, the bracketing of
  every intent runner, the Spotlight prune, and the EventKit permission and
  privacy-tier checks. Four items of
  `apps/apple/docs/reference/apple-official/APPLE_NOTIFICATION_REMINDER_AUDIT.md` still
  stand (N5, N6, N8, N10).
  - What Lorvex wrote into Apple Calendar is updated only by Mac actions
    (`AppStoreCalendarWriteBack`): an event deleted or moved on the iPhone or by
    the assistant keeps its old copy in Apple Calendar, which Lorvex itself
    hides. The lookup reaches back 90 days, so editing an older event writes a
    second copy.
  - The Watch complications show Today as unavailable from midnight until the
    phone app publishes a snapshot for the new day (the Watch app asks the
    phone for one when opened): the iPhone widgets rebuild their own file when
    they reload, but that write never reaches the Watch.
  - A widget's Complete re-plans the reminders since 2026-11-12, a repeat's
    next occurrence included, but the badge does not change until the phone
    app next runs, and neither the write nor a Focus filter change reaches
    the Watch until the phone app publishes.
  - Smaller: a Watch command the phone cannot verify at all (bytes that do
    not match their checksum, another protocol version) is rejected on the
    watch after three tries without renumbering, and the phone then refuses
    every later command as a sequence gap. Since 2026-11-11 the case that
    version skew produces, a verified command whose action the phone cannot
    read, is rejected by the phone at its sequence (`unreadable_action`), so
    the stream moves on; what remains takes corrupted bytes or a protocol
    change.
- Read-through of the Apple Watch app, its complication, and the phone's side
  of the link (2026-11-11): every source file read, the five preview pages
  captured on the simulator (first from the build of 2026-10-12, the Mac being
  on battery, then from the build with the fixes below, which draws a
  normal-priority circle neutral). Traced to the code, not reproduced on a
  watch; the captures show layout only, since the preview has no journal. Found sound: the replica's workspace fence, ordering, and atomic
  file; the command journal (never evicts, writes before it reports success);
  first-in-first-out delivery with ACKs bound to a command's identity and
  checksum; the phone's ledger, which applies a command once across retries
  and restarts; the size bounds on everything the phone sends; titles redacted
  on a locked face; the product day and its time zone carried by the replica
  rather than computed on the wrist. Fixed since (2026-11-11): a habit
  checked on the wrist while the phone was out of reach read as unchecked
  again at the next refresh, which invited a second tap on a habit counted
  several times a day; a pending check-in journaled after the replica on
  screen was received is now put back over it (both times by the watch's
  clock; the replica file keeps its date when the same bytes arrive again),
  and one older than the replica is left to the phone. One window remains:
  on reconnect the system first delivers a replica the phone published while
  out of reach, received after the check-in, so the ring reads unchecked
  until the phone applies the command and sends its next replica. Exact
  either way would need the replica to carry the phone's applied sequence for
  this watch (`local_watch_command_streams.last_terminal_sequence`), so the
  watch re-applies exactly the pending commands above it; that changes the
  envelope and needs a compatibility plan. The root view's
  spinner, which on a cleared day took the pages down on every check-in and
  capture, now shows only before the first refresh finishes. Open:
  - Fixed 2026-11-11: a rejected action read "Action 37 wasn’t applied" (the
    journal's sequence number); it now names the action ("Couldn’t
    complete") and what it was for (the task's title or habit's name from
    the replicas seen since launch, or the captured text). A failed action
    was explained only on Today, and on an empty Today read "Couldn’t load
    Today"; it is now said on the page where it was taken, Today keeps its
    empty-day message under it, and an action tried before the first replica
    says to open Lorvex on the iPhone first. The failure states are covered
    by tests, not by a capture: the preview has no journal.
  - Nothing on the wrist takes back a completed task or a habit check-in, and
    the wire has no reopen or uncheck. A few seconds' grace before the command
    is journaled would cover a mistaken tap with no protocol change.
  - Fixed 2026-11-11: `StoreError.invariant` and `.serialization`, which a
    retry of the same command cannot change, were answered as retryable
    without limit and held every later command back; they are now rejected
    (`invalid_state`). A concurrent write's `staleVersion` and database
    errors stay retryable.
  - Smaller: the list shown at midnight stays until the app is next
    activated; the watch asks the phone for a replica only when it has none or
    one from an earlier day; the phone answers that request only after its
    full refresh, the iCloud pass included; the "Synced" line on the capture
    page is drawn as a row that looks tappable.
- Russian at the largest accessibility text size (iPhone, 2026-10-12) was
  captured for Today, Tasks, Habits, and the event detail: legible, hyphenated
  by the system, nothing overlapping.
- German at the largest accessibility text size (iPhone, 2026-10-12) was
  captured for Today, Calendar, Tasks, Habits, and the event detail. One rough
  edge remains, only at that size: the Habits large title truncates
  ("Gewohnheit…"). A streak chip that used to break inside its compound
  ("12-Tag / e-Serie") now breaks at the hyphen.
- Also captured and clean on 2026-10-12: iPad in German (Today, event detail,
  Habits, Memory), and the iPhone Habits, Progress, and Lock Screen widgets in
  German and Arabic (mirrored, Arabic-Indic digits).
- Coverage not yet captured: the largest accessibility text sizes in languages
  other than English, Chinese, German, and Russian, iPad routes other than those above
  and Review, the Habits, Progress, and Lock Screen widgets in the other
  languages, Mac widgets and watch
  complications in other languages, and the MCP fuzz families for checklist
  text, trash and restore, batch tools, and recurring `until` and `count` edits.
- Needs a device or a person: real drags and resizes (including the Tasks
  table row drag), undo, context menus, Full Keyboard Access, the Quick
  Capture hotkey, Open at Login, the Control Center capture control,
  real-finger calendar swipes, watch checks on hardware, iPad hardware
  keyboard shortcuts, permanent delete on an iPhone, and a repeating task
  completed from a widget on an iPhone whose app is suspended, which should
  arm the next occurrence's reminder at once.
- Waiting on the owner's decision: the App Store listing (on hold), dark and
  tinted app-icon art, a Share extension, and the App Store "Differentiate
  Without Color Alone" claim.

### Localization
- The shipped set of thirty languages is complete
  (`apps/apple/docs/LOCALIZATION.md`, "Language coverage"); the language count
  is capped at about thirty, with room for up to five more later (the owner
  allowed it on 2026-10-12; translate them with Claude Haiku 5.5). Candidates,
  chosen for App Store reach among languages not yet shipped: Swedish, Danish,
  Norwegian Bokmål, Finnish (each `one`/`other`), and Czech (`one`/`few`/`many`/
  `other`); Hungarian and Catalan follow if a fifth slot is not Czech. Adding a
  language is more than its strings (2,700 catalog entries and 17 InfoPlist keys
  per language, measured with `localization_transfer.py export`): its
  `PLURAL_CATEGORIES` entry in `script/verify_localization_catalog.py`, its
  entry in the app's language list (`AppLanguageTests`), its quick-add
  vocabulary in `LorvexCaptureVocabulary.swift` with a `CaptureParser<Language>Tests`
  file and a pass of the fuzz probe, the widget and text-direction test
  tables, the App Store listing copy, and a capture review at the largest text
  size. The vocabulary and parser work is the part that needs a fluent reader. Every new string carries every shipped language:
  `apps/apple/script/localization_transfer.py` exports what a language lacks
  and imports translations, and the catalog verifier and `LocalizationTests`
  reject a partial language.
- The App Store listing (`apps/apple/docs/APP_STORE_METADATA.md`) carries its
  name, subtitle, description, and keywords in App Store Connect for every
  shipped language except Urdu, Hebrew, German, Dutch, Romanian, Indonesian,
  Malay, Vietnamese, Turkish, Thai, Greek, Bengali, Marathi, Telugu, and Tamil,
  whose listing copy is not written yet. Persian has no listing: App Store
  Connect offers no Persian localization.
  Screenshots exist for English and Simplified Chinese; the other locales show
  the English ones until their own are captured and uploaded. The sample
  datasets translate into every shipped language (`LorvexSampleText`), so
  those captures show sample content in their language. Listing work is on hold
  until the owner resumes it.

### Shared
- `schema/schema.sql` is the app's schema authority. Schema changes go through
  the numbered migration ladder and the sync-payload manifests
  (`schema/migrations/README.md`, `schema/sync_payload/`).
