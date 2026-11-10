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
- watchOS / Widgets design audits (need on-device).

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
  - Polish: Settings > Diagnostics and the activity log show English changelog summaries; German
    Memory sheet titles truncated at 375 pt (rechecked 2026-10-12 at 402 pt:
    "Neuer Gedächtniseintrag" wraps to two lines in the title bar's three-step
    fit, so only a 375 pt device could still show it; none is installed here); the Urdu Today medium widget shows
    one row.
- Read-only audit of data saving and sync (2026-11-09). Each item was traced
  to the code named; none is reproduced by a test and none is fixed yet.
  Checked and found sound: the CloudKit transport's change tags, conflict
  classes, zone deletion, account binding, and end-to-end encrypted fields; the
  HLC lanes; the outbox coalescing; the task editors, which write only the
  fields the user changed; a habit day that holds both a skip and a check-in
  after a merge (reads count it as kept).
  - Lists and habits merge as whole rows, and a reorder writes every shifted
    row: `applyReorder` (`SwiftLorvexCoreService+Reorder.swift`) rewrites
    `position` and sends each changed row whole at a new version, and
    `ApplyList.applyListUpsert` and `ApplyHabit` take the whole row of the newer
    version. A rename, an archive, or a target change made on another device
    while it was offline is replaced by the reordering device's older copy of
    that row. Tasks and calendar events merge field by field and are not
    affected. Syncing the order as its own register, or as one order record,
    would end it.
  - Two actions write back fields they did not change: the Mac's snooze
    (`AppStoreSnoozeActions.snoozeTask`) and the iPhone's plan-for-a-day
    (`MobileStoreTaskActions.planTask`) load the task and then call the
    force-set `updateTask(id:title:notes:…)` in a second transaction. A change
    the assistant or a sync apply commits between the two is reverted, with a
    new version that every device then takes. `TaskUpdateDraft` with the one
    field avoids it; the Shortcuts update already does.
  - A failed refresh on the Mac clears everything, the unsaved task draft
    included: `performLocalRefresh` runs seven reads without a guard, and its
    `catch` calls `clearLoadedStateAfterRefreshFailure`, which resets
    `taskDetailStorage` (the title and notes being typed). One read that throws
    blanks every surface. The iPhone's `refresh()` clears its snapshots the same
    way (`loadLocalSurfaces(clearOnFailure: true)`), which a refresh caught by
    the background suspension can reach.
  - A set-aside database leaves no lasting trace. When the open path
    quarantines a corrupt file (`LorvexStore.open`,
    `recoverManagedByQuarantine`), nothing readable is copied into the new
    database, the unsent outbox rows stay in the set-aside file, and the notice
    lives in memory in the process that did the open (`_lastDatabaseRecovery`),
    shown once. A quarantine done by the MCP helper, by a widget intent, or just
    before the app quit leaves an empty app with no explanation, and on an
    iPhone the path in the alert cannot be reached. A marker in the new
    database, a salvage pass, and an export of the set-aside file would cover it.
  - A running process does not notice a schema migration. The ladder is checked
    only at open (`SchemaMigrationRunner.checkDowngrade`). The MCP helper keeps
    running across an app update, so after a build that adds a migration it
    writes with the older build's code until its client restarts it. Comparing
    `MAX(version)` of `schema_migrations` with the value read at open, inside
    `assertCommittingDatabaseIdentity`, would refuse those writes.
  - iOS suspension does not wait for work in flight.
    `BackgroundDatabaseWork.end()` and `expire()` post the suspension and end
    the background task at once. GRDB's `suspend()` only interrupts, so an
    operation in flight still holds its SQLite lock and the `flock` on
    `<db>.storage-lock` until its thread unwinds; a process suspended inside
    that window is terminated with `0xdead10cc`. Waiting, with a bound, for
    `activeStoreOperations` to reach zero before ending the task closes it.
  - A restore cut short on an iPhone cannot be finished by running it again.
    `MobileStore.applyDataImport` holds no background task, so leaving the app
    suspends the database at once (the suspension flush skips its sync pass
    while an import runs) and every later record fails. The tasks already
    created have not had their deferred pass (`applyDeferredTaskWork`:
    dependencies, the cancelled or in-progress status, the original dates), and
    a second run skips them because they exist. Holding
    `BackgroundDatabaseWork` for the import, and finishing the deferred pass for
    a task the same archive created earlier, would cover it.
  - The assistant cannot tell that nothing is syncing. With the Mac app quit,
    the MCP helper's writes queue in the outbox and arm no notification until
    the app next runs, and `get_sync_status` reports only queue counts
    (`sync_backend_kind` is `unknown`). A heartbeat the app writes (last run,
    sync mode, last completed pass) would let the tools say so.
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
  same standing: traced to the code, not reproduced, not fixed. Found sound:
  the daily review on both platforms, capture, the Mac quit handshake for the
  drafts it covers, dirty-draft preservation across refreshes, and no write
  error swallowed with `try?`.
  - The Mac inspector loses what was just typed. The task draft autosaves 1.2
    seconds after the last keystroke, and three paths replace the draft inside
    that delay without saving it. Clicking another row on Today, a list, or the
    Calendar: `selectTaskFromList` assigns the selection and calls
    `syncSelectedTaskDraft()` at once, so the draft already belongs to the new
    task when `TaskDetailView`'s `onChange(of: selectedTaskID)` asks whether the
    old one changed (the Tasks workspace only assigns the id and saves; the
    tests assign the id too, which is why they pass). Closing the inspector
    (its close button, Escape, the open row again, or moving to Habits, Memory,
    or Reviews): the `selectedTaskID` `didSet` clears the draft for nil before
    the view can save. Start, Pause, and Reopen from the inspector set
    `taskDetailDraftTaskID = nil` and refill the draft from the stored record.
    The notes editor has no save on blur, so a paragraph typed without a pause
    is lost whole.
  - Also on the Mac inspector: an autosave that fails while moving to another
    task drops that draft, and the next successful action clears its alert
    (`loadSelectedTaskDetail`); the title autosave stores the trimmed title and
    refills the field, so a trailing space typed before a pause disappears
    ("Buy milk" then "and eggs" joins); a checklist row committed with trailing
    whitespace keeps the inspector counted as edited, and it stops taking the
    task's changes from other devices until it is selected again.
  - Quit on the Mac covers the task draft, the review, and sticky notes
    (`hasPendingAutosaveDraftForTermination`) but not the fields that commit on
    blur: a checklist row's text and a habit's name and cue are lost when ⌘Q is
    pressed with the cursor in them. A task whose title was emptied cancels
    Quit with no message, since the save declines and the draft stays pending.
    A sticky note saves only when its window loses focus, closes, or the app
    quits, so a crash loses everything typed since.
  - Accepting suggested times writes the suggestion as it was computed, on both
    platforms (`acceptSuggestedDayTimes`): `saveDayTimes` takes the time off
    every unfinished task timed that day that the suggestion does not list, so a
    time set after Suggest (in the inspector, by a drag, by the assistant) is
    removed, and an accept after midnight plans for the previous day.
  - Text cleared before the write is known to have worked: the iPhone
    checklist composer (`MobileTaskComposerRows`), where an add made while the
    task's previous write is in flight is refused without a message, and the
    Mac's inline quick add (`QuickAddRow`). The Mac checklist and the Quick
    Capture window keep the text on a failure.
  - Sheets that save the whole record from a draft filled when they opened
    write back fields the user did not touch: list edit on both platforms, the
    iPhone habit editor, the event editor on both, and a calendar drag, which
    sends the block's title and location with the new time. A change made
    elsewhere while the sheet was open is reverted. The task editors and the
    Mac habit inspector send only changed fields.
  - Smaller: creating a memory entry under a key that exists replaces that
    entry without asking, and on the Mac Edit on a row replaces unsaved composer
    text; on the iPhone only the memory composer refuses a swipe-to-dismiss
    with unsaved text; the iPhone Undo banner does nothing when another task
    write is running.
- Read-only audit of notifications, calendar mirroring, widgets, the Watch,
  and App Intents (2026-11-09), same standing: traced to the code, not
  reproduced, not fixed. Found sound: reminder triggers as true instants and
  the shared 60-request budget, the widget snapshot file (atomic write, lock,
  ordering), the Watch replica ordering and command journal, the bracketing of
  every intent runner, the Spotlight prune, and the EventKit permission and
  privacy-tier checks. Four items of
  `apps/apple/docs/reference/apple-official/APPLE_NOTIFICATION_REMINDER_AUDIT.md` still
  stand (N5, N6, N8, N10).
  - A change that reaches a locked iPhone by push is applied but not acted on.
    A background wake runs only the sync pass
    (`MobileStore.handleCloudKitPush`): reminders, the badge, the widget
    snapshot, and the Watch replica are re-planned only by a foreground
    refresh, a local write, or a pass the engine reports on its own, and
    `syncNow()` keeps that report for its caller. A reminder the assistant adds
    on the Mac is not armed on the phone, and the reminder of a task completed
    elsewhere still fires, until the app is opened or the background refresh
    runs (four hours at the soonest). The comment in
    `ReminderBackgroundRefresh.swift` says a push replenishes the window.
  - After Complete or Defer on a lock-screen reminder, nothing else is
    updated. `runTaskWrite` closes its database bracket, which suspends the
    store again, and only then posts `.lorvexBackgroundMutationApplied`; the
    refresh that answers it reads a suspended store, fails, clears the loaded
    snapshots, and sets an error (`loadLocalSurfaces(clearOnFailure: true)`).
    The widget still lists the task, the badge stays, and the task's other
    reminders stay armed until the app is opened. Any Siri or Shortcuts write
    in a backgrounded process ends the same way. The Watch receiver refreshes
    inside its bracket and is right.
  - A weekly habit on several days gets one reminder a week. For `.weekly` and
    `.timesPerWeek` the planner's period is the ISO week
    (`HabitReminderOccurrencePlanner.periodBounds`), and
    `deliveredInSamePeriod` drops every later day of a week in which one
    reminder was delivered, although the habit needs one check-in per day.
    Monday's reminder for a Monday and Wednesday habit cancels Wednesday's at
    the next re-plan. The tests never stamp a delivery, so they do not reach it.
  - Calendar events deleted in Apple Calendar can stay in Lorvex. The ingest
    removes stale rows only among those whose `start_date` is inside the window
    (`ProviderRepo.getProviderEventKeys`), while the timeline shows rows that
    started earlier: a Monday to Friday event deleted on Wednesday stays for
    the rest of the week, and a repeating series deleted elsewhere keeps its
    stored master once the window has moved past the master's start.
  - A repeating calendar series is mirrored from the first occurrence in the
    window (`EventKitSeriesAssembly`: `group.first { !$0.isDetached }`), and
    its `COUNT` is copied as is: a ten-week series ingested at week nine shows
    ten more weeks, and a Calendar left on next month makes every refresh store
    masters that start next month.
  - What Lorvex wrote into Apple Calendar is updated only by Mac actions
    (`AppStoreCalendarWriteBack`): an event deleted or moved on the iPhone or by
    the assistant keeps its old copy in Apple Calendar, which Lorvex itself
    hides. The lookup reaches back 90 days, so editing an older event writes a
    second copy.
  - iPhone widgets show "Open Lorvex to refresh" from midnight until the app is
    opened: the background wake re-plans reminders and the badge
    (`replenishReminderWindow`) but does not publish the widget snapshot, and
    no entry for the new day is prepared ahead.
  - A write from outside the app process changes no notification: a widget
    tap completes a task whose reminder still fires, and neither it nor a Focus
    filter change reaches the Watch until the phone app publishes.
  - Smaller: the two task entity queries of App Intents
    (`LorvexTaskEntityQuery`, `LorvexReopenableTaskEntityQuery`) read without
    background access and drop the error, so a saved task in a Shortcuts
    automation may not resolve while the app is suspended. A Watch command the
    phone cannot decode is rejected on the watch after three tries without
    renumbering, and the phone then refuses every later command as a sequence
    gap. Every snapshot publish reloads all widget timelines, also when the
    write was refused as older, and the Mac publishes twice per local write.
    `EKEventStoreChanged` is handled once per notification without coalescing.
    A time-zone change that keeps the same day does not re-plan habit reminders.
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
