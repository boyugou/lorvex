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
  attention"); then the findings, and changes. UI is delegated; new
  capabilities go to the owner as a proposal first.

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
    bar panel, widgets, and the Watch show no marker; the request can be set
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
    day (fixed 2026-11-09). Still on the device's day: the today highlight on
    the calendar grids and week strips (`isDateInToday`), which lay events out
    in device time, the event and snooze date chips (`LorvexDateChip`), and the
    iPhone edit sheet's Add Time proposal.
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
  - A widget's Complete only takes reminders back: a repeat's next occurrence
    is not reminded, and the badge does not change, until the phone app next
    runs, and neither the write nor a Focus filter change reaches the Watch
    until the phone app publishes.
  - Smaller: a Watch command the
    phone cannot decode is rejected on the watch after three tries without
    renumbering, and the phone then refuses every later command as a sequence
    gap.
- Read-through of the Apple Watch app, its complication, and the phone's side
  of the link (2026-11-11): every source file read, the five preview pages
  captured on the simulator from the build of 2026-10-12 (the Mac was on
  battery, so no rebuild; the pages' layout code has not changed since, the
  priority and habit colors have). Traced to the code, not reproduced on a
  watch. Found sound: the replica's workspace fence, ordering, and atomic
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
  and one older than the replica is left to the phone. The root view's
  spinner, which on a cleared day took the pages down on every check-in and
  capture, now shows only before the first refresh finishes. Open:
  - A rejected action reads "Action 37 wasn’t applied": the journal's sequence
    number, with neither the action nor the task named (only a capture shows
    its title).
  - A failed action is explained only on Today. The habits and capture pages
    give the failure haptic alone, a capture refused because the watch has no
    replica yet leaves its text with no reason, and on an empty Today a failed
    capture or check-in reads "Couldn’t load Today".
  - Nothing on the wrist takes back a completed task or a habit check-in, and
    the wire has no reopen or uncheck. A few seconds' grace before the command
    is journaled would cover a mistaken tap with no protocol change.
  - An error the phone does not classify (`StoreError.invariant`,
    `StoreError.staleVersion`) is answered as retryable without limit, so one
    such command holds every later one back with no way out on the watch;
    related to the sequence gap above.
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
  keyboard shortcuts, and permanent delete on an iPhone.
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
