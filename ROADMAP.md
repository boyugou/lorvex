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
    a parenthesized phrase leaves "( )" in Turkish, Thai, and Greek titles.
  - Batch reopen is all-or-nothing. Every lifecycle refusal a person can reach
    is worded in `UserFacingError+Reason.swift`; the cases it leaves to the
    core's English (a start on an already open task, a finished-to-finished
    transition that is not complete or cancel) are not reachable from the UI.
  - A task repeating on the 29th or 30th skips February; clamping to the last
    day changes the stored rule shape and is a product decision.
  - Sync convergence limits found by `SyncConvergenceSimulationTests`: a task
    hard-delete racing a concurrent edit when child edges arrive first; a tag
    delete cascading a newer live edge before a resurrecting upsert; alias
    deletes reordered before their redirects; no `habit_completion` fold.
  - Mac performance: a task mutation awaits a six-stage publishing chain, and
    each external database signal triggers a full refresh that re-indexes
    Spotlight and the calendar window.
  - Mac keyboard: list cards show Edit and Delete only on hover.
  - Polish: Settings > Activity shows English changelog summaries; German
    Memory sheet titles truncate at 375 pt; the Urdu Today medium widget shows
    one row.
- Coverage not yet captured: the largest accessibility text sizes in languages
  other than English and Chinese, iPad routes other than Review, the Habits,
  Progress, and Lock Screen widgets in most languages, Mac widgets and watch
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
  allowed it on 2026-10-12; translate them with Claude Haiku 5.5). Every new
  string carries every shipped language:
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
