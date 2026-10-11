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
