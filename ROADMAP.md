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
- CarPlay runtime activation: entitlement approval pending from Apple.
- watchOS / CarPlay / Widgets design audits (need on-device).

### Localization
- Grow from the twenty-eight shipped languages to the 31 locales lorvex.app is
  published in (`apps/apple/docs/LOCALIZATION.md`, "Language coverage"), one
  batch of languages at a time. Each batch is prepared on its own worktree
  branch with `apps/apple/script/localization_transfer.py` and merges with
  `localization_transfer.py import --from-checkout` once the catalog verifier,
  `LocalizationTests`, and a headless capture review pass for every language
  in it. Spanish (`es`), Hindi (`hi`), Arabic (`ar`), French (`fr`), Italian
  (`it`), Brazilian Portuguese (`pt-BR`), Russian (`ru`), Ukrainian (`uk`),
  Polish (`pl`), Japanese (`ja`), Korean (`ko`), Traditional Chinese
  (`zh-Hant`), Persian (`fa`), Urdu (`ur`), Hebrew (`he`), German (`de`), Dutch
  (`nl`), Romanian (`ro`), Indonesian (`id`), Malay (`ms`), Vietnamese (`vi`),
  Turkish (`tr`), Thai (`th`), Greek (`el`), Bengali (`bn`), and Marathi (`mr`)
  have shipped. The rest, Telugu, Tamil, and Malayalam, follow as one batch.
- The App Store listing (`apps/apple/docs/APP_STORE_METADATA.md`) carries its
  name, subtitle, description, and keywords in App Store Connect for every
  shipped language except Urdu, Hebrew, German, Dutch, Romanian, Indonesian,
  Malay, Vietnamese, Turkish, Thai, Greek, Bengali, and Marathi, whose listing
  copy is not written yet. Persian has no listing: App Store Connect offers no Persian
  localization.
  Screenshots exist for English and Simplified Chinese; the other locales show
  the English ones until their own are captured and uploaded. The sample
  datasets translate into every shipped language (`LorvexSampleText`), so
  those captures show sample content in their language.

### Shared
- `schema/schema.sql` is the app's schema authority. Schema changes go through
  the numbered migration ladder and the sync-payload manifests
  (`schema/migrations/README.md`, `schema/sync_payload/`).
