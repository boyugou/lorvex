# Localization

Lorvex Apple ships Xcode String Catalogs (`Localizable.xcstrings`) that contain
all user-facing strings. The catalogs are the single source of truth for
localized text. English (`en`) is the source language, but the infrastructure is
not an English/Chinese pair system. Shipped locales are discovered from the
catalogs themselves and then enforced across every catalog and shipping bundle,
so future languages can be added incrementally without rewriting tests,
verifiers, or local build scripts.

## Language and locale policy

Localization resolves two independent things, and Lorvex chooses them
separately:

- **Display language** — which translation of a string to show.
- **Formatting locale** — how numbers, dates, and CLDR plural categories render.

**Display language, by surface.** The rule is "follow whoever is asking":

| Surface | Display language follows | How it resolves |
|---|---|---|
| Main app UI (macOS / iOS / iPadOS) | the app's selected language — the system language, or an in-app override | in-process against the module bundle (`Text("key", bundle:)`, `String(localized: … bundle:)`) |
| Widgets, Watch, CarPlay | the host process's language (system language) | in-process against the module bundle |
| Notifications | the app/system language at the time the notification is scheduled | in-process, eager (e.g. `String(localized: "notification.snooze.body", table: "Localizable", bundle: MobileL10n.bundle)`) |
| App Intents / Shortcuts / Siri / Spotlight | the **invoking request's** locale — which can differ from the app-process language | deferred `LocalizedStringResource`, resolved by the framework at presentation |

The in-app language override is applied through the `AppleLanguages` user
default at launch (`AppLanguage`), so it takes effect on the next relaunch and
every in-process string lookup resolves against it. Formatting locale currently
continues to follow the system `Locale`; aligning manually constructed date and
relative-time formatters with an in-app language override is tracked as a
separate finalization item. Where a catalog entry defines native plural
variations, `String(localized:)`/`LocalizedStringResource` integer
interpolation selects the CLDR category automatically. English (`en`, the
source language) and Simplified Chinese (`zh-Hans`) are the shipped languages.
English uses the `one`/`other` plural categories and Chinese only `other`, so
plural variations stay small; every UI string needs exactly one translation.

### The App-Intent request-locale seam

An App Intent can run outside the app — Siri, the Shortcuts app, Spotlight, an
automation — in a locale that is not the app process's language. The strings the
system speaks or shows (intent `title`/`description`, `@Parameter` titles and
prompts, `AppShortcut` phrases, `AppEnum` case representations, and the
`IntentDialog` / confirmation prompts returned from `perform()`) must therefore
be **deferred** values the framework resolves against the request locale, not
strings resolved eagerly in the app process.

The correct type is `LocalizedStringResource`, always with an explicit `table:`
and `bundle:` (a framework catalog is not in `Bundle.main`):

```swift
// Dialog — resolves in the request locale, runtime value interpolated:
return .result(
  dialog: IntentDialog(
    LocalizedStringResource(
      "system.task.capture.dialog", defaultValue: "Captured \(title) in Lorvex.",
      table: "Localizable", bundle: SystemL10n.bundle)))

// Count-driven dialog — the interpolated Int drives native plural selection:
return .result(
  dialog: IntentDialog(
    LocalizedStringResource(
      "system.task.batch.move.dialog_count", defaultValue: "Moved \(moved.count) tasks.",
      table: "Localizable", bundle: SystemL10n.bundle)))
```

The anti-pattern is any `IntentDialog(stringLiteral:)`, including one that wraps
a composed local variable or a runner-produced summary. Composition does not
restore the request locale: the `String` was still finalized in the app process
before Siri or Shortcuts received it. Lorvex therefore has no production
`stringLiteral:` dialog exception. Entities likewise retain raw counts and
schedule fields and build their `DisplayRepresentation` copy from deferred
resources instead of storing an eagerly localized subtitle.

The dialog resource's `defaultValue` carries the source (`en`) text and all
runtime arguments; the catalog key supplies the per-language format at
resolution time. Full-sentence resources are preferred over independently
localized fragments because translators can reorder every argument. The
`appIntentDialogsUseRequestLocaleResources` test fails if a
`stringLiteral:` dialog is reintroduced.

### App Shortcut phrases and short titles

`LorvexShortcutsProvider` (an `AppShortcutsProvider`) registers the flagship
`AppShortcut`s. Its two localizable arguments have different types and therefore
localize through two different catalogs:

- **`shortTitle`** is a `LocalizedStringResource`, so it routes through the
  module catalog exactly like every intent `title`: keyed under
  `system.shortcut.<action>.short_title` with an explicit
  `table: "Localizable", bundle: SystemL10n.bundle`. These keys live in
  `Sources/LorvexSystemIntents/Resources/Localizable.xcstrings` and are validated
  by `verify_localization_catalog.py` (as raw-`LocalizedStringResource` bundle
  references, below).

- **`phrases`** are `AppShortcutPhrase` values — a distinct type that cannot take
  a `table:`/`bundle:` argument and does not resolve through
  `Localizable.xcstrings`. App Intents localizes them only through a separate,
  specially-named `AppShortcuts.xcstrings`
  (`Sources/LorvexSystemIntents/Resources/AppShortcuts.xcstrings`), keyed by the
  English phrase with the literal `${applicationName}` token (Swift's
  `\(.applicationName)`). Every phrase must contain that token. This catalog is
  consumed by Xcode's `ExtractAppIntentsMetadata` build phase, which produces the
  `Metadata.appintents` bundle from the provider and its linked framework —
  `swift build` does not run that phase, and `verify_localization_catalog.py`
  does not validate it (it validates only the module `Localizable.xcstrings`
  catalogs). The Swift `phrases:` array stays as the English source literals;
  translators fill each language in `AppShortcuts.xcstrings`.

## Catalog location

There are eight catalogs — one per UI module, plus LorvexCore's for the words
that name shared data rather than a surface's controls — each resolved against
its owning module bundle:

```
Sources/LorvexApple/Resources/Localizable.xcstrings           → Text("key", bundle: LorvexL10n.bundle) / String(localized:…, bundle: LorvexL10n.bundle)
Sources/LorvexMobile/Resources/Localizable.xcstrings          → Text("key", bundle: MobileL10n.bundle) / String(localized:…, bundle: MobileL10n.bundle)
Sources/LorvexSystemIntents/Resources/Localizable.xcstrings   → LocalizedStringResource(…, bundle: SystemL10n.bundle)
Sources/LorvexWatch/Resources/Localizable.xcstrings           → Text("key", bundle: WatchL10n.bundle) / String(localized:…, bundle: WatchL10n.bundle)
Sources/LorvexWidgetViews/Resources/Localizable.xcstrings     → Text("key", bundle: WidgetL10n.bundle) / String(localized:…, bundle: WidgetL10n.bundle)
Sources/LorvexWidgetKitSupport/Resources/Localizable.xcstrings → String(localized:…, bundle: WidgetSupportL10n.bundle) / LocalizedStringResource(…, bundle: WidgetSupportL10n.bundle)
Sources/LorvexCarPlay/Resources/Localizable.xcstrings         → String(localized:…, bundle: CarPlayL10n.bundle)
Sources/LorvexCore/Resources/Localizable.xcstrings            → String(localized:…, bundle: CoreL10n.bundle)
```

(`LorvexCore` is linked by every surface, so a word it resolves reads the same
on the Mac, iPhone, widgets, and in Shortcuts. Today it holds one entry, the
seeded Inbox's name; see the Simplified Chinese conventions below.)

(`LorvexWidgetKitSupport` is the shared widget snapshot/timeline layer — native
APIs resolve the strings baked into its render model plus status / relative-age
labels against `WidgetSupportL10n.bundle`, including the three cross-module
consumers in the Watch complication. The four WidgetKit gallery
name/description pairs stay deferred `LocalizedStringResource`s so WidgetKit
chooses the host locale when it presents the gallery. The Watch complication's
gallery name and description follow the same deferred pattern against
`WatchL10n.bundle`.)

Each catalog-bearing target declares `resources: [.process("Resources")]` in
`Package.swift`; XcodeGen auto-bundles `.xcstrings` found under the target's
source path. Framework calls MUST pass the owning module's `bundle:` explicitly:
a bare `Text("…")` resolves against `Bundle.main` (the host app), not the
framework catalog. All modules use native `Text` / `String(localized:)` or
deferred `LocalizedStringResource` directly. `LorvexL10n`, `MobileL10n`,
`SystemL10n`, `WatchL10n`, `WidgetSupportL10n`, `WidgetL10n`, `CarPlayL10n`,
and `CoreL10n` are resource-location facades only; native String Catalog APIs
resolve every string at runtime. Widget configuration data is storage-only:
`LorvexWidgetConfiguration` does not carry localized gallery copy and there is
no shared gallery-copy resolver — each widget definition owns its deferred
metadata and uses the appropriate catalog bundle.
Every bundle accessor uses the `#if SWIFT_PACKAGE` pattern
(`Bundle.module` under SwiftPM, `Bundle(for:)` in the native XcodeGen build).

`script/verify_localization_catalog.py` (in `verify_all.sh`) validates all eight
catalogs: structure, that every key carries every language declared by any
Apple catalog, and that every remaining module helper call, bundle-qualified native
`Text` / `String(localized:)`, and bundle-owned `LocalizedStringResource`
exists in the matching catalog. Each module scan must find a real reference, so
a broken scanner cannot pass vacuously. The JSON loader rejects duplicate
object keys instead of silently keeping the last value, and Swift comments are
masked before every reference scan so documentation examples cannot create
fake live keys. A dotted catalog-shaped bare `Text("typo.key")` and an implicit
`LocalizedStringResource = "…"` initializer also fail even when the typo is not
present in any catalog. Placeholder validation understands that
one locale may use an ordinary `.strings` format while another uses typed
plural substitutions in `.stringsdict`, and preserves integer length modifiers
so an ABI-sensitive `%d` / `%lld` mismatch cannot pass as equivalent. Every
plural leaf is validated against the source locale's full argument-position and
type union; a leaf may intentionally omit a rendered count, but may not invent
an argument or reinterpret its type. It also checks the raw
`LocalizedStringResource("key", … table: "Localizable", bundle: <Helper>.bundle)`
form that App-Intent metadata uses (titles, `@Parameter` labels, AppEnum case
representations, dialog / confirmation prompts, and App Shortcut short titles):
the key must exist in the catalog its `bundle:` argument names. Without that, a
string reached only through an App Intent could name a key the catalog does not
carry and still pass, rendering in English regardless of the request locale.
For LorvexApple and LorvexMobile, the verifier additionally rejects literal native
`String(localized:)` / `LocalizedStringResource` calls without the exact
`Localizable` table and owning bundle (`LorvexL10n.bundle` or
`MobileL10n.bundle`), plus catalog-owned `Text` literals without that bundle.
It also rejects source-language prose copied into every
non-source Mobile locale, including prose nested in ordinary plural variations
or named plural substitutions; a single locale may legitimately match English,
pure placeholder templates are ignored, and intentional invariant product names
are explicitly allowlisted. This keeps framework ownership and translation
quality explicit with no runtime helper layer to fall back on.
Adding `fr`, `ar`, `ja`, `zh-Hant`, or any other
locale should be a catalog + bundle metadata change, not a verifier-code change.
The required language set is the union discovered from the catalogs, so a locale
introduced in one catalog must be completed across every catalog and shipping
bundle.

This global locale-set rule is intentional. It keeps the app ready for broad
language coverage: no verifier, Swift test, or Info.plist should encode a fixed
English/Chinese pair or any other hardcoded language pair. The only hardcoded
language is the source language (`en`), because SwiftPM and Xcode need one
canonical fallback value for development builds.

## How to add a new translatable string

1. Open the relevant `Localizable.xcstrings` file in any text editor or Xcode's String Catalog editor.

2. Add a new entry under `"strings"`. Use dot-namespaced keys (`<surface>.<context>.<item>`):

   ```json
   "habits.empty.no_habits_title" : {
     "comment" : "Title shown when the habits workspace is empty",
     "extractionState" : "manual",
     "localizations" : {
       "en" : {
         "stringUnit" : {
           "state" : "translated",
           "value" : "No Habits Yet"
         }
       }
     }
   }
   ```

   Always set `"extractionState": "manual"`. This prevents Xcode from dropping the entry when it cannot find a matching source reference (common in SwiftPM projects where Xcode's string extraction doesn't run automatically).

3. In the Swift view or support file, use a native lookup with the owning
   table and bundle explicitly named:

   ```swift
   Text(
     "habits.empty.no_habits_title",
     tableName: "Localizable",
     bundle: LorvexL10n.bundle,
     comment: "Title shown when the habits workspace is empty"
   )
   ```

   For eager strings, accessibility text, and values with interpolation:

   ```swift
   String(
     localized: "habits.summary.count",
     defaultValue: "\(count) habits",
     table: "Localizable",
     bundle: LorvexL10n.bundle
   )
   ```

   For `Label` titles where a `LocalizedStringResource` is accepted directly:

   ```swift
   Label(someSelection.localizedTitle, systemImage: "repeat.circle")
   ```

4. The source-reference and reverse-reference gates discover literal keys
   automatically. Add an explicit required-key assertion only when the key is a
   release contract that must survive even while temporarily unreferenced.

5. Run `python3 script/verify_localization_catalog.py` and the relevant Swift tests to confirm nothing is broken.

## Simplified Chinese conventions

The `zh-Hans` catalogs follow Apple's Simplified Chinese usage and keep one term
per concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| List (a task list) | 列表 | 清单 names a task's checklist |
| Checklist | 清单 | an item is 清单项 |
| Someday | 将来某天 | quoted as “将来某天” inside a sentence |
| Plan block | 时间块 | |
| A block's end (Until 21:30) | 21:30 结束 | pairs with 21:30 开始 for a block ahead |
| Suggested times (a proposed schedule) | 建议时间 | the suggested list heads 建议的时间; once saved, the day's times are 当前日程 |
| Overdue | 逾期, 已逾期 | 已过期 means expired, as a stale saved watch action is |
| Open (a task not yet done) | 未完成 | 进行中 is the In Progress status and the block running now; a compact widget count may say 待办 |
| Counting tasks | 项 (你完成了 1 项任务, 还剩 3 项) | what is heard (Siri dialogs, VoiceOver labels) says 个, which reads more naturally aloud |
| Review (the day and the week) | 回顾 | in Shortcuts and Siri too |
| Capture (quick add) | 添加任务 | |
| Inbox (the seeded list) | 收件箱 | shown while the list keeps its seeded name |
| Assistant context (a task's AI notes) | 助手上下文 | |
| Copy, restart | 复制, 重启 | |
| Dock | 程序坞 | |

- Punctuation is full width (，。？！：；), and quotation marks are “ ” and ‘ ’.
- A space separates Chinese from Arabic numerals and Latin words ("还剩 5 项任务",
  "90 分钟", "iCloud 同步"). Example text that a user types, such as "30分钟" in
  the capture hint, is written the way people type it.
- Chinese text may wrap between any two characters, including after a "#". The
  capture hint therefore writes “#列表名” with an invisible word joiner
  (U+2060) after the "#", so the example never splits across lines.
- A count and the noun it counts go through a format with positional
  specifiers, never concatenation in code, because the word order differs:
  `common.count_label` is `%1$lld %2$@` in English and `%2$@ %1$lld` in
  Chinese ("接下来 4").
- Sentences assembled from several catalog entries are joined with
  `LorvexReviewSentence.join`, which puts no space after a full-width stop.
- The serif voice (a review's sentence, the menu bar sentence, an assistant's
  aside) is set with `Text(_:serifVoice:)`. On macOS it sets the Chinese runs of
  a string in Songti directly, because New York's own fallback to Songti lays
  the full-width marks out one and a half ems wide.
- The seeded Inbox list stores the English name "Inbox" as ordinary synced
  data that assistants read. Surfaces show every list through
  `LorvexList.displayName`, which gives the seeded Inbox the `list.inbox.name`
  entry of LorvexCore's catalog until someone renames it. A list editor opens
  on the shown name and stores the seeded name again when it is saved
  unchanged (`LorvexListNaming.nameToStore`), and search and a typed `#list`
  accept both names.
- Siri and Shortcuts phrases live in `AppShortcuts.xcstrings`. A Chinese phrase
  keeps spaces around the app name, as around any Latin word
  ("在 ${applicationName} 中添加任务").
- The verifier rejects a translation that copies the English text, except the
  product and technology names in its `IDENTICAL_TRANSLATION_ALLOWLIST`, and
  requires every App Shortcuts phrase to be translated and to name the app
  exactly once.

## How to add a new locale

Every catalog and every shipping bundle must carry the same language set, so a
locale is added everywhere in one change:

1. Add a `<lang>` block with `state: translated` to every entry in each of the
   eight String Catalogs under `Sources/*/Resources/*.xcstrings` (Xcode's String
   Catalog editor does this per catalog; a small script that walks the JSON is
   fine too). Plural entries need every CLDR category the language uses.
2. Add `Config/InfoPlist/<Target>/<lang>.lproj/InfoPlist.strings` for each
   shipping target, translating every key of the English file beside it.
3. Add the language to `AppLanguage` (`Sources/LorvexCore/Support/AppLanguage.swift`)
   with its endonym so the in-app language picker offers it.
4. Sync bundle metadata so the OS includes the locale in app, complication, and
   widget bundles, and in the Info.plist embedded in the debug executable
   (`Config/LorvexAppleSwiftPM-Info.plist`, described under the headless
   screenshots below):

   ```sh
   python3 script/verify_localization_catalog.py --write-bundle-localizations
   ```

5. Run `python3 script/verify_localization_catalog.py`. The verifier derives
   the required language set from the catalogs and fails until every catalog and
   shipping bundle has the same complete set. If one catalog has `fr`, every
   other catalog must also have `fr`; if one Info.plist omits `fr`, the verifier
   fails.

6. Run the app with the scheme's application language set to the new locale
   (`Edit Scheme → Run → Options → Application Language`).

## How to test with a different locale

**In Xcode (simulator or device):**

1. Edit the run scheme: `Product → Scheme → Edit Scheme`.
2. Select `Run → Options`.
3. Set `Application Language` to the desired locale.
4. Build and run; native bundle-qualified strings and deferred resources switch
   to the selected application language.

**In command-line tests:**

SwiftPM test runs do not switch a catalog's language through process locale
environment variables. `LocalizationTests` instead loads specific compiled
`.lproj` sub-bundles and asserts real native translated output and CLDR plural
selection; it also verifies catalog structure and complete language parity.
Scheme-based simulator/device checks remain useful for layout and OS-owned
surfaces, not for proving basic lookup semantics.

**Headless screenshots:**

The capture scripts take extra launch arguments, so a visual pass in another
language needs no scheme change:

```sh
LORVEX_TOUR_EXTRA_ARGS="-AppleLanguages (zh-Hans) -AppleLocale zh_CN" \
  script/ui_tour_macos.sh light /tmp/shots-zh
LORVEX_SIM_EXTRA_ARGS="-AppleLanguages (zh-Hans) -AppleLocale zh_CN" \
  script/ios_sim_screenshots.sh /tmp/shots-zh light today tasks
```

The macOS tour runs the unbundled debug executable. When an executable declares
no localizations of its own, Foundation matches every module bundle in the
process to the development language, so `String(localized:bundle:)` stays
English whatever `-AppleLanguages` says, while a `LocalizedStringResource`,
which resolves against its own locale, follows it. Debug builds therefore embed
`Config/LorvexAppleSwiftPM-Info.plist`, which declares the shipped languages, as
the executable's `__TEXT,__info_plist` section (see the `LorvexApple` target in
`Package.swift`); packaged apps declare the same list in their bundle
Info.plist. The plist has no `CFBundleIdentifier`, so the debug executable keeps
its own `UserDefaults` domain.

## Xcode workflow for translating

1. Generate the Xcode project: `script/verify_xcodegen_project.sh`.

2. Open `LorvexAppleNative.xcodeproj`. The `Localizable.xcstrings` file appears under `LorvexApple/Resources`.

3. Select the catalog file in the project navigator. The String Catalog editor opens showing all keys, their comments, and per-locale translation state.

4. For each key in `needs_review` or `stale` state, enter the translated text and set the state to `translated`.

5. Export for translation: `Editor → Export for Localization` produces an `.xcloc` bundle that can be sent to a translation service.

6. Import translated `.xcloc`: `Editor → Import Localizations`.

## Adding strings to mobile, intents, watch, widget, and CarPlay targets

`LorvexMobile` (iOS/iPadOS), `LorvexWatch` (watchOS), and
`LorvexWidgetViews` (home-screen widgets) each ship their own String Catalog
under the target's `Resources/` directory. `LorvexSystemIntents` also ships a
catalog for App Intents, Shortcuts, Siri, and Spotlight metadata, and
`LorvexCarPlay` ships a catalog for driver-safe template text. Each catalog is
reached through its own owning bundle — `MobileL10n.bundle`,
`SystemL10n.bundle`, `WatchL10n.bundle`, `WidgetL10n.bundle`,
`WidgetSupportL10n.bundle`, or `CarPlayL10n.bundle` — not
`LorvexL10n.bundle`, which owns the LorvexApple app-shell catalog.

To add a translatable string to one of these surfaces:

1. Add the entry to that module's `Localizable.xcstrings` with the source
   language and every currently shipped locale, following the dot-namespaced
   key convention and `"extractionState": "manual"` rule above.
2. Reference it with a native API and the owning module bundle:
   ```swift
   Text("settings.section.appearance")  // ✗ bare framework lookup uses Bundle.main
   Text("settings.section.appearance", bundle: MobileL10n.bundle)  // ✓ SwiftUI
   String(localized: "watch.session.end", defaultValue: "End Session",
          table: "Localizable", bundle: WatchL10n.bundle)  // ✓ imperative/a11y
   LocalizedStringResource("system.open.title", defaultValue: "Open Lorvex",
                           table: "Localizable", bundle: SystemL10n.bundle)  // ✓ deferred intent
   String(localized: "carplay.detail.started", defaultValue: "Started",
          table: "Localizable", bundle: CarPlayL10n.bundle)  // ✓ CarPlay
   ```
   For interpolation on an in-process surface (Mobile / Watch / Widget / CarPlay
   UI, notifications), interpolate typed values in `defaultValue` so native
   String Catalog resolution preserves argument order and plural selection.
   **App-Intent
   dialogs and prompts are the exception** — they must be deferred
   `LocalizedStringResource`s so Siri/Shortcuts resolve them in the request
   locale, not the app-process locale (see "The App-Intent request-locale seam"
   above); do not build an intent dialog with `IntentDialog(stringLiteral:)` or
   inject an eagerly localized fragment into a deferred resource.
3. Run `python3 script/verify_localization_catalog.py` — it fails if the key is
   missing from the catalog, lacks any shipped-language translation, or a
   shipping bundle plist has drifted from the discovered locale set.

Each module's catalog is independent. Strings shared across modules are
duplicated per catalog (or sourced from `LorvexCore`), because SwiftPM does not
merge resource bundles across module boundaries.

## SwiftPM limitation

SwiftPM does not run Xcode's `genstrings` extraction tool, so newly added Swift string literals are not automatically added to the catalog. All entries must be added manually (hence `"extractionState": "manual"` on every entry). The XcodeGen-generated Xcode project picks up the catalog as a bundled resource and supports Xcode's extraction workflow.

Raw SwiftPM copies `.xcstrings` resources but does not compile them into the
`.strings` / `.stringsdict` files native lookup consumes. The repository gate
runs `script/compile_xcstrings.sh` after `swift build --build-tests` and before
`swift test`; Xcode/XcodeGen builds compile catalogs as part of the normal build.
Run that script before a focused locale-resolution test outside `verify_all.sh`.
