# Roadmap

Open work for Lorvex, grouped by what moves it forward. Shipped work is not
listed here: each build has a record in `docs/releases/` (indexed in
`docs/INDEX.md`), and the history of a change is in its commit.

Apple Swift is the only shipping line: macOS App Store, direct macOS builds,
iOS, iPadOS, watchOS, WidgetKit, App Intents, EventKit, CloudKit/iCloud, and
other Apple-native capabilities. visionOS is out of scope for now. The former
cross-platform Tauri line was removed from this repository on 2026-09-17. The
Apple core port has landed; its decision record is
`docs/decisions/pure-swift-core-port.md`.

When an entry ships, delete it and record the build in `docs/releases/`. Keep
a shipped entry only for the part of it that is still open.

## Evaluate in daily use

These shipped, and only use can say whether they are right. Each needs a
person living with the app, and then a decision.

- Evening review ([build 146](docs/releases/1.0.0-146.md)): can someone
  finish an evening review and trust next morning's plan without reopening
  the task list?
- The current task on Mac Today ([build 147](docs/releases/1.0.0-147.md)):
  the return from a meeting, including days without time slots.
- Morning and evening routines ([build 148](docs/releases/1.0.0-148.md)):
  whether the two-hour window suits actual mornings and evenings, especially
  with unusual schedules or a habit that belongs to both routines.
- The time grid beside Mac Today's task list
  ([build 172](docs/releases/1.0.0-172.md)): whether it replaces trips to
  Calendar, and whether suggested times should be drawn on it as draft
  blocks.
- The Medium Today widget has no room for the day's calendar events beside
  its two rows: whether it should show the next event in place of a row.
- Siri working with tasks ([build 173](docs/releases/1.0.0-173.md)), on a
  device where Siri AI is available: whether Siri picks Lorvex for a request
  that names it; whether a day given to Siri should be the planned day, as
  built, or the deadline; whether deleting asks twice, once in Siri's words
  and once in Lorvex's, and if so whether Lorvex's question should go; what
  Siri says when asked for a location reminder or an hourly repeat, which
  Lorvex does not have; and, for "every other week on Sunday and Monday" and
  "every month on the 31st", whether the days Lorvex lands on are the days
  Siri announced. Lorvex takes the week start from the rule Siri sends and
  skips a month without the day.
- Siri hearing the app's name ([build 174](docs/releases/1.0.0-174.md)).
  "Lorvex" is a coined word and Siri has heard it as "Lorax". The app now
  declares an alternative name with a pronunciation hint
  (`INAlternativeAppNames`, "Lore Vex") and a spoken name
  (`CFBundleSpokenName`). Apple documents both for this purpose; developer
  reports say the hint does not always help, and nothing here can measure
  it. Say "Add a task in Lorvex" ten times before and after the build and
  count how often Siri picks Lorvex. If it does not improve, the next step
  is a phrase that does not need the name, which only the Siri AI schemas
  allow.

## Product work

- Platform adaptation sprint (owner, 2026-11-16): iPhone Duo and useful
  capabilities in macOS 27 and iOS 27. The deployment floor stays at 26, so
  every 27 API sits behind an availability check. The system integration
  changes were evaluated on 2026-11-22 against the 27.2 SDK, Apple's
  [SwiftUI](https://developer.apple.com/documentation/updates/swiftui) and
  [App Intents](https://developer.apple.com/documentation/updates/appintents)
  update lists, and the
  [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).
  The work, in priority order:
  1. Siri for tasks and events. iOS 27 and macOS 27 add the `.reminders` and
     `.calendar`
     [app schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains).
     Siri matches an intent that conforms to one from ordinary speech ("mark
     this as completed", "set the due date to tomorrow") with no phrase to
     define. Tasks and lists conform to the reminders domain since
     [build 173](docs/releases/1.0.0-173.md). Remaining, in order: mark task
     rows and detail views with `appEntityIdentifier` so "this task" resolves
     to what is on screen, which needs the iOS interface module to depend on
     the intents module; index tasks as `IndexedEntity` so Siri finds them
     through Spotlight's semantic search (the Mac indexes tasks for Spotlight
     already, iOS has no index); and give calendar events the `.calendar`
     domain's entity with its create, update and delete intents. Limits as of
     2026-11-22
     ([Apple's requirements](https://support.apple.com/en-us/127893)): Siri
     AI is in beta, supports six languages without Chinese, and does not
     work for an Apple Account in mainland China or on iPhone and iPad in
     the EU. Siri calling an intent outside a schema is a
     [developer preview](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview)
     limited to internal TestFlight testers, so the other intents wait for
     its release.
  2. iPhone Duo. Start from Apple's
     [preparation guide](https://developer.apple.com/iphone-duo/prepare/) and
     [design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
     A build made with the 27.1 SDK or later already runs edge to edge on
     both displays with toolbars and tab bars on the vertical axis, so every
     current build does. Done so far: Today's columns
     ([build 153](docs/releases/1.0.0-153.md)), the mobile Week agenda
     ([build 154](docs/releases/1.0.0-154.md)), journal search on the outer
     display ([build 170](docs/releases/1.0.0-170.md)), and a pass over
     sixteen screens on the outer display
     ([build 174](docs/releases/1.0.0-174.md)): Today, Tasks, the three
     calendar grids, Habits, both reviews, a task's detail and editor,
     capture, Settings, Lists, Memory and an event's detail, in light, with
     the calendar and Review also in dark and in landscape. Remaining:
     - The largest text sizes on the outer display. One round was taken while
       the simulator was still loading and is not evidence.
     - Resizing and Split View, which `devicectl device appResize` drives
       without a person: that navigation, selection, scroll position and an
       unsaved draft survive a size change.
     - By hand, because nothing but Device Hub's hinge control folds the
       simulator (`apps/apple/docs/development/VERIFICATION.md`, "iPhone
       Duo"): the inner display, the half-open posture with its reserved
       regions, and the same continuity when the device is opened and closed.
     - `GeometryProxy.reservedRegions`, `onHingeChange`,
       `toolbarVerticalBehavior` and a toolbar item's `axisBehavior` are in
       the 27.2 SDK and not adopted. Nothing seen on the outer display needs
       them; the inner display and the half-open posture decide.
     - On a lane too narrow for a second title line beside a time, an event
       block shows a cut title over its time ("Custom…", "11:00 AM"). The
       block's place on the grid already gives the time, so the whole title
       on two lines may serve better there.
  3. Small adoptions: `TabsPickerStyle` on the segmented pickers that switch
     a page's content, which VoiceOver then reads as tabs; toolbar
     `visibilityPriority` and `ToolbarOverflowMenu`, so a narrow window and
     Duo's vertical bar drop the less important items first.
- Hand a task to the assistant (released in build 141). Not covered yet: the
  Mac's table mode, the menu bar panel and the Watch show no marker; the
  request can be set only through the assistant, since the apps have no field
  for it; and the two sample replies in the preview data are English in every
  language.
- Undo an assistant's change. The tool shipped (`undo_ai_change`,
  2026-10-13): an assistant takes back its own update to a task or a one-off
  calendar event from the `ai_changelog` snapshots, restoring only the fields
  that still hold what that change set. Still open: an in-app Undo on a
  Settings > Activity row (a new control needs strings in every shipped
  language), rows of a batch (each batch row records the batch, not one
  task's snapshot), repeating events and series edits (their occurrence
  bookkeeping is not a field restore), and habits and lists. A record whose
  snapshot exceeds the 4000-byte log cap (long notes) cannot be undone from
  the log alone.
- Quick add, each gap confirmed by a probe or a test:
  - Lines typed in decomposed Unicode are misread in about fifteen languages
    (`ZZCaptureParserFuzzProbeTests`, `FUZZ_NFD`). Low priority in practice:
    keyboards, dictation, and most pasteboards give composed text;
    decomposed text comes from file names and a few apps, and only a keyword
    that carries an accent is affected. The fix keeps the typed text and
    matches on a composed view with an offset table, composing per grapheme
    rather than with full NFC (NFC splits composition-excluded letters such
    as Devanagari U+0958 to U+095F); eight language suites pin the current
    behavior and flip with the fix. The fuzz probe at its default seed
    reports the same gap as 18 lines where a combining accent glued onto a
    keyword's last letter ("tomorroẅ") still reads as the keyword and leaves
    the mark in the title.
  - "[pl,de] 15h" reads as 900 minutes; Vietnamese "3 giờ 15 phút" reads as
    195 minutes; the Romanian reader drops English "in 15 min".
- Locale follow-ups: weekday and Siri list joins, a few English strings
  outside the catalogs, and the week's first day.
- Calendar:
  - Provider coverage: expose which queried days were actually fetched, so
    MCP/planning can distinguish an uncached range from a confirmed empty
    range. iOS already mirrors enumerated occurrences; precise Mac imports
    follow that same observation-based contract.
  - Optional-end external fidelity: the Mac's `CalendarEventExport` still
    supplies a fallback duration and a minimum span for system-calendar
    writes. Audit that adapter's point-event semantics and external
    validation before changing the mirror contract; the human editor retains
    an absent canonical end explicitly.
  - Zero-length timing alignment: core validation accepts equal endpoints,
    while the human editor requires a positive duration. Cover explicit point
    events and recurrence intervals collapsed by a DST gap so their details
    remain editable without forcing a new duration.
- Mac:
  - Keyboard: list cards show Edit and Delete only on hover.
  - Focus ring on task rows: a row that was clicked or reached with the
    arrow keys draws the system focus ring around its selection fill, which
    reads as a focused text field (owner's screenshot, 2026-11-10). A lighter
    outline of its own (a hairline in the accent drawn by the row, with the
    system ring kept under Full Keyboard Access) was written and taken out
    again unverified: it needs a capture of a focused row, the preview tour
    never takes the keyboard focus, and a synthetic click from a script
    missed because the preview window was not on the active desktop. The way
    to prove it is a DEBUG launch option that makes the preview window key
    and puts the focus on a row itself.
  - Edit on a memory row replaces unsaved composer text.
- Apple Watch:
  - Nothing on the wrist takes back a completed task or a habit check-in,
    and the wire has no reopen or uncheck. A few seconds' grace before the
    command is journaled would cover a mistaken tap with no protocol change.
  - Smaller: the list shown at midnight stays until the app is next
    activated; the watch asks the phone for a replica only when it has none
    or one from an earlier day; the phone answers that request only after
    its full refresh, the iCloud pass included; the "Synced" line on the
    capture page is drawn as a row that looks tappable.
- Polish: Settings > Diagnostics and the activity log show English changelog
  summaries; German Memory sheet titles truncated at 375 pt (rechecked
  2026-10-12 at 402 pt: "Neuer Gedächtniseintrag" wraps to two lines in the
  title bar's three-step fit, so only a 375 pt device could still show it;
  none is installed here); the Urdu Today medium widget shows one row; in
  German at the largest accessibility text size on iPhone the Habits large
  title truncates ("Gewohnheit…").

## Areas not yet examined

Whole dimensions of the product that no audit, test or capture round has
looked at, listed on 2026-11-22 after two defects reached the owner before
they reached this list. Each names what is known and the first step. Take
them by effect on a person's day, and add to the list whenever a new one is
noticed.

- Signals from real use. The app keeps a diagnostics log on each device
  (sync refusals, failed actions, MetricKit crashes and metrics), and
  `get_recent_logs` reads it on the Mac. An iPhone's log reached a developer
  only as screenshots until build 174 added Share to the list. TestFlight's
  crash submissions were read for the first time on 2026-11-22
  (`apps/apple/script/testflight_crashes.py`): five, the newest from
  2026-10-18 on build 135, and none for a build since. Not read so far:
  TestFlight's screenshot feedback, and which builds run side by side on one
  person's devices (on 2026-11-22 the owner's Mac ran 171 beside a phone on
  173). First steps: read App Store Connect's crash and feedback records in
  each release cycle, and read the Mac's log at the start of a work session.
- The assistant's experience. The main interface is an assistant working
  through MCP. Its quality has been checked through schemas, fuzzing and
  tests of each tool, and never by watching an assistant do a person's
  requests: plan the day, clear the inbox, move a week around. Unknown: how
  many calls a request takes, where an assistant picks the wrong tool or
  misreads a result, and what the responses cost in tokens. First step: a
  set of realistic requests run by an assistant against a seeded store, the
  transcripts reviewed as critically as captures are.
- Connecting an assistant. Setup is a path into the app bundle, typed into a
  client's configuration. When the helper moved into `LorvexMCPHost.app`, an
  entry with the earlier path stopped working with no message from either
  side (seen on the owner's Mac, 2026-11-22). The Claude Code plugin finds
  the helper itself; other clients do not. To weigh: a bundle a desktop
  client installs in one step, and a line in Settings saying when an
  assistant last connected, so a broken entry shows.
- An automated accessibility audit. XCTest's `performAccessibilityAudit`
  checks contrast, hit regions, missing labels, clipped text and traits. It
  has never been run; the iOS UI test target exists. First step: one audit
  per main screen on the simulator, then decide which findings are real.
- A safety net for a person's data. Export is by hand (Settings, a Shortcuts
  action, an MCP tool); nothing keeps a dated copy. An assistant can cancel
  a whole list in one call, undo covers one assistant update at a time, and
  a sync defect can leave devices disagreeing for weeks (build 174). A local
  snapshot kept for some days and restorable from Settings would bound the
  loss from any of these.
- Disk writes and launch time on a real store. MetricKit on the owner's Mac,
  whose database is 2.5 MB, reported 28.5 MB written on 2026-11-22 and
  10.2 MB on 2026-11-14, against 1.2 to 4.1 MB on three other days, and one
  launch of 3.3 s against 0.7 to 1.2 s. The causes are not established; the
  rewrite-whole sync caches under "CloudKit traffic and scale" below are the
  first suspects. First step: attribute the writes on a day of normal use.
- Hosted CI. `Apple CI` runs only when dispatched, because macOS minutes
  were paused while the repository was private, and it has no recorded run.
  The repository is public now. First step: dispatch one run and see whether
  the hosted image has a new enough Xcode; if it passes, restore the push
  trigger.

## Sync and data

Found by read-only audits (2026-11-09) and by the convergence simulation.
Each is traced to the code; none is reproduced on devices.

- CloudKit live sync on devices: the container `iCloud.com.lorvex.apple` is
  provisioned and its schema is deployed to Production. The `.live` mode runs
  `CloudSyncController`, an actor wrapping `CKSyncEngine` over one `Lorvex`
  zone (`docs/decisions/cksyncengine-transport.md`). Still owed: two-device
  proof on TestFlight builds, including the iOS sync pass that runs inside a
  background task before the database suspends, and silent-push wakes.
- A record a device refuses as invalid is dropped, with a diagnostics entry
  and nothing else. The device that sent it shows it as synced, the others
  keep their older state, and no surface tells the person their devices
  disagree. A record held back for a record that was dropped stays held back
  until the dropped one is sent again. Build 174 fixed two causes in
  repeating tasks and repairs the rows one of them left
  ([release record](docs/releases/1.0.0-174.md)); the general gap stands. To
  weigh: check a task payload against the inbound rules where it is queued,
  so the writing device learns at once, and a sync status line that counts
  refused and held-back records.
- A generated occurrence's link to the occurrence before it
  (`spawned_from`). The link is valid only while the earlier occurrence
  records the task as its next one in the same series. Build 174 holds that
  rule when a task is cancelled with its series, when a repeat is turned off
  after a completion was undone, and on the receiving device. Open, each
  reproduced by a test run on 2026-11-22 or traced to the code:
  - A cancelled occurrence can stay linked to an earlier occurrence that no
    longer records it, and every export then stops with "Task sync is still
    reconciling related records". One path is left: undo a completion, change
    the repeat so it ends on or before that day, and complete again. Rows
    written by builds before 174 in the undo-then-turn-off-repeat order have
    the same shape. Sync accepts the shape, so it cannot be repaired the way
    the refused rows are: a device shows it briefly between two records of
    one change, and a repair there would overwrite the record still on its
    way. To weigh: drop the link where the task is written, or have the
    export leave out a link the earlier occurrence does not record.
  - A task that kept its link, lost its series and later got a repeat of its
    own (a link beside another series, no occurrence key) is refused by
    other devices and not repaired. The owner's Mac held none on 2026-11-22.
    Repairing it ends the earlier occurrence's record, which a device on a
    build before 174 answers by cancelling the task when that record arrives
    first.
  - Devices on builds before 174 still cancel a generated occurrence whose
    repeat was turned off when the earlier occurrence's record arrives
    first. It ends when every device runs 174 or later.
  - Build 174 itself still cancels it, on every device, in two cases. One:
    the earlier occurrence's record says more than that it stopped recording
    the later task, and arrives first. That happens when the earlier
    occurrence's own repeat was turned off as well, or it was reopened,
    before the device synced. Two: the receiving device had not yet applied
    the completion that generated the later task. A device keeps the later
    task only when the record it applies changes nothing about the earlier
    occurrence except ending that record. To weigh: have the device that
    takes a task out of its series stamp the task's status in the same
    write, so the task's own record outlasts a cancel another device works
    out.
  - Two devices editing at once: one completes the earlier occurrence again
    while the other changes the later task's schedule outside the series.
    Both end with the earlier occurrence naming a next one that does not
    link back; they agree with each other, and export stops as above.
  - Turning the repeat off on an occurrence withdraws the occurrences
    generated after it. Through build 174 that included completed ones: a
    daily task completed twice, with the repeat then turned off on the first
    occurrence, was left with the second (completed) and the third (open)
    both cancelled, the second without its completion time. Siri's delete,
    which ends the series, did the same to a completed occurrence of a task
    that had been reopened. The device now refuses a write that would
    withdraw a completed occurrence and says to turn the repeat off on the
    latest one; a list cancelled with its series fails as a whole on such a
    task, as it does for the other refusals. Open: the cancel a receiving
    device works out from the earlier occurrence's record has no such check,
    so two devices editing the same series before they sync can still cancel
    an occurrence one of them completed. To weigh: instead of refusing, keep
    a completed later occurrence as it is and withdraw only the open one,
    which needs the status stamp described above so the kept status holds on
    the other devices.
- The iPhone database and suspension. The store refuses work while the app
  is in the background so the system never suspends the process holding a
  file lock (crash `0xdead10cc`). One such crash was recorded on the owner's
  phone in the week of 2026-11-15; which path held the lock is not known,
  and the entry's detail (process, build, call stacks) settles it. Open
  paths, each traced to the code and none reproduced: opening the store
  (schema check, migrations, `PRAGMA optimize`) runs before the suspension
  check and outside the count of work in flight; suspending is decided by
  `UIApplication.applicationState` and resuming by the scene phase, two
  signals that could disagree; work that takes longer than one second to
  unwind outlives the wait; and the widget and Focus filter extensions
  write with no protection. No test covers the scene-phase resume, the
  suspend at launch, or the open path.
- CloudKit traffic and scale (reviewed against Apple's CKSyncEngine guidance;
  none loses data): every local write and every push runs a full
  fetch-then-send pass (`runCloudSyncCycle`), where Apple's pattern is to
  register the change and let the engine send; the system-fields cache
  (`FileCloudSyncRecordSystemFieldsStore`) is one JSON file rewritten whole,
  at most once per two seconds of changes and at the end of each explicit
  pass (a separate SQLite file in the cache directory would write only what
  changed). A queued write the server already holds is confirmed when it is
  fetched, but a full re-upload still sends each record whose fetch has not
  arrived yet.
- A task's tag and dependency caps (`maxTaskTags`, `maxTaskDependencies`) are
  held by the local writers only. Sync applies edges one by one and unions
  concurrent additions, so two devices that each added tags can merge a task
  above the cap; that task's tags (or dependencies) can then be changed only
  by one update that leaves at most the cap.
- Lists and habits merge as whole rows: `ApplyList.applyListUpsert` and
  `ApplyHabit` take the whole row of the newer version, so when two devices
  change different fields of one list or habit while apart, one change is
  lost. A reorder does not widen this: it writes only the rows that have to
  move, one for a single drag (`ReorderPositions`). Tasks and calendar events
  merge field by field. Giving lists and habits the same registers would end
  it.
- A set-aside database is not salvaged. When the open path quarantines a
  corrupt file (`LorvexStore.open`, `recoverManagedByQuarantine`), nothing
  readable is copied into the new database and the unsent outbox rows stay
  in the set-aside file. The fresh database remembers the quarantine until
  the user has seen the notice, whichever process met the bad file, but on
  an iPhone the file cannot be reached and no surface exports it. A salvage
  pass and an export of the set-aside file would cover it.
- A long restore on an iPhone can still be cut short. The import holds the
  store while the system allows background time, about half a minute after
  the app is left; past that every later record fails. The tasks already
  created have not had their deferred pass (`applyDeferredTaskWork`:
  dependencies, the cancelled or in-progress status, the original dates),
  and a second run skips them because they exist. Finishing the deferred
  pass for a task the same archive created earlier would cover it.
- Scale, none measured on a large store: the first upload queues the whole
  database in one transaction inside `startEngine()`
  (`Outbox.enqueueAllLiveForFullResync`), during which another process's
  write waits at most five seconds, and an iOS suspension midway starts it
  over. Sent outbox rows keep their payload for seven days
  (`outboxRetentionDays`), so the database holds two copies of everything
  for a week after a first upload, and rows queue while sync was never on
  although the first start queues everything again. The retention sweep
  (`runPostApplyGC`, more than ten statements and `PRAGMA optimize` in a
  write transaction) runs inside every fetched batch and after every
  refresh. The engine state is rewritten as base64 text in
  `sync_checkpoints` on every state update and lists every pending record.
  `nextBatch` reads up to 1,000 outbox rows with their payloads, in a write
  transaction, for each batch of 200. Each process has one connection
  (`DatabaseQueue`), so the refresh's parallel reads run one at a time and
  wait behind an inbound apply; `DatabasePool` would let them run beside it.
  `PRAGMA quick_check` runs on every open.
- Sync convergence limits found by `SyncConvergenceSimulationTests`: a task
  hard-delete racing a concurrent edit when child edges arrive first; a tag
  delete cascading a newer live edge before a resurrecting upsert; alias
  deletes reordered before their redirects; no `habit_completion` fold. A
  soak (`LORVEX_SYNC_SIM_SEEDS=300 LORVEX_SYNC_SIM_FIRST_SEED=2000`, 120
  steps, the log transport) still diverges on about 7 seeds in 300, after a
  tag's delete stopped cascading its edges away before its redirect's fold,
  in the same batch (`orderedForApply`) and while the redirect waits for its
  winner (`gateLwwAndFk`). The rest are other classes: a `task_tag` edge
  held by one replica only where one replica authored the alias and the edge
  under the same clock value (seed 2000), a lost `task_checklist_item` (seed
  1037: a child authored after its task's hard delete is discarded as
  `fk_unresolved` before the task upsert that resurrects the task arrives;
  keeping such children parked leaves entries that never resolve when the
  task stays deleted, so 104 of 300 seeds then end with pending entries, and
  the change was backed out), and a `habit_completion` tombstone with a
  different death version (a note, not a divergence). A parent's hard delete
  cascades its children on the replicas that apply it, while a replica whose
  own newer upsert wins keeps them, and the resurrecting upsert then reaches
  the others without them. A delete that loses to a newer local habit or
  task re-emits that parent's surviving children at fresh versions
  (`reassertChildrenAfterLostDelete`): checklist items no longer diverge in
  the soak, and 150 seeds from 1000 fell from 10 to 3. A habit completion
  still diverges in seed 1030's shape: with record-slot coalescing the
  parent's newer upsert replaces the delete in the log, so the replica that
  authored the upsert never sees the delete to lose to it and re-emits
  nothing, while the others cascaded the child and then apply the
  resurrecting upsert (fixing it needs the upsert to carry or request its
  children). A child that reaches a replica before the upsert that
  resurrects its parent is still discarded (keeping it parked leaves entries
  that never resolve when the parent stays deleted). The `chaos` transport,
  which reorders even one device's own emissions and so is harsher than
  CloudKit, diverges on 37 of 200 seeds from 3000, 31 of them on `task_tag`
  edges (a deleted alias source's edges cascading before its redirect
  arrives), and leaves no pending entries. A soak of 100 seeds from 5000 on
  the log transport (2026-10-13) diverged on 4, all in the child-edge
  classes above. The runs are not bit-for-bit repeatable (ids and clocks
  come from the wall clock), so a seed names a shape, not an exact run.

## Notifications, calendar mirroring, widgets, and the Watch link

Found by read-only audits (2026-11-09) and a read-through of the Watch app
(2026-11-11). Each is traced to the code; none is reproduced on devices.

- Four items of
  `apps/apple/docs/reference/apple-official/APPLE_NOTIFICATION_REMINDER_AUDIT.md`
  still stand (N5, N6, N8, N10).
- What Lorvex wrote into Apple Calendar is updated only by Mac actions
  (`AppStoreCalendarWriteBack`): an event deleted or moved on the iPhone or
  by the assistant keeps its old copy in Apple Calendar, which Lorvex itself
  hides. The lookup reaches back 90 days, so editing an older event writes a
  second copy.
- The Watch complications show Today as unavailable from midnight until the
  phone app publishes a snapshot for the new day (the Watch app asks the
  phone for one when opened): the iPhone widgets rebuild their own file when
  they reload, but that write never reaches the Watch.
- A widget's Complete or check-in runs in the widget extension. It re-plans
  the reminders itself (`WidgetReminderReplan` over `ReminderReplan`), a
  repeat's next occurrence included, but the extension cannot read the badge
  setting (the app's own defaults) or reach the Watch (no WatchConnectivity
  in an extension): the badge does not change until the phone app next runs,
  and neither the write nor a Focus filter change reaches the Watch until
  the phone app publishes. The re-plan removes every pending reminder before
  arming up to 60 again, so an extension stopped midway leaves none until
  the app runs; adding first (the same identifiers replace in place) and
  then removing only the stale ones would close that.
- A Watch command the phone cannot verify at all (bytes that do not match
  their checksum, another protocol version) is rejected on the watch after
  three tries without renumbering, and the phone then refuses every later
  command as a sequence gap. The case that version skew produces, a verified
  command whose action the phone cannot read, is rejected by the phone at
  its sequence (`unreadable_action`), so the stream moves on; what remains
  takes corrupted bytes or a protocol change.
- A habit checked on the wrist while the phone was out of reach: on
  reconnect the system first delivers a replica the phone published while
  out of reach, received after the check-in, so the ring reads unchecked
  until the phone applies the command and sends its next replica. Exact
  either way would need the replica to carry the phone's applied sequence
  for this watch (`local_watch_command_streams.last_terminal_sequence`), so
  the watch re-applies exactly the pending commands above it; that changes
  the envelope and needs a compatibility plan.

## Verification still owed

- The widget's reminder re-plan after Complete and check-in is verified by
  tests with stand-in schedulers and four mutation checks, not yet on a
  device. It assumes the extension's notification center is the app's; if it
  were not, the pass would read the permission as unanswered and do nothing.
- watchOS and widget design audits on hardware: the Watch read-through of
  2026-11-11 used the simulator, and its captures show layout only.
- Coverage not yet captured: the largest accessibility text sizes in
  languages other than English, Chinese, German, and Russian, iPad routes
  other than Today, the event detail, Habits, Memory, and Review, the
  Habits, Progress, and Lock Screen widgets in languages other than German
  and Arabic, Mac widgets and watch complications in other languages, and
  the MCP fuzz families for checklist text, trash and restore, batch tools,
  and recurring `until` and `count` edits.
- Whether the system decides an intent's lock-screen access from the built
  metadata or from the running app is not measured. Until
  [build 173](docs/releases/1.0.0-173.md) the metadata recorded every
  Shortcuts action as allowed on a locked device; it now records each
  action's declared policy. Check on a locked iPhone that Siri asks for an
  unlock before **Read Task** and **Export Data**, and adds a task through
  **Capture Task** without one.
- Needs a device or a person: real drags and resizes (including the Tasks
  table row drag, a task dragged from Mac Today's list onto its time grid,
  and a task dragged onto a list in the Mac sidebar, where a build made with
  the 27 SDK lets the list row itself perform the drop), undo, context menus, Full Keyboard Access, the Quick Capture
  hotkey, Open at Login, the Control Center capture control, real-finger
  calendar swipes, watch checks on hardware, iPad hardware keyboard
  shortcuts, permanent delete on an iPhone, and a repeating task completed
  from a widget on an iPhone whose app is suspended, which should arm the
  next occurrence's reminder at once.

## Waiting on the owner

- Decisions: dark and tinted app-icon art, a Share extension, and the App
  Store "Differentiate Without Color Alone" claim.
- The App Store listing, on hold until the owner resumes it. The listing
  (`apps/apple/docs/APP_STORE_METADATA.md`) carries its name, subtitle,
  description, and keywords in App Store Connect for every shipped language
  except Urdu, Hebrew, German, Dutch, Romanian, Indonesian, Malay,
  Vietnamese, Turkish, Thai, Greek, Bengali, Marathi, Telugu, and Tamil,
  whose listing copy is not written yet. Persian has no listing: App Store
  Connect offers no Persian localization. Screenshots exist for English and
  Simplified Chinese; the other locales show the English ones until their
  own are captured and uploaded. The sample datasets translate into every
  shipped language (`LorvexSampleText`), so those captures show sample
  content in their language.
- Up to five more languages, allowed by the owner on 2026-10-12 and not
  scheduled (translate them with Claude Haiku 5.5). Candidates, chosen for
  App Store reach among languages not yet shipped: Swedish, Danish,
  Norwegian Bokmål, Finnish (each `one`/`other`), and Czech
  (`one`/`few`/`many`/`other`); Hungarian and Catalan follow if a fifth slot
  is not Czech. Adding a language is more than its strings (2,700 catalog
  entries and 17 InfoPlist keys per language, measured with
  `localization_transfer.py export`): its `PLURAL_CATEGORIES` entry in
  `script/verify_localization_catalog.py`, its entry in the app's language
  list (`AppLanguageTests`), its quick-add vocabulary in
  `LorvexCaptureVocabulary.swift` with a `CaptureParser<Language>Tests` file
  and a pass of the fuzz probe, the widget and text-direction test tables,
  the App Store listing copy, and a capture review at the largest text size.
  The vocabulary and parser work is the part that needs a fluent reader.

## Standing rules

- Maintenance and its dates (TestFlight build expiry, certificates,
  toolchain, dependencies): `apps/apple/docs/release.md`, "Standing
  maintenance".
- The shipped set of thirty languages is complete
  (`apps/apple/docs/LOCALIZATION.md`, "Language coverage"), and the language
  count is capped at about thirty. Every new string carries every shipped
  language: `apps/apple/script/localization_transfer.py` exports what a
  language lacks and imports translations, and the catalog verifier and
  `LocalizationTests` reject a partial language.
- `schema/schema.sql` is the app's schema authority. Schema changes go
  through the numbered migration ladder and the sync-payload manifests
  (`schema/migrations/README.md`, `schema/sync_payload/`).

## Decided, not open

Recorded so they are not reopened without new information.

- A task repeating on the 29th or 30th skips the months that lack that day,
  as RFC 5545 says (`CalendarRecurrence.injectBymonthday`); only an anchor
  that is its month's last day becomes `BYMONTHDAY=-1` and follows month
  ends. Clamping the 29th and 30th would need a multi-day `BYMONTHDAY` with
  `BYSETPOS` that the repeat summary cannot word plainly, so it stays as is
  unless a simpler stored shape is found.
- Habit names in the widget tiles lose two to six characters on the small
  and medium widgets. The tile keeps every name at one size and tightens
  before truncating, two-line names do not fit two rows of tiles, and the
  habit's symbol and color name it too.
- No language model inside the app, on the device or in Apple's cloud
  (Foundation Models, Core AI, `SpotlightSearchTool`). Lorvex has no in-app
  AI runtime (`apps/apple/CLAUDE.md`, "Tech Stack"); an assistant reaches it
  through MCP or through App Intents.
- Not adopted from the 27 SDKs, because the app has no use for them:
  reordering and swipe actions outside `List` (the rows that reorder or swipe
  are already in a `List`), the URL-based document protocols (no documents),
  `AsyncImage` caching (no remote images), and AppKit's pull-to-refresh
  controller (no manual refresh, rule 12 of `apps/apple/CLAUDE.md`).
- No capture button on the Home Screen widgets. Capture is already one tap
  away in Control Center, on the Lock Screen, on the Action button, and in
  the app icon's quick action; a ＋ on a glance would repeat it (rule 12 of
  `apps/apple/CLAUDE.md`) and add chrome to a surface that stays neutral
  until something needs attention.
