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
| Main app UI (macOS / iOS / iPadOS) and CarPlay, which runs in the iOS app's process | the app's language: the system language, or the app's own language preference | in-process against the module bundle (`Text("key", bundle:)`, `String(localized: … bundle:)`) |
| Widgets, Watch | their own process's language, which is the system language | in-process against the module bundle |
| Notifications | the app/system language at the time the notification is scheduled | in-process, eager (e.g. `String(localized: "notification.snooze.body", table: "Localizable", bundle: MobileL10n.bundle)`) |
| App Intents / Shortcuts / Siri / Spotlight | the **invoking request's** locale — which can differ from the app-process language | deferred `LocalizedStringResource`, resolved by the framework at presentation |

How a process picks its language, and how the app's own language preference
works, is described under "Following the system language" below.

**Formatting.** A process's `Locale.current` combines the language its bundle
resolved at launch with the user's region and settings (calendar, digits,
24-hour time, first weekday), so an app showing Chinese on a Mac set to the
United States region formats as `zh-Hans_US`. Anything a person reads is
formatted in that locale, read at the moment of formatting, so a change of
region or clock applies to the next label without a relaunch; a fixed locale
such as `en_US_POSIX` is only for machine formats. Dates go through the display
functions of `LorvexDateFormatters` (`string(_:template:timeZone:)`,
`string(_:dateStyle:timeZone:)`, `dayNumber`, `range`, `clockTime`,
`dayAndClockTime`, `relative`, `relativeDays`). Their locale defaults to
`LorvexClockFormat.displayLocale`, the current locale with the clock chosen in
Settings, and each takes the time zone the date is shown in. No surface keeps a
locale of its own or a formatter built from a locale captured once.

**Numbers and lengths of time.** A number inside a sentence is interpolated
into the `String(localized:)` or `LocalizedStringResource` call
(`"\(count) tasks"`), which formats it in the display locale, so its digits
follow the user's numbering system; it is never pre-formatted with
`String(format:)`, which ignores the locale. A length of time (an estimate, a
planned block, a day's load, time left) is written by `LorvexDurationFormat`
from the system's CLDR duration units ("1 hr 30 min", "1小时30分钟", "1 ч 30
мин"), and how long ago something happened by
`LorvexDateFormatters.elapsed(seconds:)` ("5 min. ago", "hace 2 h", "3天前").
The catalogs carry no minute or hour words of their own; a sentence around
such a value takes it as a `%@` argument ("About %@", "%@ left").

**Lists and ordinals.** Names that read as one phrase (a rule's weekdays, the
tasks a Siri reply names) are joined by the display locale's list format,
`.formatted(.list(type: .and))`, with `width: .narrow` for compact labels. It
supplies the language's own separators and conjunction ("Mon, Wed, and Fri",
"lun, mié y vie", "周一、周三和周五") and isolates right-to-left names from the
text around them. When only some names are read out, the count of the rest
("2 more") is the list's last item, so the conjunction comes once. Other joins
are not lists: facts set side by side on screen are separated by " · ", a
VoiceOver label separates its facts with ", " (read as a pause), and a field
that takes comma-separated input (tags, dependencies) keeps ", " as its
syntax. An ordinal ("1st", "1.º", "第1") comes from a `NumberFormatter` with the
`.ordinal` style in the display locale, never from a number and a suffix.

**Searching and sorting.** A filter over names or text matches with
`localizedStandardContains`, which ignores case and accents as the user's
language defines them ("cafe" finds "Café"), the same folding the store's
full-text index (`unicode61 remove_diacritics 2`) applies to tasks. Names
listed alphabetically are sorted with `localizedStandardCompare` (letter case
ignored, accented letters beside their base letter, "tag2" before "tag10"),
not by SQLite, which compares text by code point and whose `COLLATE NOCASE`
folds only ASCII letters. Whether two tag or habit names are the same is a
separate rule: it follows the store's lookup key (NFKC, case folded,
whitespace collapsed), which keeps accents, so "Café" and "cafe" are two tags.

**Calendars.** Dates are shown in the user's calendar: Gregorian in most
regions, Buddhist years in Thailand, Persian months in Iran, or whichever
calendar the user picked. Month grids and day pickers lay out days in the same
calendar (`LorvexDateFormatters.displayCalendar(timeZone:)`), so a written date
always matches the grid it sits in. A week starts on the user's first weekday
(Sunday in the United States, Monday in most of Europe, Saturday in Egypt and
Iran, or the day chosen in System Settings): month grids, week strips, weekday
pickers, per-weekday charts, and lists of weekdays follow it, through the
display calendar and `LorvexWeekdayOrder`. Habit periods are the exception: a
habit counts ISO weeks, Monday to Sunday, on every device, so devices set to
different regions agree on the week a check-in counts toward, and the habit
grids lay out those weeks. Stored days are Gregorian `yyyy-MM-dd` keys,
and so are recurrence rules and habit cadences (ISO weeks). `PlannedDayBridge`
converts between a stored day and a local one; it takes a time zone, not a
calendar, and never copies year, month, and day numbers from one calendar into
another.

**Plurals.** Where a catalog entry defines native plural variations,
`String(localized:)`/`LocalizedStringResource` integer interpolation selects
the CLDR category automatically. The rules for writing count strings are under
"Counts and plural forms" below. The shipped languages are the ones the
catalogs carry; see "Language coverage" below. A plural entry carries, for each
language, the CLDR categories that language's integer counts select, as
declared in `PLURAL_CATEGORIES` in `script/verify_localization_catalog.py`:
English `one`/`other`; Spanish and Italian `one`/`other`, and French and
Brazilian Portuguese `one`/`other` where `one` selects both 0 and 1, each with an
optional `many` that only round millions select and that falls back to `other`
when absent; Hindi `one`/`other`, where `one` selects both 0 and 1; Chinese
(Simplified and Traditional), Japanese, and Korean only `other`; Russian and
Ukrainian
`one`/`few`/`many`/`other`, where `one` selects 1,
21, 31, and so on (never 11), `few` 2 to 4, 22 to 24, and so on (never 12 to 14),
and `many` 0, 5 to 20, 25 to 30, and so on; Polish `one`/`few`/`many`/`other`,
where `one` selects only 1, `few` 2 to 4, 22 to 24, and so on, and `many` 0, 5 to
21, 25 to 31, and so on, 12 to 14 included; Arabic all six: `zero` selects 0,
`one` 1, `two` 2, `few` 3 to 10, `many` 11 to 99, and `other` 100 and over.
In Russian, Ukrainian, and Polish only fractions select `other`; the format
still requires the form, so it carries the genitive singular ("1,5 дня").
Apple's lookup honors an explicit `zero` entry in every language.

A `one` form may leave the number out ("Once a week") only in a language whose
`one` means exactly 1, as in English, Spanish, Italian, and Polish. French,
Brazilian Portuguese, Hindi, Bengali, and Persian also use `one` for 0, and
Russian and Ukrainian use it for 21, 31, 101, and so on, so their `one` forms
show the count. A `zero` form takes 0 over from `one`, so an entry that defines
`zero` may drop the number from `one` in a language whose `one` otherwise also
covers only 0. `ONE_ALSO_SELECTS` in `script/verify_localization_catalog.py`
lists these languages, and the verifier rejects a `one` form, top-level or in a
substitution, that leaves the count out where it must not. In every language,
each form of a substitution contains `%arg`, except a unit word set apart from
its number (see "Counts and plural forms") and a category the language names
in the noun itself: Arabic `one` and `two` ("مهمة واحدة", "مهمتان") and the
Hebrew dual `two`, which `WORDLESS_COUNT_CATEGORIES` lists.

Because no plural category means exactly 1 in every language, a phrase that
should read without a number for exactly one in every language ("Every week",
"每周") gets a key of its own, which the code chooses for a count of 1; the
plural entry then serves 2 and up, and its translator comment says so
(`recurrence.every_week` beside `recurrence.every_n_weeks`).

### Counts and plural forms

Every count in a source text varies by plural in the English source, even
where English writes every form alike ("%lld completed"): the source's plural
forms are the ones each translator fills in, so a count with no plural forms
in English would reach every language as one fixed form. A text with one count
may vary at the top level; a text with several counts varies each with its own
substitution, so every count selects its own form:

```json
"settings.diagnostics.status.spotlight": {
  "localizations": {
    "en": {
      "stringUnit": { "state": "translated", "value": "%#@tasks@, %#@events@" },
      "substitutions": {
        "tasks":  { "argNum": 1, "formatSpecifier": "lld", "variations": { "plural": {
          "one":   { "stringUnit": { "state": "translated", "value": "%arg task" } },
          "other": { "stringUnit": { "state": "translated", "value": "%arg tasks" } } } } },
        "events": { "argNum": 2, "formatSpecifier": "lld", "variations": { "plural": {
          "one":   { "stringUnit": { "state": "translated", "value": "%arg calendar event" } },
          "other": { "stringUnit": { "state": "translated", "value": "%arg calendar events" } } } } }
      }
    }
  }
}
```

The code passes the counts as plain interpolations
(`"\(tasks) tasks, \(events) calendar events"`); the catalog decides the forms.
A sentence is one entry with its numbers interpolated, never a phrase
assembled in code from separately localized fragments, because word order,
separators, and agreement differ between languages.

An integer argument that counts nothing has no plural forms: a part of an "N of
M" ratio with no noun after it ("3/5"), a day of the month, a point on a fixed
scale, a value after its label ("Pending: 3"), or an identifier. Each such
argument is listed in `NON_COUNT_INTEGER_ARGUMENTS` in
`script/verify_localization_catalog.py` with the reason it counts nothing; the
verifier rejects an unlisted count without plural forms, and a listing that no
longer exempts anything.

A translation into a language with more than one plural category varies every
count the source varies. A language with a single category (Chinese, Japanese,
Korean, Indonesian, Malay, Thai, Vietnamese) writes every count alike, so its
translation may be plain text. Any translation may vary a count the source does
not, as Russian does where a verb agrees with the first number of "1 of 3".

A unit word set beside a number the surface shows apart from it ("days" under
the goal ring's large "30") leaves the number out of every form, in the source
and in every translation; the number only selects the word's form. Such an
entry uses a substitution whose forms omit `%arg` (`%#@unit@` with forms "day"
and "days"), because `xcstringstool` rejects a top-level plural whose forms do
not show the number. The `one` rule above does not apply to it, since no form
shows the count.

### Following the system language

Each process shows the first language in the user's preferred-language list
that its bundles ship, matched the way Foundation matches localizations:

- A regional system language selects its language: `ar-SA` and `ar-EG` select
  `ar`; `es-MX`, `es-419`, and `es-ES` select `es`; `fr-CA` and `fr-CH` select
  `fr`; `hi-IN` selects `hi`; `it-CH` selects `it`; `ja-JP` selects `ja`;
  `ko-KR` selects `ko`; `pl-PL` selects `pl`; `ru-RU` and `ru-KZ` select `ru`;
  `uk-UA` selects `uk`; `en-GB` selects `en`. `pt-PT` selects `pt-BR`, the one
  Portuguese variety shipped.
- Chinese is matched by script, and a code with no script gets the script its
  region writes. `zh-Hant`, every `zh-Hant-*` code, and the Taiwan, Hong Kong,
  and Macau regions (`zh-TW`, `zh-HK`, `zh-MO`) select `zh-Hant`; `zh-Hans`,
  every `zh-Hans-*` code, the mainland and Singapore regions (`zh-CN`,
  `zh-SG`), and bare `zh` select `zh-Hans`. An explicit script wins over the
  region (`zh-Hans-HK` selects `zh-Hans`, `zh-Hant-CN` selects `zh-Hant`), so a
  code never crosses scripts. With both scripts shipped, Foundation resolves
  `zh-HK` and `zh-MO` to `zh-Hant` on its own, and `AppLanguage` reads the same
  answer from it rather than keeping a region table of its own.
- A list whose first language is not shipped falls through to the next one: a
  Mac set to German, then Simplified Chinese, shows Simplified Chinese.
- A list naming no shipped language selects the development language, English.

`AppLanguageTests` pins these rules.

Foundation limits every module bundle in a process to the languages the
process's main bundle declares, so each shipping bundle declares the full set:
`CFBundleDevelopmentRegion` and `CFBundleLocalizations` in its Info.plist (the
checked-in `Config/*-Info.plist` files, the macOS app's Info.plist that
`script/build_and_run.sh` generates, and the plist embedded in the debug
executable), plus a `<language>.lproj` directory per language. A bundle that
omits a language shows English in it whatever the module catalogs carry.

The Info.plist values the system shows a person (bundle names, the calendar
permission prompts, Home Screen quick actions) are localized in
`Config/InfoPlist/<target>/<language>.lproj/InfoPlist.strings`. XcodeGen
bundles them into the iOS and watchOS targets; `build_and_run.sh` stages the
`LorvexApple` and `LorvexWidgets` sets into the macOS app and its widget
extension, and `package_local.sh` checks that every declared language arrived.
`verify_localization_catalog.py` requires every such key in every shipped
language, requires the English text to equal the Info.plist's own (the system
shows the strings file in place of the plist value), and rejects a directory
for a language the app does not ship.

The app's own language preference is the `AppleLanguages` value in the app's
preference domain, which is where the system's per-app language setting
writes it too (on Lorvex's page in iOS Settings, and under macOS System
Settings > General > Language & Region > Applications). The in-app picker
(`AppLanguage`) reads and writes that same value, so the picker and the system
setting always agree; "System Default" removes it. It lists the languages by
endonym in one order for every interface language: the Latin-script names
alphabetically, then each other script as a group (Cyrillic, Arabic,
Devanagari, Hangul, Han). The picker reads only the
app's own domain: a plain `UserDefaults` lookup would fall through to launch
arguments and to the system-wide list and report them as a choice. A bundle
resolves its language once, at launch, so a change applies after a relaunch;
both pickers show a note while the chosen language differs from the running
one, and macOS offers Quit & Reopen. The app's widgets and the watch keep
following the system language, because each runs in its own process with its
own preferences.

The layout direction follows the language the app shows, however that
language was chosen. iOS mirrors an app running in a right-to-left language
by itself. AppKit mirrors only while the `AppleTextDirection` default is on,
and the value AppKit registers for it follows the system's language list, not
the app's: Arabic chosen in the in-app picker or under System Settings >
Applications on an English Mac would show Arabic text laid out left to right.
So the Mac app turns the default on for its own process at launch, in the
launch-argument domain, whenever the language it runs in reads right to left
(`LorvexAppleTextDirection`, called first in `LorvexAppleApp.init()`, since
AppKit reads the default once and keeps the answer). A left-to-right language
needs nothing: AppKit lays its localization out left to right even on a
right-to-left system.

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
  `\(.applicationName)`). Every phrase must contain that token. The system reads
  the phrases from `AppShortcuts.strings` in the bundle that holds the App
  Intents metadata: on iOS, Xcode's `ExtractAppIntentsMetadata` build phase
  writes both into the LorvexSystemIntents framework; on macOS, release staging
  (`script/extract_app_intents_metadata.py`, run by `build_and_run.sh`) writes
  them into the app bundle. `verify_localization_catalog.py` checks the catalog
  on its own: every phrase and translation names the app exactly once, and
  every shipped language translates every phrase. The Swift `phrases:` array
  stays as the English source literals; translators fill each language in
  `AppShortcuts.xcstrings`.

- **Metadata strings on macOS.** The system resolves every string the App
  Intents metadata names (intent and parameter titles, descriptions, entity
  names) in the bundle that holds the metadata, but the macOS build ships each
  module's catalog in a nested SwiftPM resource bundle. Release staging
  therefore copies exactly those strings into the app's and the widget
  extension's own `<language>.lproj/Localizable.strings`, and fails when one is
  missing from every linked catalog or lacks a shipped language.

## Language coverage

English (`en`) is the source language. The shipped languages are English,
Arabic (`ar`), Spanish (`es`), French (`fr`), Hindi (`hi`), Italian (`it`),
Japanese (`ja`), Korean (`ko`), Polish (`pl`), Brazilian Portuguese (`pt-BR`),
Russian (`ru`), Ukrainian (`uk`), Simplified Chinese (`zh-Hans`), and
Traditional Chinese (`zh-Hant`).

The target set is the 31 locales lorvex.app is published in: `en`, `zh-Hans`,
`zh-Hant`, `es`, `hi`, `ar`, `fr`, `bn`, `pt-BR`, `ru`, `id`, `ur`, `de`, `ja`,
`mr`, `te`, `tr`, `ta`, `vi`, `ko`, `fa`, `it`, `th`, `pl`, `uk`, `ms`, `ml`,
`nl`, `ro`, `el`, `he`. `PLURAL_CATEGORIES` declares the plural rules of every
one of them (a regional identifier such as `pt-BR` uses its language's rules).
Each identifier names the variety its translation is written in and covers
the regions the system matches to it: neutral `es` serves every Spanish
region, Brazilian Portuguese `pt-BR` also serves Portugal (Foundation falls
back to a sibling region), and `zh-Hant` (Taiwan usage) serves Hong Kong and
Macau. A language ships only when every catalog, every InfoPlist.strings
target, and the language picker carry it; the verifier and `LocalizationTests`
reject a partial language, so languages are added one batch at a time, each
language in the batch complete before the batch merges. Arabic is
right-to-left; its mirrored layout is captured and reviewed on the macOS
preview tour, the iOS screens, and the iOS widget gallery, while the watch and
CarPlay surfaces have no Arabic capture. Persian, Urdu, and Hebrew are
right-to-left too and need the same review when they are added.

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
on the Mac, iPhone, widgets, and in Shortcuts. It holds the seeded Inbox's name
(see the Simplified Chinese conventions below), relative day phrases, habit
streak lengths, how a recurrence rule reads (its frequency names, interval,
anchor, weekdays, and summary), a task's status and priority names, the facts
VoiceOver reads for a task row and a dependency, the words a capture line
previews ("Adds “…”", "Due Friday"), the names of the data categories and
their groups that the export pickers, import preview, and import summary
show ("Calendar Events", "Reviews & Assistant"), what a rejected import file
shows (empty, not a Lorvex backup, from a newer Lorvex, damaged, too large),
and every line of the import summary (its counts, the "Not imported:" and
restored-without groups, and the names of the details a restored task can
lack). A word both apps show about shared data belongs here, not in two app
catalogs.)

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
Apple catalog, and that every bundle-qualified native `Text` /
`String(localized:)` and bundle-owned `LocalizedStringResource` exists in the
matching catalog. Each module scan must find a real reference, so
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
an argument or reinterpret its type. It also checks the
`LocalizedStringResource("key", … table: "Localizable", bundle: <Module>L10n.bundle)`
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
Adding `fa`, `he`, or any other
locale should be a catalog + bundle metadata change, not a verifier-code change.
The required language set is the union discovered from the catalogs, so a locale
introduced in one catalog must be completed across every catalog and shipping
bundle.

The verifier also compares each call's English `defaultValue` with the
catalog's English text, placeholder for placeholder when the default
interpolates, and enforces the count rules under "Counts and plural forms".
Only the compiler knows the type of each interpolated value, so
`script/verify_localization_arguments.py` checks the arguments themselves: it
builds the package for macOS with the compiler's localized-string extraction
(`-emit-localized-strings`) into `.build/localized-strings` and compares the
arguments each call passes (`Int` as `%lld`, `UInt32` as `%u`, `Double` as
`%lf`, any other value as `%@`) with the arguments its catalog text reads. An
argument the catalog reads that the call does not pass, or reads with another
type, prints garbage or crashes, and one it never reads drops out of the
sentence; the catalog verifier already holds every translation to the source
text's arguments, so the check covers every language. The first run builds
from scratch (about a minute and a half); later runs are incremental, and
`--skip-build` rereads the last build. Code compiled only for iOS or watchOS
is outside a macOS build, and the report counts those calls (`--verbose` lists
them). Run it whenever a localized string's interpolations change.

This global locale-set rule is intentional. It keeps the app ready for broad
language coverage: no verifier, Swift test, or Info.plist should encode a fixed
English/Chinese pair or any other hardcoded language pair. The only hardcoded
language is the source language (`en`), because SwiftPM and Xcode need one
canonical fallback value for development builds.

## How to add a new translatable string

1. Write the entry's spec, its comment and its text in every shipped language,
   and add it with `script/localization_transfer.py define`. Use dot-namespaced
   keys (`<surface>.<context>.<item>`):

   ```sh
   cat > /tmp/habits.json <<'EOF'
   {
     "habits.empty.no_habits_title": {
       "comment": "Title shown when the habits workspace is empty",
       "en": "No Habits",
       "es": "No hay hábitos",
       "zh-Hans": "没有习惯"
     }
   }
   EOF
   python3 script/localization_transfer.py define \
     --catalog Sources/LorvexApple/Resources/Localizable.xcstrings /tmp/habits.json
   ```

2. Every shipped language is required, so a string ships translated into every
   language or not at all. Text with a count takes `{"plural": {...}}` with the
   categories each language's integer counts select (see "Plurals" above), or
   one substitution per count (see "Counts and plural forms"), and the other
   shorthands `localization_transfer.py` documents work too. The
   command checks every language's placeholders and plural categories against
   the English source, writes `"extractionState": "manual"` (which keeps Xcode
   from dropping an entry whose source reference it cannot find, as in SwiftPM
   projects), and keeps the catalog's serialization, so the diff shows only the
   new entry. Defining an existing key replaces its whole entry where it
   stands; `remove --catalog PATH KEY …` deletes entries.

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

5. Run `python3 script/verify_localization_catalog.py` and the relevant Swift
   tests to confirm nothing is broken, and `python3
   script/verify_localization_arguments.py` when the string interpolates
   values.

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

## Spanish conventions

The `es` catalogs are one neutral international Spanish: es-419, es-MX, and
every other Spanish locale fall back to it, so regionalisms are avoided. They
follow Apple's Spanish usage and keep one term per concept across every catalog,
so a thing reads the same on the Mac, iPhone, watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | tarea, lista, etiqueta | all feminine; a task's checklist is a lista de comprobación and its item an elemento |
| Inbox (the seeded list) | Entrada | shown while the list keeps its seeded name; short enough for the Mac sidebar beside its count, where “Bandeja de entrada” truncates |
| Someday | Algún día | capitalized and unquoted inside a sentence, like Hoy and Calendario |
| Due (the deadline field) | Vencimiento | “Vence 5 oct” before a date, vencida for overdue, “Venció hace 3 días” for a past deadline |
| Open (a task not yet done) | pendiente | never abierta; En curso is the In Progress status and Iniciada a started task |
| Done (a button) and done (a state) | Listo, completada | Listo closes a sheet; a finished task is completada |
| Defer and snooze | Aplazar, Posponer | defer moves a task to a later day; snooze moves a reminder |
| Plan (verb) | planificar | the day a task is planned for is its fecha planificada |
| Schedule (the day pane) | Agenda | Sugerir horarios proposes one; Horario del día is the day hours |
| Capture (quick add) | Añadir | “Captura rápida” names the Quick Capture home screen action |
| Review (the day and the week) | Revisión | revisión diaria, revisión semanal; its fields are Logros, Obstáculos, Aprendizajes |
| Memory | Memoria | one entry is a recuerdo; where English says notes, Spanish says notas |
| Assistant, AI | asistente, IA | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | hábito, registro, racha, hito | hábito is masculine; Registrar is the check-in action |
| Depends on | Depende de | |
| Recurrence | repetición | Repetir is the field, Se repite the state, Cada the interval |
| Sync, snapshot | sincronización, instantánea | |
| Apple features | Ajustes, Calendario, Recordatorios, Atajos, Siri, Spotlight, modo de concentración, pantalla bloqueada | product names stay: Lorvex, iCloud, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as tú, never usted or vosotros. Instructions are
  imperatives ("Añade una tarea"); buttons, menu items, and intent titles are
  infinitives ("Completar tarea"); a confirmation after an action is impersonal
  ("Se completó “%@”.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence (Hoy,
  Algún día, Calendario, Memoria) take a capital.
- Inverted marks are always paired (¿…? ¡…!). An ellipsis is the single character
  … wherever English has one. User content (task titles, list names) is quoted
  with “ ”, never « » or straight quotes, and only where the English quotes it.
- A space separates a number from its unit ("90 min", "2 h"), "aprox." stands for
  "about", and the thousands separator is a no-break space ("10 000"). A date
  format hint reads AAAA-MM-DD.
- An `es` plural entry carries `one` and `other` only, and `zero` only where the
  English entry has one. Counted phrases agree in each form ("Queda 1 tarea",
  "Quedan 3 tareas"), even where the English one and other texts are identical.
  An English entry that carries a count without plural variations cannot agree
  in number, so its Spanish reads the same for every count: a label and a colon
  ("Seleccionadas: %lld", "Pendientes: %lld"), or a phrase whose words do not
  vary.
- Status words agree with what they describe: Completada, Cancelada, and
  Bloqueada for a task; Archivados for habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter wording
  than a literal translation, because Spanish runs about a quarter longer than
  English ("Planificar hoy", "Abre Lorvex", "7 días" for the menu bar panel's
  Next 7 Days switch). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Spanish day, time, and
  duration words for a user who reads Spanish, so the Spanish capture hint gives
  Spanish examples ("mañana", "a las 15:00", "cada lunes"). Spanish does not
  write a clock time with h, so the time example says "a las".
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are tú imperatives that
  name the app exactly once ("Añade una tarea a ${applicationName}").

## Hindi conventions

The `hi` catalogs are Hindi as written in India, in Devanagari. They follow
Apple's Hindi usage (कैलेंडर, रिमाइंडर, सेटिंग्ज़) and keep one term per concept
across every catalog, so a thing reads the same on the Mac, iPhone, watch,
widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | कार्य, सूची, टैग | कार्य reads the same in the singular and the plural; a task's checklist is a चेकलिस्ट and its item an आइटम |
| Inbox (the seeded list) | इनबॉक्स | shown while the list keeps its seeded name |
| Today, tomorrow, yesterday | आज, कल, बीता कल | कल also means "yesterday" in everyday Hindi, so the past day is always बीता कल (बीते कल inside a sentence) |
| Someday | किसी दिन | quoted as “किसी दिन” inside a sentence |
| Due (the deadline field) | नियत तिथि | नियत on a compact label, अतिदेय for overdue |
| Open (a task not yet done) | लंबित | never खुला; प्रगति में is the In Progress status and शुरू a started task |
| Done and complete | हो गया, पूर्ण, पूरा | हो गया closes a sheet; पूर्ण is the Completed status and पूर्ण करें completes a task; पूरा, पूरे, पूरी describe progress |
| Cancel, cancelled | रद्द करें, रद्द | |
| Defer and snooze | टालें, स्नूज़ करें | defer moves a task to a later day (“कल पर टालें”); snooze moves a reminder |
| Plan (verb) | प्लान करें | the day a task is planned for is its प्लान की तारीख़; प्लानिंग heads the planning fields |
| Schedule, agenda | शेड्यूल, एजेंडा | समय सुझाएँ proposes times; दिन के घंटे are the day hours |
| Capture (quick add) | जोड़ें | “तुरंत जोड़ें” names the Quick Capture home screen action |
| Review (the day and the week) | समीक्षा | दैनिक समीक्षा, साप्ताहिक समीक्षा; its fields are उपलब्धियाँ, बाधाएँ, सीख |
| Memory | मेमोरी | one entry is an एंट्री; where English says notes, Hindi says नोट |
| Assistant | असिस्टेंट | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone, goal | आदत, चेक-इन, स्ट्रीक, माइलस्टोन, लक्ष्य | चेक-इन करें is the check-in action |
| Depends on | इन पर निर्भर | निर्भरताएँ heads the list of dependencies |
| Recurrence | दोहराव | दोहराएँ is the field, हर the interval |
| Sync, snapshot | सिंक, स्नैपशॉट | |
| Settings | सेटिंग्ज़ | सेटिंग names one preference |
| Apple features | कैलेंडर, रिमाइंडर, फ़ोकस, सूचनाएँ, लॉक स्क्रीन, डॉक, विजेट | product names stay Latin: Lorvex, iCloud, CloudKit, Siri, Spotlight, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as आप, never तुम or तू. Instructions, buttons, menu
  items, and intent titles are polite imperatives ("कार्य जोड़ें", "सूची
  हटाएँ"); a confirmation after an action is impersonal and passive
  ("“%@” हटा दिया गया।"); "कृपया" appears only where the English says "Please".
- Participles agree in gender with what they describe, so a confirmation is
  written for each noun and never shares one verb form: a कार्य is masculine
  ("“%@” पूर्ण किया गया।"), an आदत and a सूची are feminine ("आदत “%@” पूर्ण की
  गई।", "सूची “%@” बनाई गई।").
- Hindi is written in Devanagari. Product and technology names stay Latin:
  Lorvex, iCloud, CloudKit, Siri, Spotlight, Apple Watch, CarPlay, Claude, MCP,
  and file formats such as JSON, CSV, ICS, and ZIP, as do iPhone, iPad, and Mac.
  Everyday technology words that Apple's Hindi interfaces transliterate are
  written in Devanagari (कैलेंडर, रिमाइंडर, असिस्टेंट, इवेंट, टैग, सिंक, डिवाइस,
  इंपोर्ट, एक्सपोर्ट, ऐप, फ़ाइल); words with an established Hindi equivalent
  stay Hindi (कार्य, सूची, समीक्षा, लक्ष्य, आदत, सूचना).
- The nukta is always written on ज़ and फ़ (सेटिंग्ज़, फ़ाइल, ज़रूरी, फ़ोकस). ख़
  appears in the Perso-Arabic words that conventionally carry it (तारीख़,
  आख़िरी, ख़त्म, ख़ास, ख़राब), and खाली is written without it. Plurals and
  imperatives ending in -एँ and -ियाँ take the chandrabindu (हटाएँ, सूचियाँ,
  उपलब्धियाँ).
- A sentence ends with a danda (।) and no space before it, wherever the English
  ends with a period; labels, buttons, and headings carry no end mark. A
  question mark, exclamation mark, colon, comma, and parenthesis are the Latin
  characters, and an ellipsis is the single character … wherever English has
  one.
- Quotation marks are “ ” only. User content (task titles, list names, habit
  names, event titles) is quoted wherever it sits in a sentence, including where
  the English leaves it bare, because Hindi puts the verb last and the quotes
  mark where the name ends. Lorvex's own view names inside a sentence are quoted
  the same way (“आज”, “किसी दिन”).
- Numbers use Latin digits only, never Devanagari digits. A plain space
  separates a number from its unit ("90 मिनट", "2 घंटे"), and "लगभग" stands for
  "about". Format hints such as HH:MM and YYYY-MM-DD stay as written.
- Retrying is "फिर से कोशिश करें". Redoing something to the app or its data
  uses दोबारा (दोबारा शुरू करें, दोबारा खोलें, दोबारा अपलोड); reopening a task
  is "फिर से खोलें".
- A string that fills in several values uses positional specifiers (`%1$lld`,
  `%2$@`) wherever the Hindi word order differs from the English, as in
  "“%2$@” में %1$lld कार्य जोड़ा गया।", never concatenation in code.
- `one` selects both 0 and 1, so every `one` form shows the count, except a
  unit word set apart from its number (see "Counts and plural forms"). Nouns
  that do not change with number (कार्य, दिन, मिनट, सप्ताह, आइटम, इवेंट,
  रिमाइंडर, टैग, रिकॉर्ड, एंट्री, चेक-इन) keep `one` and `other` identical.
  Where the noun or verb does change (महीना and महीने, आदत and आदतों, किया गया
  and किए गए, है and हैं), the entry also carries a `zero` that repeats the
  `other` form, so 0 reads "0 महीने" and not "0 महीना". An entry whose
  English carries `zero` carries a Hindi `zero`.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter wording
  than a literal translation, and may drop the copula ("कुछ प्लान नहीं").
  Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Hindi day, date, time,
  duration, repeat, and priority words for a user who reads Hindi, so the Hindi
  capture hint gives Hindi examples (“कल”, “शाम 5 बजे”, “हर सोमवार”, “20 मिनट”,
  “#सूची”). Hindi says a clock time with बजे after the hour, so the time example
  carries it. कल is read as tomorrow and परसों as the day after tomorrow and
  never as a past day, because the app writes the past day बीता कल; a line in
  the past tense stays unread. The parser reads the Devanagari digits as Latin
  ones, the precomposed nukta letters as their base consonants, and the
  candrabindu as the anusvara, accepts a nukta typed as a separate sign or left
  out, and the title keeps what was typed. Hindi written in Latin letters is not
  read. The examples are Devanagari, written left to right like the rest of the
  string, so the hint needs no bidirectional isolate.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are polite imperatives
  that name the app exactly once, in front of its postposition
  ("${applicationName} में कार्य जोड़ें").

## Arabic conventions

The `ar` catalogs are Modern Standard Arabic in the register of Apple's Arabic
interfaces (التقويم, الإعدادات, الإشعارات, الاختصارات). Every Arabic locale
(ar-SA, ar-EG, ar-AE, and the rest) selects them, so regionalisms are avoided.
They keep one term per concept across every catalog, so a thing reads the same
on the Mac, iPhone, watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | مهمة, قائمة, وسم | plurals مهام, قوائم, وسوم; a task's checklist is a قائمة التحقق and its item a عنصر |
| Inbox (the seeded list) | الوارد | shown while the list keeps its seeded name |
| Today, tomorrow, yesterday | اليوم, غدًا, أمس | |
| Someday | يومًا ما | quoted inside a sentence ("يومًا ما") |
| Due (the deadline field) | الاستحقاق | مستحقة before a date, متأخرة for overdue |
| Open (a task not yet done) | غير مكتملة | never مفتوحة; قيد التنفيذ is the In Progress status and تم البدء a started task |
| Done and complete | تم, مكتملة, إكمال | تم closes a sheet; مكتملة is the Completed status; إكمال completes a task |
| Cancel, cancelled | إلغاء, ملغاة | |
| Defer and snooze | تأجيل, غفوة | defer moves a task to a later day; snooze moves a reminder (غفوة حتى) |
| Plan (verb) | تخطيط | the day a task is planned for is its تاريخ التخطيط; مخططة is planned and مجدولة has a date |
| Schedule, agenda | الجدول | اقتراح أوقات proposes times; ساعات اليوم are the day hours |
| Capture (quick add) | إضافة | إضافة مهمة names the capture sheet |
| Review (the day and the week) | مراجعة | المراجعة اليومية, المراجعة الأسبوعية; its fields are الإنجازات, العقبات, الدروس المستفادة; the assistant's briefing is a موجز |
| Memory | الذاكرة | one entry is an إدخال |
| Assistant, AI | المساعد, الذكاء الاصطناعي | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone, goal | عادة, تسجيل, سلسلة, محطة, هدف | تسجيل is also the check-in action |
| Waits on, depends on, blocked | بانتظار, تعتمد على, محظورة | تبعية (plural تبعيات) names one dependency; the Shortcuts parameter reads تعتمد على |
| Recurrence | التكرار | |
| Sync, snapshot | المزامنة, لقطة | |
| Settings | الإعدادات | |
| Apple features | التقويم, حدث تقويم, الإشعارات, شاشة القفل, الاختصارات, التركيز, أداة | a widget is an أداة; Dock and Spotlight stay Latin |

- The reader is addressed in the masculine singular. Instructions are
  imperatives ("أضف مهمة"); buttons, menu items, and intent titles are verbal
  nouns ("إضافة", "حذف", "تأجيل مهمة"); a confirmation after an action is تم
  or تمت with a verbal noun (`تم إكمال "%@".`, `تمت إضافة مهمة واحدة إلى %2$@.`).
- Product and technology names stay Latin: Lorvex, iCloud, CloudKit, Siri,
  Spotlight, Apple Watch, CarPlay, Claude, MCP, and file formats such as JSON,
  CSV, ICS, and ZIP, as do iPhone, iPad, and Mac. The conjunction و is written
  attached to the next word, Latin names and placeholders included ("Mac
  وiPhone وiPad", "و%2$@"). The one-letter prepositions ل and ب in front of a
  Latin name, a placeholder, or a number carry a tatweel because a Latin
  character cannot join them ("لـ Lorvex", "بـ %3$@").
- Punctuation is the Arabic comma ، semicolon ؛ and question mark ؟. A sentence
  ends with the Latin full stop, and the colon, the parentheses, and the
  single-character ellipsis … are the same as in English.
- Quotation marks are the straight `"` only, never « » or curly quotes. User
  content (task titles, list names, habit names, event titles) is quoted
  wherever it sits in a sentence, including where the English leaves it bare,
  and Lorvex's own view and button names inside a sentence are quoted the same
  way ("يومًا ما", "تصدير", "اقتراح أوقات").
- A catalog never contains a digit. Counts and values arrive through
  placeholders, which the system formats in the digits of the user's region
  (Arabic-Indic for ar-SA, for example), and a number the English writes as a
  fixed word is written out ("الأيام السبعة القادمة", "نظام اثنتي عشرة ساعة").
  The exceptions are text a person types: the priority values "1 أو 2 أو 3" and
  the example words of the capture hint. Format hints such as HH:MM stay as
  written. "حوالي" stands for "about", and "د" is the compact unit for
  minutes beside a number.
- An `ar` plural entry carries all six categories, and the forms agree with the
  count. `one` is the singular with واحد or واحدة in place of the number ("مهمة
  واحدة"), `two` is the dual with no number ("مهمتان"), `few` is the plural
  noun after the number ("%lld مهام"), and `many` and `other` are the singular
  noun after the number ("%lld مهمة"), with the accusative tanween in `many`
  where the noun takes one ("%lld إكمالًا"). Verbs and adjectives agree with
  the form ("مهمتان متأخرتان"). `zero` repeats the `other` form or, where the
  sentence reads better, says "لا توجد" ("لا توجد مهام متأخرة"). A count shown
  apart from its unit word uses forms without the number (see "Counts and
  plural forms"). A string with several counts has one substitution per count,
  each with its own six forms.
- A string that fills in several values uses positional specifiers (`%1$@`,
  `%2$lld`) wherever the Arabic word order differs from the English, never
  concatenation in code.
- Weekday names come from the calendar's short names, which are indefinite in
  Arabic ("اثنين", "جمعة"), so a string that wraps one reads as a phrase
  ("آخر جمعة"). The system's ordinal for Arabic is the bare number, so a
  weekday's position in a month is "%2$@ رقم %1$@" and its position from the
  end "%2$@ رقم %1$@ من النهاية". Lists of names are joined by the system's list
  format, which attaches و to the next item, so the "and N more" that ends a
  Siri reply (`system.list.more`) is only "%lld أخرى".
- No bidirectional control characters are written into a catalog unless a
  capture shows a string rendering wrongly. One string carries a left-to-right
  isolate (U+2066 and U+2069) because the surrounding Arabic reorders what is
  inside it: the keyboard shortcut on the last page of the first-run wizard
  (`setup.done.capture.detail`) displays "⌘N" as "N⌘" otherwise. The capture
  hint (`capture.footer.words`) needs none, since its examples hold no Latin
  text: a Latin word that follows a number inside Arabic text is laid out right
  to left together with the number ("20 min" would display as "min 20").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter wording
  than a literal translation ("سبعة أيام" for the menu bar panel's Next 7 Days
  switch, "تم البدء" for a started task). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Arabic day, date, time,
  duration, repeat, and priority words for a user who reads Arabic, so the
  Arabic capture hint gives Arabic examples ("غدًا", "الساعة 3 مساءً", "كل
  اثنين", "20 دقيقة"). Arabic says a clock time with "الساعة", so the time
  example says it. The parser reads the letters that are spelled in more than
  one way as one (أ, إ, آ, and ٱ as ا, ى as ي, ة as ه) and ignores vowel signs
  and tatweel, and the title keeps what was typed. The hint's examples hold no
  Latin text, so they need no bidirectional isolate.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are masculine imperatives
  that name the app exactly once ("أضف مهمة إلى ${applicationName}").

## French conventions

The `fr` catalogs are one neutral French: fr-FR, fr-CA, fr-CH, and every other
French locale select them, so regionalisms are avoided. They follow Apple's
French usage (Réglages, Calendrier, Rappels, Raccourcis) and keep one term per
concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | tâche, liste, tag | tâche and liste are feminine; a task's checklist is a liste de contrôle and its item an élément |
| Inbox (the seeded list) | Boîte de réception | shown while the list keeps its seeded name |
| Someday | Un jour | capitalized and unquoted after a preposition ("dans Un jour", "vers Un jour"), quoted where it qualifies tasks ("les tâches « Un jour »") |
| Due (the deadline field) | Échéance | "Échéance %@" leads a row, "il y a 3 jours" marks a past deadline, En retard is overdue |
| Open (a task not yet done) | À faire | never ouverte; En cours is the In Progress status and Démarrée a started task |
| Blocked, cancelled, completed | Bloquée, Annulée, Terminée | |
| Done (a button) and done (a state) | Terminé, Terminée, Fait | Terminé closes a sheet; a finished task is Terminée; Fait marks a habit complete for its period |
| Defer and snooze | Reporter, Masquer jusqu’à | Reporter moves a task to a later day; Masquer jusqu’à hides a task until a date; a reminder's snooze action is "Rappeler dans 1 heure" |
| Plan (verb) | planifier | |
| Schedule (the day pane) | Planning | Suggérer des horaires proposes one; Horaires de la journée are the day hours |
| Capture (quick add) | Ajout rapide | |
| Review (the day and the week) | Bilan | bilan hebdomadaire for the week; its fields are Réussites, Obstacles, Enseignements |
| Memory | Mémoire | one entry is a souvenir |
| Assistant, AI | assistant, IA | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | habitude, validation, série, palier | Valider is the check-in action |
| Depends on | Dépend de | |
| Recurrence | répétition | Répéter is the field, Se répète the state, Tous les or Toutes les the interval; the modes are Régulièrement and Après achèvement |
| Sync, snapshot | synchronisation, instantané | |
| Apple features | Réglages, Calendrier, Rappels, Raccourcis, Siri, Spotlight, mode de concentration, Réglages Système, écran de verrouillage | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as vous, never tu. Instructions are imperatives
  ("Activez l’accès au calendrier"); buttons, menu items, and intent titles are
  infinitives ("Terminer une tâche"); an intent's description is a third-person
  statement ("Termine une tâche de Lorvex."); a confirmation after an action is a
  participle that agrees with what it names ("« %@ » terminée.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence
  (Aujourd’hui, Un jour, Calendrier, Mémoire) take a capital.
- A no-break space (U+00A0) goes before ? ! ; and a colon, and inside guillemets
  (« %@ »), so a line never breaks between a mark and the word it belongs to.
  User content (task titles, list names) is quoted with « », never straight or
  curly quotes, and only where the English quotes it. The apostrophe is ’, and
  an ellipsis is the single character … wherever English has one.
- The thousands separator is a no-break space ("10 000"), "environ" stands for
  "about", and "facultatif" for "optional". A date format hint reads AAAA-MM-JJ.
- `one` selects both 0 and 1, so every `one` form shows the count, except a unit
  word set apart from its number (see "Counts and plural forms"). Where `one`
  drops the number ("Une fois par semaine"), the entry also carries a `zero` that
  repeats the `other` form, so 0 reads "0 fois par semaine". Counted phrases agree
  in each form ("1 tâche restante", "3 tâches restantes"), even where the English
  one and other texts are identical, except a phrase whose words do not vary
  ("%lld plus tôt").
- Status words agree with what they describe: Terminée, Annulée, Bloquée, and
  Démarrée for a task; Archivées for lists and habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation, because
  French runs about a fifth longer than English ("Planifier aujourd’hui", "Ouvrez
  Lorvex", "7 jours" for the menu bar panel's Next 7 Days switch, "Déborde" for
  Won’t fit). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads French day, time, and
  duration words for a user who reads French, so the French capture hint gives
  French examples (« demain », « 15h », « tous les lundis »).
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are what a person says to
  the assistant, so they are tu imperatives that name the app exactly once ("Ajoute
  une tâche dans ${applicationName}"), unlike the vous of the interface.

## Italian conventions

The `it` catalogs are one neutral Italian: it-IT, it-CH, and every other Italian
locale select them, so regionalisms are avoided. They follow Apple's Italian
usage (Impostazioni, Calendario, Promemoria, Comandi rapidi) and keep one term
per concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | attività, lista, tag | attività is invariable and feminine; a task's checklist is a lista di controllo and its item an elemento |
| Inbox (the seeded list) | In arrivo | shown while the list keeps its seeded name |
| Someday | Prima o poi | capitalized and unquoted after a preposition ("Sposta in Prima o poi"), quoted where it qualifies tasks ("le attività “Prima o poi”") |
| Due (the deadline field) | Scadenza | "Scadenza %@" leads a row, "3 giorni fa" marks a past deadline, In ritardo is overdue |
| Open (a task not yet done) | Da fare | never aperta; In corso is the In Progress status and Iniziata a started task |
| Blocked, cancelled, completed | Bloccata, Annullata, Completata | |
| Done (a button) and done (a state) | Fine, Completata, Fatto | Fine closes a sheet; a finished task is Completata; Fatto marks a habit complete for its period |
| Defer and snooze | Rimanda, Nascondi fino a | Rimanda moves a task to a later day; Nascondi fino a hides a task until a date; a reminder's snooze action is "Posticipa di 1 ora" |
| Plan (verb) | pianificare | |
| Schedule (the day pane) | Agenda | Suggerisci orari proposes one; Orari della giornata are the day hours |
| Capture (quick add) | Aggiunta rapida | |
| Review (the day and the week) | Revisione | revisione settimanale for the week; its fields are Successi, Ostacoli, Lezioni apprese |
| Memory | Memoria | one entry is a ricordo |
| Assistant, AI | assistente, IA | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | abitudine, registrazione, serie, traguardo | Registra is the check-in action |
| Depends on | Dipende da | |
| Recurrence | ripetizione | Ripeti is the field, Si ripete the state, Ogni the interval; the modes are Regolarmente and Dopo il completamento |
| Sync, snapshot | sincronizzazione, istantanea | |
| Apple features | Impostazioni, Calendario, Promemoria, Comandi rapidi, Siri, Spotlight, modalità di concentrazione, Impostazioni di Sistema, schermata di blocco | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as tu, never Lei or voi. Instructions, buttons, menu
  items, and intent titles are imperatives ("Aggiungi un’attività", "Completa
  attività"); an intent's description is a third-person statement ("Aggiunge un
  elemento della lista di controllo a un’attività di Lorvex."); a confirmation
  after an action is a participle that agrees with what it names ("“%@”
  completata.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence (Oggi,
  Prima o poi, Calendario, Memoria) take a capital.
- User content (task titles, list names) is quoted with “ ”, never « » or
  straight quotes, and only where the English quotes it. The apostrophe is ’,
  which an elision needs ("un’attività", "l’abitudine"), and an ellipsis is the
  single character … wherever English has one.
- The thousands separator is a period ("10.000"), "circa" stands for "about", and
  "facoltativo" for "optional". A date format hint reads AAAA-MM-GG.
- `one` selects only 1, as in English, so a `one` form may leave the number out
  ("Una volta a settimana"). An `it` plural entry carries `one` and `other` only.
  Counted phrases agree in each form ("1 attività rimasta", "3 attività rimaste"),
  even where the English one and other texts are identical ("1 precedente",
  "3 precedenti"), except a phrase whose words do not vary.
- Status words agree with what they describe: Completata, Annullata, Bloccata,
  and Iniziata for a task; Archiviate for lists and habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation, because
  Italian runs about a fifth longer than English ("Pianifica oggi", "Apri
  Lorvex", "7 giorni" for the menu bar panel's Next 7 Days switch). Accessibility
  labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Italian day, time, and
  duration words for a user who reads Italian, so the Italian capture hint gives
  Italian examples ("domani", "alle 15", "ogni lunedì").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are tu imperatives that
  name the app exactly once, in front of its preposition ("Aggiungi un’attività a
  ${applicationName}").

## Brazilian Portuguese conventions

The `pt-BR` catalogs are Brazilian Portuguese. Every Brazilian locale selects
them, and so does pt-PT, because Foundation falls back to the one shipped
Portuguese variety; wording that is only European Portuguese (ecrã, utilizador,
ficheiro) is never used. They follow Apple's Brazilian Portuguese usage (Ajustes,
Calendário, Lembretes, Atalhos) and keep one term per concept across every
catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and in
Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | tarefa, lista, etiqueta | all feminine; a task's checklist is a lista de verificação and its item an item |
| Inbox (the seeded list) | Entrada | shown while the list keeps its seeded name |
| Someday | Algum dia | capitalized and unquoted after a preposition ("Mover para Algum dia"), quoted where it qualifies tasks ("As tarefas “Algum dia”") |
| Due (the deadline field) | Prazo | "Prazo %@" leads a row, "há 3 dias" marks a past deadline, Atrasada is overdue |
| Open (a task not yet done) | Pendente | never aberta; Em andamento is the In Progress status and Iniciada a started task |
| Blocked, cancelled, completed | Bloqueada, Cancelada, Concluída | |
| Done (a button) and done (a state) | Concluído, Concluída, Feito | Concluído closes a sheet; a finished task is Concluída; Feito marks a habit complete for its period |
| Defer and snooze | Adiar, Ocultar até | Adiar moves a task to a later day; Ocultar até hides a task until a date; a reminder's snooze action is "Lembrar em 1 hora" |
| Plan (verb) | planejar | |
| Schedule (the day pane) | Agenda | Sugerir horários proposes one; Horário do dia is the day hours |
| Capture (quick add) | Captura rápida | |
| Review (the day and the week) | Revisão | revisão semanal for the week; its fields are Conquistas, Obstáculos, Aprendizados |
| Memory | Memória | |
| Assistant, AI | assistente, IA | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | hábito, registro, sequência, marco | hábito is masculine; Registrar is the check-in action |
| Depends on | Depende de | |
| Recurrence | repetição | Repetir is the field, Repete the state, A cada the interval; the modes are Regularmente and Após a conclusão |
| Sync, snapshot | sincronização, instantâneo | |
| Apple features | Ajustes, Calendário, Lembretes, Atalhos, Siri, Spotlight, modo de Foco, Ajustes do Sistema, tela bloqueada | Siri takes the feminine article ("pela Siri"); product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as você, never tu. Instructions are imperatives in the
  você form ("Adicione uma tarefa"); buttons, menu items, and intent titles are
  infinitives ("Concluir tarefa"); an intent's description is a third-person
  statement ("Cria um hábito do Lorvex pelos Atalhos ou pela Siri."); a
  confirmation after an action is a participle that agrees with what it names
  ("“%@” concluída.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence (Hoje,
  Algum dia, Calendário, Memória) take a capital.
- The app's name takes the masculine article and contracts with prepositions
  like any masculine noun ("no Lorvex", "do Lorvex", "ao Lorvex", "Abra o
  Lorvex").
- User content (task titles, list names) is quoted with “ ”, never « » or
  straight quotes, and only where the English quotes it. An ellipsis is the
  single character … wherever English has one.
- The thousands separator is a period ("10.000"), "cerca de" stands for "about",
  and "opcional" for "optional". A date format hint reads AAAA-MM-DD.
- `one` selects both 0 and 1, so every `one` form shows the count, except a unit
  word set apart from its number (see "Counts and plural forms"). Where `one`
  drops the number ("Uma vez por semana"), the entry also carries a `zero` that
  repeats the `other` form, so 0 reads "0 vezes por semana". Counted phrases
  agree in each form ("1 tarefa restante", "3 tarefas restantes"), even where the
  English one and other texts are identical ("1 anterior", "3 anteriores"),
  except a phrase whose words do not vary.
- Status words agree with what they describe: Concluída, Cancelada, Bloqueada,
  and Iniciada for a task; Arquivadas for lists and Arquivados for habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation, because
  Portuguese runs about a fifth longer than English ("Planejar hoje", "Abra o
  Lorvex", "7 dias" for the menu bar panel's Next 7 Days switch). Accessibility
  labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Portuguese day, time, and
  duration words for a user who reads Portuguese, so the Portuguese capture hint
  gives Portuguese examples ("amanhã", "15h", "toda segunda").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are você imperatives that
  name the app exactly once, contracted with its preposition ("Adicione uma
  tarefa ao ${applicationName}", "Conclua uma tarefa no ${applicationName}").

## Russian conventions

The `ru` catalogs are one neutral Russian: ru-RU, ru-KZ, and every other Russian
locale select them. They follow Apple's Russian usage (Настройки, Календарь,
Напоминания, Быстрые команды) and keep one term per concept across every
catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and in
Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | задача, список, тег | задача is feminine, список and тег masculine; a task's checklist is a чек-лист and its item a пункт |
| Inbox (the seeded list) | Входящие | shown while the list keeps its seeded name |
| Someday | Когда-нибудь | capitalized and quoted where it names the view or qualifies tasks («Когда-нибудь») |
| Due (the deadline field) | Срок | "Срок: %@" leads a row, "просрочено на 3 дня" marks a past deadline, Просрочено is overdue |
| Open (a task not yet done) | Не выполнена | the status; В работе is In Progress; lists that are not archived are Активные |
| Blocked, cancelled, completed | Заблокирована, Отменена, Выполнена | feminine, agreeing with задача |
| Done (a button) and done (a state) | Готово, Выполнено, Выполненные | Готово closes a sheet; Выполнено labels a finished item; Выполненные is the filter |
| Defer and snooze | Отложить, Скрыть до | Отложить moves a task to a later day; Скрыть до hides a task until a date; a reminder's snooze action is "Напомнить через 1 час" |
| Plan (verb) | запланировать | |
| Schedule (the day pane) | Расписание | Предложить время proposes one; Часы дня are the day hours |
| Capture (quick add) | Быстрый ввод | the capture tab, which has little room, reads Добавить |
| Review (the day and the week) | Итоги | итоги недели for the week; its fields are Успехи, Препятствия, Выводы |
| Memory | Память | one entry is a запись |
| Assistant, AI | ассистент, ИИ | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | привычка, отметка, серия, рубеж | Отметить is the check-in action |
| Depends on | Зависит от | |
| Recurrence | повтор | Повтор is the field, повторяется the state, Каждые the interval; the modes are Регулярно and После выполнения |
| Sync, snapshot | синхронизация, снимок | |
| Apple features | Настройки, Календарь, Напоминания, Быстрые команды, Siri, Spotlight, режим фокусирования, Системные настройки, экран блокировки | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as вы, written lowercase, never ты. Instructions are
  plural imperatives ("Включите доступ к календарю"); buttons, menu items, and
  intent titles are infinitives ("Выполнить задачу Lorvex"); an intent's
  description is a third-person statement ("Выполняет задачу Lorvex."); a
  confirmation after an action is a passive participle that agrees with what it
  names ("Задача «%@» выполнена."). No text speaks as "I" in the past tense,
  because the verb would have to choose a grammatical gender.
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence
  («Сегодня», «Когда-нибудь», «Календарь», «Память») take a capital, and those
  view names are quoted.
- User content (task titles, list names) is quoted with « », never straight or
  curly quotes, and only where the English quotes it. The letter ё is written
  (Ещё, Тёмное, учётная запись), and an ellipsis is the single character … wherever
  English has one. Product names stay Latin and are not declined ("в Lorvex",
  "из Lorvex", "в iCloud"); Apple's app names are declined ("в Системных
  настройках"), and the Shortcuts app is quoted ("из «Быстрых команд»").
- A count is tied to the word after it with a no-break space ("%lld\u00a0задач"
  in the catalog), so a wrapping headline never ends a line on a bare number;
  `verify_localization_catalog.py` rejects a plain space there.
- The thousands separator is a no-break space ("10 000"), "около" stands for
  "about", and "необязательно" for "optional". A date format hint reads
  ГГГГ-ММ-ДД and a time hint ЧЧ:ММ.
- `one` selects 1, 21, 31, and so on, so every `one` form shows the count, except
  a unit word set apart from its number (see "Counts and plural forms"). Every
  count varies in all four categories, with the noun in the case the number
  asks for: nominative singular after 1 ("1 задача"), genitive singular after
  2 to 4 ("2 задачи"), genitive plural after 5 or more ("5 задач"), and
  genitive singular for `other` ("1,5 задачи"). Where a number follows "из", the
  noun is in the genitive in every category ("1 из 3"), and a verb agrees with
  the first number. Where agreement would force an awkward phrase, all four
  forms read alike with the number first or last ("Списков: 3, невыполненных
  задач: 12").
- Status words agree with what they describe: Не выполнена, В работе,
  Заблокирована, Отменена, and Выполнена for a task; Архивные for lists, and В
  архиве for the archived habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation,
  because Russian runs about a fifth longer than English, in wider letters
  ("7 дней" for the menu bar panel's Next 7 Days switch, "Не вошло" for Won’t
  fit, "ост." as the caption under the remaining-tasks ring, "Записать задачу"
  as a short title). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Russian day, date, time,
  duration, repeat, and priority words for a user who reads Russian, so the
  Russian capture hint gives Russian examples ("завтра", "в 15:00", "каждый
  понедельник", "20 мин"). Russian says a clock time with "в", so the time
  example says "в". The parser reads ё as е, and the title keeps the letter that
  was typed.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are what a person says
  to the assistant, so they are singular imperatives that name the app exactly
  once, leave it undeclined, and put it at the end ("Добавь задачу в
  ${applicationName}").

## Ukrainian conventions

The `uk` catalogs are Ukrainian as written in Ukraine; uk-UA and every other
Ukrainian locale select them. They follow Apple's Ukrainian usage (Параметри,
Календар, Нагадування, Швидкі команди) and keep one term per concept across
every catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and
in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | завдання, список, тег | завдання is neuter and reads alike in the nominative singular and plural; a task's checklist is a чек-лист and its item a пункт |
| Inbox (the seeded list) | Вхідні | shown while the list keeps its seeded name |
| Someday | Колись | capitalized and quoted where it names the view or qualifies tasks («Колись») |
| Due (the deadline field) | Термін | "Термін: %@" leads a row, "прострочено на 3 дні" marks a past deadline, Прострочено is overdue |
| Open (a task not yet done) | Не виконано | the status; У роботі is In Progress; lists that are not archived are Активні |
| Blocked, cancelled, completed | Заблоковано, Скасовано, Виконано | neuter, agreeing with завдання |
| Done (a button) and done (a state) | Готово, Виконано, Виконані | Готово closes a sheet; Виконано labels a finished item; Виконані is the filter |
| Defer and snooze | Відкласти, Приховати до | Відкласти moves a task to a later day; Приховати до hides a task until a date; a reminder's snooze action is "Нагадати через 1 годину" |
| Plan (verb) | запланувати | |
| Schedule (the day pane) | Розклад | Запропонувати час proposes one; Години дня are the day hours |
| Capture (quick add) | Швидкий ввід | the capture tab, which has little room, reads Додати |
| Review (the day and the week) | Підсумки | підсумки тижня for the week; its fields are Успіхи, Перешкоди, Висновки |
| Memory | Пам’ять | one entry is a запис |
| Assistant, AI | асистент, ШІ | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | звичка, позначка, серія, віха | Позначити is the check-in action |
| Depends on | Залежить від | |
| Recurrence | повторення | Повторення is the field, повторюється the state, Кожні the interval; the modes are Регулярно and Після виконання |
| Sync, snapshot | синхронізація, знімок | |
| Apple features | Параметри, Календар, Нагадування, Швидкі команди, Siri, Spotlight, режим фокусування, Системні параметри, екран блокування | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as ви, written lowercase, never ти. Instructions are
  plural imperatives ("Увімкніть доступ до календаря"); buttons, menu items, and
  intent titles are infinitives ("Виконати завдання Lorvex"); an intent's
  description is a third-person statement ("Виконує завдання Lorvex."); a
  confirmation after an action is an impersonal -но or -то participle
  ("Завдання «%@» виконано."). No text speaks as "I" in the past tense, because
  the verb would have to choose a grammatical gender.
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence
  («Сьогодні», «Колись», «Календар», «Пам’ять») take a capital, and those view
  names are quoted.
- User content (task titles, list names) is quoted with « », never straight or
  curly quotes, and only where the English quotes it. The apostrophe is ’
  (пам’ять, об’єкт), and an ellipsis is the single character … wherever English
  has one. The default is "за умовчанням" and an icon is a "значок". Product
  names stay Latin and are not declined ("в Lorvex", "у Lorvex"); Apple's app
  names are declined ("у Системних параметрах"), and the Shortcuts app is quoted
  ("зі «Швидких команд»").
- Prepositions and conjunctions follow vowel and consonant alternation: в after
  a vowel and у after a consonant ("Додай завдання в …", "Прочитай огляд у …",
  "Відкриваю «Календар» у …"), і and й ("додавати й змінювати"), з, із, and зі
  ("зі «Швидких команд»").
- A count is tied to the word after it with a no-break space ("%lld\u00a0завдань"
  in the catalog), so a wrapping headline never ends a line on a bare number;
  `verify_localization_catalog.py` rejects a plain space there.
- The thousands separator is a no-break space ("10 000"), "близько" stands for
  "about", and "необов’язково" for "optional". A date format hint reads
  РРРР-ММ-ДД and a time hint ГГ:ХХ.
- `one` selects 1, 21, 31, and so on, so every `one` form shows the count, except
  a unit word set apart from its number (see "Counts and plural forms"). Every
  count varies in all four categories, with the noun in the case the number
  asks for: nominative singular after 1 ("1 завдання"), nominative plural after
  2 to 4 ("2 дні"), genitive plural after 5 or more ("5 днів"), and genitive
  singular for `other` ("1,5 дня"). Where a number follows "з", the noun is in
  the genitive in every category ("1 з 3"). Where agreement would force an
  awkward phrase, all four forms read alike with the number first or last
  ("Списків: 3, невиконаних завдань: 12").
- Status words are neuter, agreeing with завдання: Не виконано, У роботі,
  Заблоковано, Скасовано, and Виконано for a task; Архівні for lists, and В
  архіві for the archived habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation,
  because Ukrainian runs about a fifth longer than English, in wider letters
  ("7 днів" for the menu bar panel's Next 7 Days switch, "Не влізло" for Won’t
  fit, "зал." as the caption under the remaining-tasks ring, "Занотувати
  завдання" as a short title). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Ukrainian day, date, time,
  duration, repeat, and priority words for a user who reads Ukrainian, so the
  Ukrainian capture hint gives Ukrainian examples ("завтра", "о 15:00", "кожного
  понеділка", "20 хв"). Ukrainian says a clock time with "о", so the time
  example says "о". The parser reads the apostrophe of "п'ятниця" typed as
  U+0027, U+2019, or U+02BC, and the title keeps the one that was typed.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are singular imperatives
  that name the app exactly once, leave it undeclined, and put it at the end
  ("Додай завдання в ${applicationName}").

## Polish conventions

The `pl` catalogs are Polish as written in Poland; pl-PL and every other Polish
locale select them. They follow Apple's Polish usage (Ustawienia, Kalendarz,
Przypomnienia, Skróty) and keep one term per concept across every catalog, so a
thing reads the same on the Mac, iPhone, watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | zadanie, lista, tag | zadanie is neuter, lista feminine, tag masculine; a task's checklist is a lista kontrolna and its item an element |
| Inbox (the seeded list) | Przychodzące | shown while the list keeps its seeded name |
| Someday | Kiedyś | capitalized and quoted where it names the view or qualifies tasks („Kiedyś”) |
| Due (the deadline field) | Termin | "Termin: %@" leads a row, "3 dni po terminie" marks a past deadline, Zaległe is overdue |
| Open (a task not yet done) | Do zrobienia | the status, never otwarte; W toku is In Progress; lists that are not archived are Aktywne |
| Blocked, cancelled, completed | Zablokowane, Anulowane, Ukończone | |
| Done (a button) and done (a state) | Gotowe, Ukończone, Wykonane | Gotowe closes a sheet; a finished task is Ukończone; Wykonane marks a habit complete for its period |
| Defer and snooze | Odłóż, Ukryj do | Odłóż moves a task to a later day; Ukryj do hides a task until a date; a reminder's snooze action is "Przypomnij za 1 godzinę" |
| Plan (verb) | zaplanować | |
| Schedule (the day pane) | Harmonogram | Zaproponuj godziny proposes one; Godziny dnia are the day hours |
| Capture (quick add) | Szybkie dodawanie | the capture tab, which has little room, reads Dodaj |
| Review (the day and the week) | Podsumowanie | podsumowanie tygodnia for the week; its fields are Sukcesy, Przeszkody, Wnioski |
| Memory | Pamięć | one entry is a wpis |
| Assistant, AI | asystent, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | nawyk, odhaczenie, seria, kamień milowy | Odhacz is the check-in action |
| Depends on | Zależy od | |
| Recurrence | powtarzanie | Powtarzanie is the field, "powtarza się" the state, Co the interval; the modes are Regularnie and Po ukończeniu |
| Sync, snapshot | synchronizacja, migawka | a sync record is a rekord |
| Apple features | Ustawienia, Kalendarz, Przypomnienia, Skróty, Siri, Spotlight, Fokus, Ustawienia systemowe, ekran blokady | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed in the second person singular (ty), never as Pan or
  Pani, and a pronoun inside a sentence is lowercase ("na twoje konto iCloud").
  Buttons, menu items, intent titles, and instructions are imperatives ("Dodaj
  zadanie", "Ukończ zadanie Lorvex", "Włącz dostęp do Kalendarza"); an intent's
  description is a third-person statement ("Oznacza zadanie Lorvex jako
  ukończone."); a confirmation after an action is an impersonal -no or -to form
  ("Ukończono zadanie „%@”.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names are lowercase. Only proper names,
  Apple's feature names, and Lorvex's own view names inside a sentence
  („Dzisiaj”, „Kiedyś”, „Kalendarz”, „Pamięć”) take a capital, and those view
  names are quoted. The menu bar panel's Today switch, which has little room,
  reads "Dziś".
- User content (task titles, list names) is quoted with „ ”, never « » or
  straight quotes, and only where the English quotes it. An ellipsis is the
  single character … wherever English has one. Product names stay Latin and are
  not declined ("w Lorvex"), while Apple's device names are ("na Macu", "na
  iPhonie", "z iPhone’a", the apostrophe marking an ending added to a silent
  final letter). Apple's app names are declined ("w Ustawieniach systemowych"),
  and the Shortcuts app is "ze Skrótów".
- A count is tied to the word after it with a no-break space ("%lld\u00a0zadań"
  in the catalog), so a wrapping headline never ends a line on a bare number;
  `verify_localization_catalog.py` rejects a plain space there.
- The thousands separator is a no-break space ("10 000"), "około" stands for
  "about", and "opcjonalnie" for "optional". A date format hint reads
  RRRR-MM-DD and a time hint GG:MM.
- `one` selects only 1, as in English, so a top-level `one` form may leave the
  number out; a substitution's `one` still contains `%arg`. `few` selects 2 to 4,
  22 to 24, and so on, and `many` selects 0, 5 to 21, 25 to 31, and so on, so
  12 to 14 are `many`. A plural entry carries `one`, `few`, `many`, and `other`,
  and every count varies in all four: nominative singular after 1 ("1 zadanie"),
  nominative plural after 2 to 4 ("2 zadania"), genitive plural after 5 or more
  ("5 zadań"), and genitive singular for `other` ("1,5 zadania"). A verb agrees
  with the number: a plural verb after 2 to 4 ("Na dziś zostały 2 zadania"), a
  neuter singular verb after 5 or more and after 1 ("Na dziś zostało 5 zadań",
  "Na dziś zostało 1 zadanie"). Where agreement would force an awkward phrase,
  all four forms read alike with the number first or last ("3 do zrobienia",
  "Liczba list: 3"), and a compound adjective such as "3-dniowa seria" is the
  same in every form.
- Status words agree with what they describe: Zablokowane, Anulowane, and
  Ukończone for a task; Zarchiwizowane for lists and habits.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation, because
  Polish runs about a fifth longer than English ("7 dni" for the menu bar
  panel's Next 7 Days switch, "Nie zdąży" for Won’t fit, "zost." as the caption
  under the remaining-tasks ring, "Zapisz zadanie" as a short title).
  Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Polish day, date, time,
  duration, repeat, and priority words for a user who reads Polish, so the
  Polish capture hint gives Polish examples ("jutro", "o 15:00", "co
  poniedziałek", "20 min"). Polish says a clock time with "o", so the time
  example says "o". The parser reads ą, ć, ę, ń, ó, ś, ź, and ż as the letter
  without its mark and ł as l, and the title keeps the letters that were typed.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are singular imperatives
  that name the app exactly once, leave it undeclined, and put it at the end
  ("Dodaj zadanie w ${applicationName}").

## Japanese conventions

The `ja` catalogs are Japanese as written in Japan; ja-JP and every other
Japanese locale select them. They follow Apple's Japanese usage (設定,
カレンダー, ショートカット, 集中モード) and keep one term per concept across every
catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and in
Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | タスク, リスト, タグ | a task's checklist is a チェックリスト and its item a 項目 |
| Inbox (the seeded list) | インボックス | shown while the list keeps its seeded name |
| Today | 今日 | 明日 is Tomorrow; the menu bar panel's switches read 今日 and 今後7日間 |
| Someday | いつか | quoted as 「いつか」 inside a sentence |
| Due (the deadline field) | 期限 | "期限：%@" leads a row, "3日遅れ" marks a past deadline |
| Overdue | 期限切れ | |
| Open (a task not yet done) | 未完了 | the status and the filter |
| In progress | 進行中 | the In Progress status; 開始済み marks a task that has started |
| Blocked, cancelled | ブロック中, キャンセル済み | |
| Done (a button) and done (a state) | 完了, 完了済み | 完了 closes a sheet and completes a task; 完了済み is the Completed status and filter |
| Defer | 延期 | moves a task to a later day ("明日に延期") |
| Snooze | スヌーズ | moves a reminder ("1時間スヌーズ") |
| Reminder, notification | リマインダー, 通知 | a task's reminder is a リマインダー, the system's alert a 通知 |
| Plan | 計画 | the day a task is planned for is its 予定日, and putting a task on a day reads 予定にする ("今日の予定にしました") |
| Schedule (the day pane) | スケジュール | 時刻を提案 proposes one; スケジュール済み is the Scheduled filter |
| Capture (quick add) | クイック入力 | the watch's capture button, which has little room, reads 追加 |
| Review (the day and the week) | 振り返り | its fields are 成果, 障害, 学び |
| Memory | メモリ | where English says notes, Japanese says メモ |
| Assistant, AI | アシスタント, AI | Claude and MCP stay as they are |
| Habit | 習慣 | |
| Check-in | チェックイン | |
| Streak | 連続記録 | "7日連続" is a counted streak |
| Milestone | マイルストーン | "次は7日" is the compact label for the next one |
| Depends on | 依存先 | the relation between tasks is a 依存関係 |
| Repeat | 繰り返し | the modes are 定期 and 完了後 |
| Sync, snapshot | 同期, スナップショット | |
| Apple features | 設定, カレンダー, ショートカット, 集中モード, ロック画面, システム設定 | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- Sentences end in です or ます ("「%@」を完了しました。", "同期は一時停止のままです。"),
  and an instruction ends in ください ("繰り返しの間隔は、1〜10,000の整数にしてください。").
  A button, menu item, tab, section header, or intent title is a noun or a
  dictionary-form phrase ("タスクを追加", "削除", "読み取る"); an intent description
  is a です/ます sentence.
- The reader is not addressed. あなた appears only where a headline contrasts the
  person with the assistant or marks what is theirs ("最終判断はあなたに",
  "あなただけのもの").
- User content (a task title, a list name) is quoted with 「 」, only where the
  English quotes it. A Lorvex view, a button, and an Apple app or settings name
  take 「 」 when a sentence names them ("「設定」>「アシスタント」でLorvexを再接続する",
  "「いつか」"). “ ” and straight quotes are not used.
- Punctuation is full width (、。？！：（）), a range is written 〜 ("1〜10,000",
  "%2$@〜%3$@"), and an ellipsis is the single character … wherever the English
  has one.
- No space separates Japanese from Latin letters or digits ("Lorvexのデータ",
  "今後7日間", "1時間スヌーズ"). The exceptions are a display name ("Lorvex 今日")
  and a label set beside its value ("今日 2/5"). A key's name is Latin followed by
  キー ("Returnキー").
- Tasks, events, and records are counted with 件 ("残り3件", "イベント2件"),
  completions with 回, and spans with 日, 週間, and か月 ("3週間", "2か月"). Japanese
  has the single plural category `other`, so a plural entry is one plain string
  that shows the number wherever the English forms show it.
- Katakana spellings follow Apple's Japanese UI and are the same in every
  catalog. The long-vowel mark is written in カレンダー, リマインダー, エラー, コピー,
  ヘルパー, and サイドバー and omitted in サーバ, フォルダ, フィルタ, and インスペクタ.
- A third-party app is "App" in the iOS and watchOS catalogs ("他のカレンダーApp",
  "Apple WatchのApp") and アプリ in the macOS catalog
  ("アプリを再インストールしてください"), following each platform's system wording.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation ("枠なし"
  for Won't fit, "今後7日間" for the menu bar panel's Next 7 Days switch, "残り" as
  the caption under the remaining-tasks ring, "今日の計画" as a short title).
  Accessibility labels may be longer ("今日の残りは3件です").
- The capture parser (`LorvexCaptureParser`) reads Japanese day, time, and
  duration words for a user who reads Japanese, so the Japanese capture hint
  gives Japanese examples in 「 」 (「明日」「午後3時」「毎週月曜」「30分」). Its `#`
  example carries an invisible word joiner (U+2060) after the `#`, so the
  example never splits across lines.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` name the app exactly
  once, attach a particle to it without a space, and are noun or dictionary-form
  phrases ("${applicationName}にタスクを追加", "${applicationName}を開く").

## Korean conventions

The `ko` catalogs are Korean as written in South Korea; ko-KR and every other
Korean locale select them. They follow Apple's Korean usage (설정, 캘린더, 단축어,
집중 모드) and keep one term per concept across every catalog, so a thing reads
the same on the Mac, iPhone, watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | 할 일, 목록, 태그 | a task's checklist is a 체크리스트 and its item a 항목 |
| Inbox (the seeded list) | 수신함 | shown while the list keeps its seeded name |
| Today | 오늘 | 내일 is Tomorrow; the menu bar panel's switches read 오늘 and 앞으로 7일 |
| Someday | 언젠가 | quoted as ‘언젠가’ inside a sentence |
| Due (the deadline field) | 기한 | "기한: %@" leads a row, "3일 지연" marks a past deadline |
| Overdue | 기한 초과 | |
| Open (a task not yet done) | 미완료 | the status and the filter |
| In progress | 진행 중 | the In Progress status; 시작됨 marks a task that has started |
| Blocked, cancelled | 차단됨, 취소됨 | |
| Done (a button) and done (a state) | 완료, 완료됨 | 완료 closes a sheet and completes a task; 완료됨 is the Completed status and filter |
| Defer | 미루기 | moves a task to a later day ("내일로 미룰 수 있습니다") |
| Snooze | 다시 알림 | moves a reminder ("1시간 후 다시 알림") |
| Reminder, notification | 알림 | one word names a task's reminder and the system's notification |
| Plan | 계획 | the day a task is planned for is its 예정일, and 예정 marks what is planned for a day ("내일 예정") |
| Schedule (the day pane) | 일정 | 시간 제안 proposes one; 예정됨 is the Scheduled filter |
| Capture (quick add) | 빠른 추가 | the watch's capture button, which has little room, reads 추가 |
| Review (the day and the week) | 회고 | its fields are 성과, 걸림돌, 배운 점 |
| Memory | 메모리 | where English says notes, Korean says 메모 |
| Assistant, AI | 어시스턴트, AI | Claude and MCP stay as they are |
| Habit | 습관 | |
| Check-in | 체크인 | |
| Streak | 연속 기록 | "7일 연속" is a counted streak |
| Milestone | 마일스톤 | "다음: 7일" is the compact label for the next one |
| Depends on | 의존 대상 | the relation between tasks is a 의존 관계 |
| Repeat | 반복 | the modes are 정기적으로 and 완료 후 |
| Sync, snapshot | 동기화, 스냅샷 | |
| Apple features | 설정, 캘린더, 단축어, 집중 모드, 잠금 화면, 시스템 설정 | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight; a third-party app is 앱 |

- Sentences end in 합니다 or 입니다 ("“%@” 할 일을 완료했습니다."), an instruction
  in 하세요 ("Apple Watch 앱을 다시 여세요"), and a question in 까요 ("중요해질
  때까지 ‘언젠가’에 보관할까요?"). A button, menu item, tab, section header, or
  intent title is a noun or noun phrase ("추가", "삭제", "미루기", "시간 제안"); an
  intent description is a 합니다 sentence ("Lorvex 습관 완료 기록을 읽습니다."). An
  empty state is a noun phrase ending in 없음 ("계획 없음", "‘언젠가’ 할 일 없음").
- The reader is not addressed with a pronoun. The subject is left out, and 직접
  or 본인 stands where the English stresses "you" ("최종 결정은 직접 하세요",
  "사용자 본인의 iCloud 계정").
- User content (a task title, a list name) is quoted with “ ”, only where the
  English quotes it ("“%@” 할 일을 완료했습니다."). A Lorvex view, a button, or a
  calendar named inside a sentence is set in ‘ ’ ("‘언젠가’", "‘시간 제안’", "전용
  ‘Lorvex’ 캘린더"). A Settings path is written as Apple writes it, names joined
  by > without quotes ("설정 > 어시스턴트").
- A particle whose form depends on the sound before it (이/가, 은/는, 을/를, 와/과,
  으로/로) never follows a placeholder directly, because the substituted text
  decides the right form; a fixed noun stands between them ("“%@” 할 일을"). A
  particle attaches directly to a Latin product name ("Lorvex를", "iPhone에서").
- Korean orthography sets the spaces: words are separated, and a counter
  attaches to its number ("3개", "5분", "7일"). A Latin word or product name is
  separated from the Korean word after it by a space ("Lorvex 데이터"), except
  where a particle attaches to it. A key's name is Latin followed by 키
  ("Return 키").
- 개 counts tasks, events, and items ("할 일 3개", "이벤트 2개", "항목 3개"), 회
  counts occurrences ("%lld회 완료", "주 3회"), 건 counts sync records ("대기 중
  3건"), and 일, 주, and 개월 span time ("7일", "2주", "3개월"). Korean has the single
  plural category `other`, so a plural entry is one plain string that shows the
  number wherever the English forms show it. A range is written with ~
  ("%2$@~%3$@"), and an ellipsis is the single character … wherever the English
  has one.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation ("자리
  없음" for Won't fit, "앞으로 7일" for the menu bar panel's Next 7 Days switch,
  "남음" as the caption under the remaining-tasks ring, "오늘 계획" as a short
  title). Accessibility labels may be longer ("오늘 남은 할 일 3개").
- The capture parser (`LorvexCaptureParser`) reads Korean day, time, and
  duration words for a user who reads Korean, so the Korean capture hint gives
  Korean examples in “ ” (“내일”, “오후 3시”, “매주 월요일”, “30분”). Its `#` example
  carries an invisible word joiner (U+2060) after the `#`, so the example never
  splits across lines.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` name the app exactly
  once and use only particles whose form does not depend on the sound before
  them (에, 에서), so the app name works whatever it is
  ("${applicationName}에 할 일 추가", "${applicationName} 열기").

## Traditional Chinese conventions

The `zh-Hant` catalogs are Traditional Chinese as written in Taiwan; zh-TW,
zh-HK, zh-MO, and every other Traditional-script locale select them. They follow
Apple's Taiwan usage (設定, 行事曆, 捷徑, 專注模式) and keep one term per concept
across every catalog, so a thing reads the same on the Mac, iPhone, watch,
widgets, and in Shortcuts. The text is written for Taiwan, not converted from
`zh-Hans`: where the two differ in vocabulary, the table gives the Taiwan term.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | 任務, 清單, 標籤 | a task's checklist is a 核對清單 and its item a 項目 |
| Inbox (the seeded list) | 收件匣 | shown while the list keeps its seeded name |
| Today | 今天 | 明天 is Tomorrow; the menu bar panel's switches read 今天 and 未來 7 天 |
| Someday | 將來某天 | quoted as 「將來某天」 inside a sentence |
| Due (the deadline field) | 到期 | "%@到期" follows a date, "逾期 3 天" marks a past deadline |
| Overdue | 已逾期 | |
| Open (a task not yet done) | 未完成 | the status and the filter |
| In progress | 進行中 | the In Progress status; 已開始 marks a task that has started |
| Blocked, cancelled | 受阻, 已取消 | |
| Done (a button) and done (a state) | 完成, 已完成 | 完成 closes a sheet and completes a task; 已完成 is the Completed status and filter |
| Defer | 延後 | moves a task to a later day |
| Snooze | 稍後提醒 | moves a reminder ("1 小時後提醒") |
| Reminder, notification | 提醒, 通知 | a task's reminder is a 提醒, the system's alert a 通知 |
| Plan | 規劃 | the day a task is planned for is its 預定日期, and putting a task on a day reads 安排 ("已安排在明天") |
| Schedule (the day pane) | 行程 | 建議時間 proposes one; 已排程 is the Scheduled filter |
| Capture (quick add) | 快速新增 | the watch's capture button, which has little room, reads 新增 |
| Review (the day and the week) | 回顧 | its fields are 成果, 阻礙, 心得 |
| Memory | 記憶 | where English says notes, Chinese says 備註 |
| Assistant, AI | 助理, AI | Claude and MCP stay as they are |
| Habit | 習慣 | |
| Check-in | 打卡 | "尚無打卡紀錄" when there is none |
| Streak | 連續紀錄 | "連續 7 天" is a counted streak |
| Milestone | 里程碑 | "下一個里程碑：7 天" is the compact label for the next one |
| Depends on | 相依於 | the relation between tasks is a 相依關係 |
| Repeat | 重複 | the modes are 定期 and 完成後 |
| Sync, snapshot | 同步, 快照 | |
| Apple features | 設定, 行事曆, 捷徑, 專注模式, 鎖定畫面, 系統設定 | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight; a third-party app is App |

- The reader is addressed as 你, never 您 ("依照你的行事曆"). A button, menu item,
  tab, section header, or intent title is a short verb phrase or noun ("新增任務",
  "稍後提醒"); an instruction is an imperative ("請在兩部裝置上都更新 Lorvex"); a
  confirmation after an action reports the result ("已完成「%@」。", "已將「%@」安排在今天。").
- Vocabulary is Taiwan usage, chosen term by term: 資料 (data), 檔案 (file),
  資料夾 (folder), 伺服器 (server), 裝置 (device), 帳號 (account), 小工具
  (widget), 選單列 (menu bar), 儲存 (save), 匯出 and 匯入 (export and import),
  and 拷貝 (copy, the word Apple's Taiwan interface uses for the clipboard). A
  week is 週 ("每週", "每 2 週"), never 周.
- Punctuation is full width (，。？！：；（）、). 「 」 quotes user content (a
  task title, a list name) only where the English quotes it, and also a Lorvex
  view, a button, and an Apple app or settings name when a sentence names them
  ("「設定」>「助理」", "「將來某天」"). A range reads 至 or 到 ("%2$@ 至 %3$@",
  "1 到 10,000").
- An ordinary space separates Chinese from Latin letters and Arabic numerals in
  running text ("Lorvex 可以", "3 個任務", "未來 7 天"). Between a number
  placeholder and a Chinese unit the space is a no-break space (U+00A0), so a
  line never ends on the number and starts the next with its unit; the verifier
  requires it for Chinese and Japanese. Example text a person types, such as
  "下午3點" in the capture hint, is written the way people type it. A key's name
  is Latin followed by 鍵 ("Return 鍵").
- 個 counts tasks and events ("3 個任務", "2 個事件"), 筆 counts records ("略過了
  3 筆紀錄"), 次 counts occurrences ("完成 7 次"), and 天, 週, and 個月 span time.
  Chinese has the single plural category `other`, so a plural entry is one plain
  string that shows the number wherever the English forms show it.
- 紀錄 names a record that is kept (完成紀錄, 連續紀錄, 歷史紀錄, 筆紀錄), and 記錄
  names a log or the act of logging (變更記錄, 診斷記錄, 活動記錄, 已記錄「%@」).
- 規劃 is planning in general ("規劃今天") and 安排 puts a task on a day ("已將「%@」
  安排在今天"); 計劃 and 計畫 are not used.
- macOS text says 按一下 ("按一下 ＋") and iOS text says 點一下 ("點一下 ＋"). A
  third-party app is "App" ("Apple Watch 上的 App", "其他行事曆 App").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation ("排不下"
  for Won't fit, "未來 7 天" for the menu bar panel's Next 7 Days switch, "剩餘"
  as the caption under the remaining-tasks ring, "規劃今天" as a short title).
  Accessibility labels may be longer ("今天還剩 3 個任務").
- The capture parser (`LorvexCaptureParser`) reads Chinese in either script:
  it reads the Traditional characters its Chinese words use (後, 週, 這, 禮, 點,
  鐘, 時, 個, 兩, 緊, 號, and 頭) as their Simplified forms, so "後天", "下週三",
  "每月5號", "30分鐘", and "兩個鐘頭" read like their Simplified spellings. The
  capture hint therefore writes every example in Traditional characters ("明天",
  "下午3點", "每星期一", "30分鐘"). Its `#` example carries an
  invisible word joiner (U+2060) after the `#`, so the example never splits
  across lines.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` name the app exactly
  once and keep a space on each side of it, as around any Latin word
  ("在 ${applicationName} 中新增任務", "開啟 ${applicationName}").

## How to add a new locale

Every catalog and every shipping bundle must carry the same language set, so a
locale is added everywhere in one change. `script/localization_transfer.py`
moves translations in and out of all eight String Catalogs, the App Shortcuts
catalog, and the InfoPlist.strings targets, for one language or for a batch of
several. The steps below name one language; "Translating a batch" after them
shows the same commands for several.

1. Make sure `PLURAL_CATEGORIES` in `script/verify_localization_catalog.py`
   declares the language (the target set above is declared). Look up anything
   new in the CLDR plural rules and list only the categories integer counts
   select.
2. Export what the language lacks:

   ```sh
   python3 script/localization_transfer.py export --language fr --output /tmp/fr.json
   ```

   Each item carries its catalog, key, comment, English source, the other
   shipped languages' translations for reference, and a null `translation`.
   `--catalog <path>` limits the export to one catalog, for working in
   pieces, and `--text` prints the items as a readable listing instead of
   JSON (`--offset`/`--limit` select a window of the items in either form).
   Fill every `translation` with a string, or for plural entries with
   `{"plural": {...}}` (the categories the document's `pluralCategories`
   requires) or a substitution shorthand; the script's docstring lists the
   shapes. Keep every placeholder (`%@`, `%lld`, `%1$@`, `%#@name@`, `%arg`)
   and every `${applicationName}` token.
3. Import it:

   ```sh
   python3 script/localization_transfer.py import --language fr /tmp/fr.json
   ```

   Items whose English changed since the export, or whose translation fails
   the verifier's entry checks (placeholders, plural categories), are listed
   and skipped; the rest are written. Export again to see what remains.

   Translations can also go in as a JSON object mapping keys of one catalog
   to their translations (the same shapes), which is easier to write in
   batches than a filled export document. `apply` checks them against the
   catalog's current English and overwrites any earlier translation of the
   same keys, so it also serves revision passes:

   ```sh
   python3 script/localization_transfer.py apply --language fr \
     --catalog Sources/LorvexWatch/Resources/Localizable.xcstrings /tmp/fr-watch.json
   ```
4. Add the language to `AppLanguage` (`Sources/LorvexCore/Support/AppLanguage.swift`)
   with its endonym. `LocalizationTests` fails until the picker offers exactly
   the catalogs' languages. The picker sorts itself by endonym, and
   `AppLanguageTests` pins that order, so add the language to its expected
   list where its endonym falls.
5. Sync bundle metadata so the OS includes the locale in app, complication, and
   widget bundles, and in the Info.plist embedded in the debug executable
   (`Config/LorvexAppleSwiftPM-Info.plist`, described under the headless
   screenshots below):

   ```sh
   python3 script/verify_localization_catalog.py --write-bundle-localizations
   ```

   It rewrites only `CFBundleLocalizations` (and a wrong
   `CFBundleDevelopmentRegion`), so each plist keeps its comments and layout.

6. Run `python3 script/verify_localization_catalog.py`. The verifier derives
   the required language set from the catalogs and fails until every catalog and
   shipping bundle has the same complete set.
7. Add a conventions section for the language to this document, as the
   Simplified Chinese, Spanish, French, Italian, Brazilian Portuguese, Russian,
   Ukrainian, Polish, Japanese, Korean, Traditional Chinese, Hindi, and Arabic
   ones: one term per concept across every catalog, punctuation and quotation
   marks, spacing around numbers and Latin words.
8. Capture the macOS tour and the iOS screens in the language (see "Headless
   screenshots") and look for truncated, clipped, or overlapping text.

A language prepared on a branch merges without hand-resolving catalog
conflicts: keep the main checkout's catalogs, then copy the branch's
translations for every entry whose English source is unchanged:

```sh
python3 script/localization_transfer.py import --language fr --from-checkout ../lorvex-fr
```

An entry whose key moved to another catalog on either side after the branch
started is still matched: when the branch's matching catalog lacks the key,
the translation comes from the branch catalog that holds the key with the same
English source, provided every such catalog agrees on it. The command lists
the entries still missing the language (keys added or reworded on main after
the branch started); translate those through an export before the merge
commit.

### Translating a batch

A batch of languages is prepared on one branch, and every language in it is
complete before the batch merges. A catalog entry holds all of its languages,
so translating the batch together reads each entry's English source and
developer comment once. Repeat `--language` to move several languages in one
call:

```sh
python3 script/localization_transfer.py export \
  --language fr --language it --language pt-BR --text --offset 0 --limit 80
```

The listing, and the JSON document without `--text`, include every entry that
lacks at least one of the languages. An item carries its catalog, key, comment,
and English source (every plural and substitution form), and a `translations`
object with one null slot for each language that still lacks the entry; an
entry that has some of the languages gets slots only for the rest, and a
"lacks" line in the listing names them. The other shipped languages'
translations are left out. `--offset` and `--limit` select a window of the
catalog items in the listing and in the JSON document alike (the
InfoPlist.strings items belong to the last window), and an export lists only
what is still missing, so each page of work starts at offset 0.

Translations go in page by page, so a run that stops partway keeps what it
imported. `apply` takes a JSON object mapping each key of one catalog to an
object of language to translation, in the same shapes as a single language, and
leaves alone any language a key omits:

```sh
python3 script/localization_transfer.py apply \
  --language fr --language it --language pt-BR \
  --catalog Sources/LorvexWatch/Resources/Localizable.xcstrings /tmp/watch.json
# /tmp/watch.json: {"watch.session.end": {"fr": "…", "it": "…", "pt-BR": "…"}}
```

`import FILE` writes a filled several-language JSON document, the slots of
`translations` filled in. The document names its languages, so `--language` may
be left out. Each slot is checked on its own against the verifier's entry
checks: a slot that fails is listed and skipped, the others are written, and
the command exits 1. A batch branch merges with one command that copies each
language in turn and lists what each still lacks:

```sh
python3 script/localization_transfer.py import \
  --language fr --language it --language pt-BR --from-checkout ../lorvex-batch
```

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

A launch argument stands in for the system language list, so a regional or
multi-language system is tested the same way, for example
`-AppleLanguages "(fr-FR, zh-CN)" -AppleLocale fr_FR` for a French Mac whose
second language is Simplified Chinese. The in-app picker treats the argument
as the system language and still shows "System Default".

A right-to-left language mirrors both apps from `-AppleLanguages` alone, the
way it does when a person picks the language: the Mac app turns AppKit's text
direction on for itself (see "Following the system language"). A capture that
needs a left-to-right layout of a right-to-left language passes
`-AppleTextDirection NO`, which the app leaves as given.

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

Native lookup reads compiled `.strings` / `.stringsdict` tables, not the
catalog. Under Swift Build (products in `.build/out/Products/<Configuration>`),
`swift build` compiles each catalog into those tables; the native SwiftPM build
system (products in `.build/<triple>/<configuration>`) only copies the raw
`.xcstrings`. `script/compile_xcstrings.sh` compiles any raw catalog it finds
and accepts bundles the build already compiled, so `verify_all.sh` runs it after
`swift build --build-tests` and before `swift test` under either system.
Xcode/XcodeGen builds compile catalogs as part of the normal build.
