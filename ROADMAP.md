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
- watchOS / Widgets design audits (need on-device).
- Direct-download DMG: the only release on the releases page is 1.0.0 (59),
  58 builds and sixteen languages behind the current build. A new release
  (tag `v1.0.0+<build>`) needs Developer ID provisioning profiles for the
  three current bundle identifiers and a notarytool credential profile. The
  policy is `apps/apple/docs/release.md`, "GitHub Releases".

- Open UI/UX work, each verified against the code but not yet done:
  - iPhone habit rows and the habit detail's Complete Today button judge
    "done" by today's count, while the Mac and the iPhone detail dial use the
    period (`HabitPeriodProgress`), so a times-per-week habit that met its
    week reads done on one surface and open on another. The iPhone rows need
    the habit's recent completions loaded to agree.
  - The iPhone milestone-goal hint says "streak length" for a weekly habit;
    the Mac hint says weeks. It needs a new string in all thirty languages.
  - Streak values read "12-day streak" on the Mac habit card and "12 days" in
    the inspector and on the iPhone; Mac Lists cards omit the list's
    description, which the iPhone Lists rows show; a habit counted several
    times a day draws its ring as segments on some surfaces and as one arc
    on others.
  - In the Tasks table at the smallest Mac window with the inspector open,
    long translated text (Russian) overflows its column by about 20 pt.
  - Calendar events offer no Copy as Text or Share action.
  - Quick add misreads lines typed in decomposed Unicode in about fifteen
    languages (`ZZCaptureParserFuzzProbeTests`, `FUZZ_NFD`).
  - Locale follow-ups: weekday and Siri list joins, a few English strings
    outside the catalogs, and the week's first day.
- Known code gaps, each confirmed by a probe or a test but not yet fixed:
  - Quick add: the decomposed-Unicode fix keeps the typed text and matches on
    a composed view with an offset table, composing per grapheme rather than
    with full NFC (NFC splits composition-excluded letters such as Devanagari
    U+0958 to U+095F); eight language suites pin the current behavior and flip
    with the fix. "[pl,de] 15h" reads as 900 minutes; Vietnamese "3 giờ 15
    phút" reads as 195 minutes; the Romanian reader drops English "in 15 min";
    a parenthesized phrase leaves "( )" in Turkish, Thai, and Greek titles.
  - Titles and list names can hold a line break when set over MCP or pasted
    into the Mac inspector; the core has no single-line title policy.
  - Cancelling a repeating occurrence whose reserved successor is already
    finished reports "can't be completed again"; it needs a cancel-specific
    refusal in all thirty languages. Two lifecycle refusals are English-only
    (`UserFacingError+Reason.swift`). Batch reopen is all-or-nothing.
  - A task repeating on the 29th or 30th skips February; clamping to the last
    day changes the stored rule shape and is a product decision.
  - Busy flags still span local fan-out in `mutateHabitReminder`, iOS sheet
    saves, and iOS `mutateTask`.
  - Stale views: an inbound calendar-only change does not reach an open iOS
    day review; an inbound habits-only change does not reach the Mac review's
    habit rows.
  - Sync convergence limits found by `SyncConvergenceSimulationTests`: a task
    hard-delete racing a concurrent edit when child edges arrive first; a tag
    delete cascading a newer live edge before a resurrecting upsert; alias
    deletes reordered before their redirects; no `habit_completion` fold.
  - Mac performance: a task mutation awaits a six-stage publishing chain, and
    each external database signal triggers a full refresh that re-indexes
    Spotlight and the calendar window.
  - Mac keyboard: list cards show Edit and Delete only on hover, and the memory
    list and plan rail have no arrow-key traversal. Mac Today's arrow keys skip
    event rows.
  - Polish: Mac icon-picker labels show raw SF Symbol names and search only
    English names; Settings > Activity shows English changelog summaries; the
    Settings group "Operations" is a vague name in every language; German
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
  is capped at about thirty. Every new string carries all thirty languages:
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
