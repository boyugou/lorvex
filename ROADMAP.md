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
    phút" reads as 195 minutes; the Romanian reader drops English "in 15 min";
    (a parenthesized phrase left "( )" in the title in every language; the title cleanup now removes the pair).
  - Batch reopen is all-or-nothing. Every lifecycle refusal a person can reach
    is worded in `UserFacingError+Reason.swift`; the cases it leaves to the
    core's English (a start on an already open task, a finished-to-finished
    transition that is not complete or cancel) are not reachable from the UI.
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
    redirect arrives), and leaves no pending entries. The runs are not bit-for-bit repeatable (ids and
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
  - Polish: Settings > Activity shows English changelog summaries; German
    Memory sheet titles truncated at 375 pt (rechecked 2026-10-12 at 402 pt:
    "Neuer Gedächtniseintrag" wraps to two lines in the title bar's three-step
    fit, so only a 375 pt device could still show it; none is installed here); the Urdu Today medium widget shows
    one row.
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
