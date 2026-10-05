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

**Dates that open a line.** System date data writes weekday and month names
in lowercase in Spanish, French, Italian, Brazilian Portuguese, Russian,
Ukrainian, Polish, Dutch, and Romanian ("lunes, 21 de septiembre", "сентябрь
2026 г."). The app's text is in sentence case, so a title, heading, or label
that opens with a date must start with a capital. Such a date is written with
`position: .leading` (`LorvexDateFormatters.string`, `range`, `lorvexDayLine`,
`lorvexShortDayLine`; a `Date.FormatStyle` takes
`capitalizationContext: .beginningOfSentence`), which applies the language's
own capitalization of the start of a sentence ("Lunes, 21 de septiembre",
"Сентябрь 2026 г."). A date that follows other words in a sentence keeps the
default `.inline` position, so a Siri reply that names the day after other
words keeps its lowercase weekday. A relative phrase ("yesterday", "hace 3
días") always starts in lowercase, in every language. `LorvexDateHeadingTests`
pins the month and weekday templates.

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
English, German, Dutch, Turkish, and Greek `one`/`other`, where `one` selects
only 1; Spanish and Italian `one`/`other`, and French and Brazilian Portuguese
`one`/`other` where `one` selects both 0 and 1, each with an optional `many`
that only round millions select and that falls back to `other` when absent; Hindi and Persian `one`/`other`, where `one` selects both 0 and
1; Urdu `one`/`other`, where `one` selects only 1; Hebrew `one`/`other` with an
optional `two` for the dual, where `one` selects only 1 and `two` only 2; Chinese
(Simplified and Traditional), Indonesian, Japanese, Korean, Malay, Thai, and
Vietnamese only `other`; Russian and
Ukrainian
`one`/`few`/`many`/`other`, where `one` selects 1,
21, 31, and so on (never 11), `few` 2 to 4, 22 to 24, and so on (never 12 to 14),
and `many` 0, 5 to 20, 25 to 30, and so on; Polish `one`/`few`/`many`/`other`,
where `one` selects only 1, `few` 2 to 4, 22 to 24, and so on, and `many` 0, 5 to
21, 25 to 31, and so on, 12 to 14 included; Romanian `one`/`few`/`other`, where
`one` selects only 1, `few` 0, 2 to 19, 101 to 119, 201 to 219, and so on, and
`other` 20 to 100, 120 to 200, and so on; Arabic all six: `zero` selects 0,
`one` 1, `two` 2, `few` 3 to 10, `many` 11 to 99, and `other` 100 and over.
In Russian, Ukrainian, and Polish only fractions select `other`; the format
still requires the form, so it carries the genitive singular ("1,5 дня").
In Romanian a fraction selects `few`.
Apple's lookup honors an explicit `zero` entry in every language.

A `one` form may leave the number out ("Once a week") only in a language whose
`one` means exactly 1, as in English, German, Dutch, Spanish, Italian, Romanian,
Polish, Turkish, and Greek. French,
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
  `ar`; `de-AT` and `de-CH` select `de`; `el-GR` and `el-CY` select `el`;
  `es-MX`, `es-419`, and `es-ES` select `es`; `fr-CA` and `fr-CH` select `fr`;
  `hi-IN` selects `hi`; `id-ID` selects `id`; `it-CH` selects `it`; `ja-JP`
  selects `ja`; `ko-KR` selects `ko`; `ms-MY`, `ms-SG`, and `ms-BN` select
  `ms`; `nl-BE` selects `nl`; `pl-PL` selects `pl`; `ro-MD` selects `ro`;
  `ru-RU` and `ru-KZ` select `ru`; `th-TH` selects `th`; `tr-TR` and `tr-CY`
  select `tr`; `uk-UA` selects `uk`; `vi-VN` selects `vi`; `en-GB` selects
  `en`. `pt-PT` selects `pt-BR`, the one Portuguese variety shipped.
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
  Mac set to Swedish, then Simplified Chinese, shows Simplified Chinese.
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
alphabetically, then each other script as a group (Greek, Cyrillic, Hebrew,
Arabic script, Devanagari, Thai, Hangul, Han). The picker reads only the
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
the app's: Arabic, Persian, Urdu, or Hebrew chosen in the in-app picker or
under System Settings > Applications on an English Mac would show its text laid
out left to right.
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
Arabic (`ar`), German (`de`), Greek (`el`), Spanish (`es`), Persian (`fa`),
French (`fr`), Hebrew (`he`), Hindi (`hi`), Indonesian (`id`), Italian (`it`),
Japanese (`ja`), Korean (`ko`), Malay (`ms`), Dutch (`nl`), Polish (`pl`),
Brazilian Portuguese (`pt-BR`), Romanian (`ro`), Russian (`ru`), Thai (`th`),
Turkish (`tr`), Ukrainian (`uk`), Urdu (`ur`), Vietnamese (`vi`), Simplified
Chinese (`zh-Hans`), and Traditional Chinese (`zh-Hant`).

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
language in the batch complete before the batch merges. Arabic, Persian,
Urdu, and Hebrew are right-to-left. Arabic's mirrored layout is captured and
reviewed on the macOS preview tour, the iOS screens, and the iOS widget gallery;
the Persian, Urdu, and Hebrew layouts are captured and reviewed on the macOS
preview tour and the iPad screens. The watch and CarPlay surfaces have no
capture in any right-to-left language.

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

## Persian conventions

The `fa` catalogs are standard Persian as written in Iran, in the neutral polite
register of Apple's Persian interfaces (تقویم, اعلان‌ها, میان‌برها). Every
Persian locale (fa-IR, fa-AF) selects them. They keep one term per concept across
every catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and
in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | کار, فهرست, برچسب | plurals کارها, فهرست‌ها, برچسب‌ها; the loanword تسک is not used; a task's checklist is a چک‌لیست and its item a مورد |
| Inbox (the seeded list) | صندوق ورودی | shown while the list keeps its seeded name |
| Today, tomorrow, yesterday | امروز, فردا, دیروز | |
| Someday | شاید بعدها | quoted inside a sentence («شاید بعدها») |
| Due, overdue | سررسید, عقب‌افتاده | |
| Open (a task not yet done) | باز | در حال انجام is the In Progress status and مسدود a blocked task |
| Done and complete | تمام, انجام‌شده, تکمیل‌شده, تکمیل | تمام closes a sheet; انجام‌شده and انجام شد mark finished work; تکمیل‌شده is the Completed status; تکمیل completes a task |
| Cancel, cancelled | لغو, لغوشده | |
| Defer and snooze | موکول کردن, تعویق | defer moves a task to a later day (موکول به فردا); snooze moves a reminder (تعویق یک‌ساعته) |
| Plan, schedule | برنامه‌ریزی, زمان‌بندی | برنامه alone means the app, so a schedule is never برنامه |
| Capture (quick add) | افزودن | افزودن کار names the capture sheet and افزودن سریع the quick-capture entry |
| Review (the day and the week) | مرور | مرور روزانه, مرور هفتگی; its fields are موفقیت‌ها, موانع, آموخته‌ها; the assistant's briefing is a خلاصه |
| Memory | حافظه | one entry is a مورد |
| Assistant, AI | دستیار, هوش مصنوعی | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone, goal | عادت, ثبت, زنجیره, نقطه‌ی عطف, هدف | ثبت is also the check-in action |
| Waits on, dependency | منتظر, وابستگی | |
| Reminder, recurrence | یادآور, تکرار | |
| Sync, snapshot | همگام‌سازی, اسنپ‌شات | |
| Settings | تنظیمات | |
| Apple features | تقویم, رویداد, اعلان‌ها, صفحه قفل, میان‌برها, حالت تمرکز, ویجت | Dock and Spotlight stay Latin |

- The reader is addressed politely in the plural. Instructions are imperatives
  ("Lorvex را دوباره راه‌اندازی کنید"); buttons, menu items, and intent titles
  are verbal nouns ("افزودن", "حذف", "افزودن به تقویم"); a question is a passive
  subjunctive ("فهرست «%@» حذف شود؟"); a confirmation or a failure is a past
  passive ("فهرست %@ از Lorvex حذف شد.", "تعویق یادآور انجام نشد."). Persian does
  not mark gender, so no sentence depends on the reader's. The word برنامه
  alone means the app, and a sentence that would open with the Latin name opens
  with it ("برنامه Lorvex می‌تواند …").
- Letters are the Persian ی (U+06CC) and ک (U+06A9), never the Arabic ي and ك.
  The zero-width non-joiner (U+200C) separates the verb prefixes می‌ and نمی‌
  from their verb ("می‌شود"), the suffixes ها, های, تر, and ای from a word that
  ends in a joining letter ("فهرست‌ها", "مناسب‌تر", "هفته‌ای"), and the parts of
  a compound ("برنامه‌ریزی", "همگام‌سازی", "تکمیل‌شده"). A word ending in a
  non-joining letter takes its suffix without it ("کارها").
- Product and technology names stay Latin: Lorvex, iCloud, CloudKit, Siri,
  Spotlight, Apple Watch, CarPlay, Claude, MCP, and file formats such as JSON,
  CSV, ICS, and ZIP, as do iPhone, iPad, and Mac. The prepositions stand apart
  from them ("در Lorvex", "از iCloud").
- Punctuation is the Persian comma ، semicolon ؛ and question mark ؟. A sentence
  ends with the Latin full stop, and the colon, the parentheses, and the
  single-character ellipsis … are the same as in English.
- Quotation marks are « » (U+00AB, U+00BB; « comes first in the text), never
  straight or curly quotes. They stand wherever the English quotes with curly
  quotes; a name the English leaves bare stays bare unless the sentence needs
  the quotes to show where the name ends ("کار «%@» تکمیل شد.").
- A Persian locale formats numbers in Extended Arabic-Indic digits (fa-IR
  writes "۱۲"), so counts, times, and dates arrive through placeholders and
  the system picks the digits. A number the English writes as a fixed digit is
  written out ("هفت روز آینده", "دوازده‌ساعته"), because an ASCII digit would
  stand beside the system's Persian ones. The exceptions are examples a person
  types: the numbers in the milestone and encouragement hints ("مثلاً 50") and
  the example words of the capture hint, whose digits are Persian ones.
- An `fa` plural entry carries `one` and `other`, and Persian `one` also
  selects 0. A noun stays singular after a number, so the two forms of a count
  are usually alike ("%lld کار باقی مانده"). A `one` form that drops the number
  ("روزی یک بار") comes with a `zero` form that shows it ("روزی %lld بار"), so a
  count of 0 does not read "once". Both forms of a substitution carry `%arg`.
- A string that fills in several values uses positional specifiers (`%1$@`,
  `%2$lld`) wherever the Persian word order differs from the English, never
  concatenation in code.
- Weekday names come from the calendar ("دوشنبه", "سه‌شنبه"). The system's
  ordinal for Persian is the number followed by a full stop ("۲."), which reads
  as an ordinal when the number leads, so a weekday's position in a month is
  "%1$@ %2$@" and its position from the end "%1$@ از آخر %2$@". Lists of
  names are joined by the system's list format.
- A paragraph takes its base direction from its first strong character, so a
  sentence that opens with a Latin name or a placeholder would lay out left to
  right and put its closing punctuation at the wrong end. A sentence is
  therefore written to open with a Persian word ("برنامه Lorvex آماده است."),
  and what the English opens with moves behind it. Short labels, window titles,
  accessibility labels, and format names that are one Latin name ("Lorvex",
  "CSV", "JSON", "CloudKit", "Spotlight") stay as they are. No other
  bidirectional control character is written into a catalog, except one
  left-to-right isolate (U+2066 and U+2069) around the keyboard shortcut on
  the last page of the first-run wizard (`setup.done.capture.detail`), which
  displays "⌘N" as "N⌘" otherwise.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter
  wording than a literal translation ("هفت روز آینده" for the menu bar panel's
  Next 7 Days switch, "همگام‌شده %@" for the watch's sync status). Accessibility
  labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Persian day, date, time,
  duration, repeat, and priority words for a user who reads Persian (the
  Iranian and the Afghan spellings), so the Persian capture hint gives Persian
  examples ("فردا", "ساعت ۳ بعدازظهر", "هر دوشنبه", "۲۰ دقیقه"). Persian says a
  clock time with "ساعت", so the time example says it. A written date is
  counted in the Solar Hijri calendar ("۱۲ مهر") or, when it names a Gregorian
  month, in the Gregorian one ("۵ مارس"), and weeks start on Monday as the
  app's weeks do, so "هفته آینده شنبه" is the Saturday that closes the coming
  week. The parser reads the Persian and Arabic digits as Latin ones and the letters
  that are spelled in more than one way as one (أ, إ, and آ as ا; ي and ى as
  ی; ك as ک; ة as ه), ignores vowel signs and tatweel, and reads a compound
  typed with a space, a zero-width non-joiner, or nothing as one word
  ("سه‌شنبه", "سه شنبه", "سهشنبه"); the title keeps what was typed. The hint's
  examples hold no Latin text, so they need no bidirectional isolate, and
  their digits are the Persian ones a Persian keyboard types.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are spoken singular
  imperatives that name the app exactly once ("یک کار به ${applicationName}
  اضافه کن").

## Urdu conventions

The `ur` catalogs are standard Urdu as written in Pakistan, in the polite آپ
register, with the Perso-Arabic vocabulary the language has and the English
loanwords people say for technology (ٹیگ, اسنوز, ویجٹ, ڈیٹا). Every Urdu locale
(ur-PK, ur-IN) selects them. They keep one term per concept across every
catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and in
Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | کام, فہرست, ٹیگ | plurals کام, فہرستیں, ٹیگز; a task's checklist is a چیک لسٹ and its item an آئٹم |
| Inbox (the seeded list) | ان باکس | shown while the list keeps its seeded name |
| Today, tomorrow, yesterday | آج, آئندہ کل, گزشتہ کل | کل means both "yesterday" and "tomorrow" in Urdu, and the system's relative date formatter writes yesterday as کل and tomorrow as آئندہ کل; a label that names tomorrow alone is therefore آئندہ کل, one that names yesterday is the explicit گزشتہ کل, and inside a sentence tomorrow stays کل ("کل تک ملتوی کریں") |
| Someday | کسی دن | quoted inside a sentence ("کسی دن") |
| Due, overdue | مقررہ تاریخ, تاخیر کا شکار | |
| Open (a task not yet done) | نامکمل | جاری is the In Progress status and رکا ہوا a blocked task |
| Done and complete | ہو گیا, مکمل | ہو گیا closes a sheet or marks finished work; مکمل is the Completed status and مکمل کریں completes a task |
| Cancel, cancelled | منسوخ کریں, منسوخ | |
| Defer and snooze | ملتوی کریں, اسنوز کریں | defer moves a task to a later day; snooze moves a reminder |
| Plan, schedule, agenda | منصوبہ, شیڈول, ایجنڈا | |
| Capture (quick add) | شامل کریں | کام شامل کریں names the capture sheet |
| Review (the day and the week) | جائزہ | روزانہ جائزہ, ہفتہ وار جائزہ; its fields are کامیابیاں, رکاوٹیں, اسباق; the assistant's briefing is a بریفنگ |
| Memory | حافظہ | one entry is an اندراج |
| Assistant, AI | اسسٹنٹ, AI | AI stays Latin; Claude and MCP stay as they are |
| Habit, check-in, streak, milestone, goal | عادت, چیک اِن, تسلسل, سنگ میل, ہدف | چیک اِن کریں is the check-in action |
| Waits on, dependency | انتظار میں, انحصار | |
| Reminder, recurrence | یاد دہانی, تکرار | |
| Sync, snapshot | سنک, اسنیپ شاٹ | |
| Settings | ترتیبات | |
| Apple features | کیلنڈر, نوٹیفکیشنز, لاک اسکرین, شارٹ کٹس, فوکس, ویجٹ | Dock and Spotlight stay Latin |

- The reader is addressed as آپ. Buttons, menu items, instructions, and intent
  titles are polite imperatives ("شامل کریں", "حذف کریں", "کام شامل کریں"); a
  question is the same form ("فہرست "%@" حذف کریں؟"); a confirmation is a
  perfect with گیا or ہو گیا ("فہرست %@ کو Lorvex سے حذف کر دیا گیا۔"); a
  failure is "… نہیں ہو سکا۔". A verb agrees with the noun's gender: کام,
  ایونٹ, ٹیگ, اندراج, and ڈیٹا are masculine; فہرست, عادت, and یاد دہانی are
  feminine. Lorvex takes masculine forms ("Lorvex ویجٹ کیش صاف نہیں کر سکا۔"),
  except directly after ایپ, which is feminine ("یہ ایپ اس طرح بنائی گئی ہے").
  Sentences about the user use the honorific plural.
- Letters are the Urdu ک, ی, ہ, ے, ں, and ھ, never the Arabic ك, ي, and ه. The
  text is plain Urdu; the system renders it in Nastaliq, whose letters stand
  taller and lower than Naskh letters.
- Product and technology names stay Latin: Lorvex, iCloud, CloudKit, Siri,
  Spotlight, Apple Watch, CarPlay, Claude, MCP, AI, and file formats such as
  JSON, CSV, ICS, and ZIP, as do iPhone, iPad, and Mac. They sit in the sentence
  as they are ("ایپ Lorvex میں کھولیں", "اپنی iCloud ترتیبات کھولیں").
- Punctuation is the Urdu full stop ۔ comma ، semicolon ؛ and question mark ؟. The
  colon, the parentheses, and the single-character ellipsis … are the same as
  in English.
- Quotation marks are the straight `"`, never curly quotes or « ». They stand
  wherever the English quotes with curly quotes.
- Urdu locales (ur-PK and ur-IN) format numbers in ASCII digits, so a fixed
  number in the catalog is a digit ("اگلے 7 دن", "12 گھنٹے") as it is in
  English, and counts arrive through placeholders.
- A `ur` plural entry carries `one` and `other`, and `one` selects exactly 1,
  so a `one` form may drop the number ("دن میں ایک بار"). A noun before a
  postposition takes its oblique plural ("%arg دنوں میں ہدف پورا ہوا"), while a
  noun that has no separate plural keeps its form ("%lld کام"). Both forms of a
  substitution carry `%arg`.
- A string that fills in several values uses positional specifiers (`%1$@`,
  `%2$lld`) wherever the Urdu word order differs from the English, never
  concatenation in code. Urdu puts the verb last, so a sentence often needs
  them.
- Weekday names come from the calendar ("پیر", "منگل", "اتوار"). The system's
  ordinal for Urdu is the number followed by a full stop ("2."), which reads as
  an ordinal when the number leads, so a weekday's position in a month is
  "%1$@ %2$@", its position from the end "آخر سے %1$@ %2$@", and the last one
  "آخری %@". Lists of names are joined by the system's list format.
- A paragraph takes its base direction from its first strong character, so a
  sentence that opens with a Latin name or a placeholder would lay out left to
  right and move its closing punctuation (the Urdu full stop belongs to the
  right-to-left run and stays in place; an ASCII mark does not). A sentence or
  an action label is written to open with an Urdu word ("ایپ Lorvex کھولیں",
  "اپنا iCloud ڈیٹا حذف کریں", "اپنے iPhone پر کھولیں"): a label that opened
  with the Latin name would lay out left to right and an Urdu reader would meet
  its Urdu words before the name ("Lorvex میں کھولیں" reads "میں کھولیں
  Lorvex"). Noun-phrase titles that name a Latin product first ("Apple فیچرز",
  "Lorvex فہرست"), window titles, accessibility labels, Siri entity type
  names, and format names stay as they are. No other bidirectional control
  character is written into a catalog, except one left-to-right isolate
  (U+2066 and U+2069) around the keyboard shortcut on the last page of the
  first-run wizard (`setup.done.capture.detail`).
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter
  wording than a literal translation ("اگلے 7 دن" for the menu bar panel's Next
  7 Days switch, "%@ سنک ہوا" for the watch's sync status). Accessibility labels
  may be longer.
- The capture parser (`LorvexCaptureParser`) reads Urdu day, date, time,
  duration, repeat, and priority words for a user who reads Urdu (ur-PK and
  ur-IN), so the Urdu capture hint gives Urdu examples ("کل", "شام 5 بجے", "ہر
  پیر", "20 منٹ", "#فہرست"). Urdu says a clock time with بجے after the hour, so
  the time example carries it. کل is read as tomorrow and پرسوں as the day
  after tomorrow and never as a past day, because the app writes the past day
  گزشتہ کل; a line in the past tense stays unread. A written date is counted in
  the Gregorian calendar, whose months Urdu writes in their own spellings
  (مارچ, مئی, اکتوبر); the months of the Islamic and the Indian calendars are
  not read. Weeks start on Monday as the app's weeks do, so "اگلے جمعہ" is the
  Friday of the week that begins on the coming Monday, and the weekend is
  Saturday and Sunday ("ویک اینڈ" is the coming Saturday). ہفتہ and ہفتے also
  mean "the week", so they name Saturday only beside a mark of a day ("ہفتے
  کو", "ہفتہ اور اتوار") while سنیچر names it anywhere. The parser reads the
  Arabic-Indic and the Extended Arabic-Indic digits as Latin ones and the
  letters that Urdu and Arabic keyboards spell in more than one way as one (the
  alefs with hamza or madda as ا; ي, ى, and ئ as ی; ك as ک; every heh as ہ; ں
  as ن), but keeps the bari ye ے apart from the choti yeh ی, since "ہے" and
  "ہی" are different words. It ignores vowel signs and tatweel, reads a
  compound typed with a space, a zero-width non-joiner, or nothing as one word
  ("سہ پہر", "سہ‌پہر", "سہپہر"), and leaves the title as it was typed. Urdu
  written in Latin letters is not read. A user whose languages hold Urdu
  together with Arabic or Persian also gets Arabic "كل" (all) and Persian "کل"
  (whole) read as tomorrow when no phrase of that language claims them first,
  because the Urdu reading form folds the Arabic kaf into the Urdu one. The
  hint's examples hold no Latin text, so they need no bidirectional isolate,
  and their digits are the ASCII ones Urdu locales format numbers with.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are polite imperatives
  that name the app exactly once ("ایک کام ${applicationName} میں شامل کریں").

## Hebrew conventions

The `he` catalogs are modern Hebrew written without vowel points, in the
register of Apple's Hebrew interfaces (לוח שנה, התראות, קיצורי דרך). Every Hebrew
locale (he-IL and the rest) selects them. They keep one term per concept across
every catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and
in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | משימה, רשימה, תג | plurals משימות, רשימות, תגים; a task's checklist is a רשימת תיוג and its item a פריט |
| Inbox (the seeded list) | תיבת דואר נכנס | shown while the list keeps its seeded name |
| Today, tomorrow, yesterday | היום, מחר, אתמול | |
| Someday | מתישהו | quoted inside a sentence ("מתישהו") |
| Due, overdue | תאריך יעד, באיחור | |
| Open (a task not yet done) | פתוחה | statuses agree with the feminine משימה: פתוחה, הושלמה, בוטלה, חסומה (plural פתוחות, הושלמו); בתהליך is In Progress |
| Done and complete | סיום, הושלמה, השלמה | סיום closes a sheet; הושלמה is the Completed status; השלמה completes a task |
| Cancel, cancelled | ביטול, בוטלה | |
| Allow, allowed (a permission) | אפשר, מותר | אפשר is the platform's button word (אפשר התראות); אישור is only OK |
| Defer and snooze | דחייה, נודניק | defer moves a task to a later day; snooze moves a reminder (נודניק עד) |
| Plan, schedule, agenda | תכנון, לוח זמנים, סדר יום | |
| Capture (quick add) | הוספה | הוספת משימה names the capture sheet |
| Review (the day and the week) | סקירה | סקירה יומית, סקירה שבועית; its fields are הצלחות, חסמים, תובנות; the assistant's briefing is a תדריך |
| Memory | זיכרון | one entry is a רשומת זיכרון |
| Assistant, AI | עוזר, AI | AI stays Latin; Claude and MCP stay as they are |
| About (an estimate) | בערך | a separate word before the duration ("בערך %@ של עבודה"), never the prefix כ- |
| Habit, check-in, streak, milestone, goal | הרגל, סימון, רצף, אבן דרך, יעד | סימון is also the check-in action |
| Waits on, dependency | ממתינה ל, תלות | |
| Reminder, recurrence | תזכורת, חזרה | |
| Sync, snapshot | סנכרון, תמונת מצב | |
| Settings | הגדרות | |
| Apple features | לוח שנה, התראות, מסך הנעילה, קיצורי דרך, מצב ריכוז, ווידג׳ט | Dock and Spotlight stay Latin |

- The text avoids addressing the reader in a gendered form. Buttons, menu items,
  and intent titles are verbal nouns ("הוספה", "מחיקה", "הוספה ללוח השנה"); a
  question is an infinitive ("למחוק את הרשימה "%@"?"); an instruction is
  impersonal ("יש להפעיל מחדש את Lorvex", "לוחצים על ⌘N"); a confirmation is a
  past tense that agrees with the noun ("המשימה "%@" הושלמה."); and a second
  person form is one that the unpointed spelling gives both genders ("שבחרת",
  "שלך"). First-person past forms in sample content ("סקרתי") read the same for
  every speaker. Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are
  infinitives that name the app exactly once ("להוסיף משימה ל-${applicationName}").
- Hebrew is written unpointed. The geresh ׳ (U+05F3) marks an abbreviation or a
  foreign sound ("דק׳", "מס׳", "ווידג׳ט") and the gershayim ״ (U+05F4) an acronym;
  neither is the ASCII apostrophe or quotation mark.
- Product and technology names stay Latin: Lorvex, iCloud, CloudKit, Siri,
  Spotlight, Apple Watch, CarPlay, Claude, MCP, AI, and file formats such as
  JSON, CSV, ICS, and ZIP, as do iPhone, iPad, and Mac. A one-letter prefix (ל, ב,
  ה, ו, מ, ש, כ) takes a hyphen before Latin text, a digit, or a placeholder
  that always opens with a digit or Latin text: a number, a clock time, an ISO
  date, a counted phrase, or the app name ("ל-Lorvex", "ב-7 הימים הקרובים",
  "ב-%@" before a time, "ו-%2$@" before "2 אירועים"). A placeholder that can
  open with a Hebrew word takes no hyphenated prefix. That holds for a name, for
  a duration (the system writes two hours as the word שעתיים), and for a day
  line (it opens with יום). The sentence is built so that a noun or a separate
  word stands before such a placeholder ("לרשימה "%2$@"", "בערך %@ של עבודה");
  a day line takes the attached prefix ("ב%@" reads "ביום ראשון, 4 באוקטובר").
- Punctuation is ASCII: the comma, the full stop, the semicolon, and the
  question mark are the same as in English, as are the colon, the parentheses,
  and the single-character ellipsis …. The dash is the em dash — with spaces.
- Quotation marks are the straight `"`, never curly quotes or the Hebrew
  gershayim. They stand wherever the English quotes with curly quotes, and
  Lorvex's own view and button names inside a sentence are quoted the same way
  ("מתישהו").
- Hebrew locales format numbers in ASCII digits, so a fixed number in the
  catalog is a digit ("7 הימים הקרובים", "12 שעות") as it is in English, and
  counts arrive through placeholders. A count is written with its digits before
  the noun, so the gender agreement of Hebrew numerals never shows.
- An `he` plural entry carries `one` and `other` and may carry `two`, the dual,
  where the noun has one. `one` selects exactly 1 and spells the number as a
  word or leaves it out ("משימה אחת", "פעם ביום"); `two` is the dual with no
  number ("שתי משימות", "יומיים", "כל שבועיים"); `other` shows the count ("%lld
  משימות"). Verbs and adjectives agree with the form ("נבחרה משימה אחת",
  "נבחרו שתי משימות", "נבחרו %lld משימות"). A form that omits the count carries
  numbered specifiers where the string takes several values. Every form of a
  substitution carries `%arg`, except the dual, which names the count in the
  noun.
- A string that fills in several values uses positional specifiers (`%1$@`,
  `%2$lld`) wherever the Hebrew word order differs from the English, never
  concatenation in code.
- Weekday names come from the calendar ("יום שני", "יום ג׳"). The system's
  ordinal for Hebrew is the bare number, so a weekday's position in a month is
  "%2$@ מס׳ %1$@" and its position from the end "%2$@ מס׳ %1$@ מהסוף". Lists
  of names are joined by the system's list format, which attaches ו- to the last
  item.
- A paragraph takes its base direction from its first strong character, so a
  sentence that opens with a Latin name or a placeholder would lay out left to
  right and put its closing punctuation at the wrong end. A sentence is
  therefore written to open with a Hebrew word ("אפליקציית Lorvex יכולה …"), and
  what the English opens with moves behind it. Short labels, window titles,
  accessibility labels, and format names that are one Latin name ("Lorvex",
  "CSV", "JSON", "CloudKit", "Spotlight") stay as they are. No other
  bidirectional control character is written into a catalog, except one
  left-to-right isolate (U+2066 and U+2069) around the keyboard shortcut on the
  last page of the first-run wizard (`setup.done.capture.detail`).
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, and App Shortcut short titles) use shorter
  wording than a literal translation ("7 הימים הקרובים" for the menu bar panel's
  Next 7 Days switch, "סונכרן %@" for the watch's sync status). Accessibility
  labels may be longer.
- The capture parser (`LorvexCaptureParser`) reads Hebrew day, date, time,
  duration, repeat, and priority words for a user who reads Hebrew (he-IL and
  any other region), so the Hebrew capture hint gives Hebrew examples ("מחר",
  "בשעה 5 בערב", "כל יום שני", "20 דקות", "#רשימה"). Hebrew says a clock time
  with "בשעה" before the hour, so the time example carries it. Hebrew attaches
  the one-letter prepositions and the article to the word they go with
  ("בשבוע", "למחר", "השבוע"), so each pattern spells the prefixes it accepts and
  a word with any other prefix ("ומחר", "שמחר") stays unread. No past day is
  read: אתמול is no day word, and a line in the past tense or one that says
  אתמול holds no day to plan except מחר, מחרתיים, and "בעוד" with a count, which
  cannot be past. A written date is counted in the Gregorian calendar, whose
  months Hebrew writes in their own spellings (מרץ or מרס, אוקטובר); the Hebrew
  calendar is out of scope, so its months (תשרי, ניסן), digits-only dates, and
  Hebrew numerals ("י״ב") are not read. Weeks start on Monday as the app's
  weeks do, so "בשבוע הבא ביום רביעי" is the Wednesday of the week that begins
  on the coming Monday, and the weekend is Saturday and Sunday ("סוף השבוע" is
  the coming Saturday). Israel's week starts on Sunday and its weekend is
  Friday and Saturday, so the phrases that depend on which days make up the
  week ("כל יום עבודה", "בימי עבודה", a span from Sunday to Thursday with no
  "כל") stay in the title. The weekday names (ראשון, שני, שלישי) are also
  ordinary words, so they name a day after "יום" or with an attached ב ("ביום
  שני", "בשלישי"), and a number after ב is a clock time only with a colon, a
  fraction word, or a part of the day ("ב-9 בבוקר"), since "ב-5 ימים" counts
  things. דחוף is a priority word only at the end of the line or before a
  colon or a comma, since it is an ordinary adjective elsewhere. The parser
  reads the final letters (ך ם ן ף ץ) as the regular ones, every hyphen and the
  maqaf as the hyphen, and every apostrophe and double quote as the geresh and
  gershayim, so "אחה"צ", "אחה”צ", and "אחה״צ" are one word. It ignores niqqud,
  a word may carry it anywhere, and the title keeps what was typed. Hebrew
  written in Latin letters is not read. The hint's examples hold no Latin text,
  so they need no bidirectional isolate, and their digits are the ASCII ones
  Hebrew locales format numbers with.

## German conventions

The `de` catalogs are Standard German as written in Germany; de-DE, de-AT,
de-CH, and every other German locale select them, so regional vocabulary is
avoided and the spelling uses ß. They follow Apple's German usage
(Einstellungen, Kalender, Erinnerungen, Kurzbefehle) and keep one term per
concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | Aufgabe, Liste, Tag | Aufgabe and Liste are feminine, Tag masculine (plural Tags); a task's checklist is a Checkliste and its item a Checklistenpunkt |
| Inbox (the seeded list) | Eingang | shown while the list keeps its seeded name |
| Someday | Irgendwann | capitalized, and quoted where it names the view inside a sentence („Irgendwann“) |
| Due (the deadline field) | Fällig | "Fällig: %@" leads a row, so a relative word or a date never reads as a clause; Überfällig is overdue |
| Open (a task not yet done) | Offen | the status; In Bearbeitung is In Progress and Gestartet a started task |
| Blocked, cancelled, completed | Blockiert, Abgebrochen, Erledigt | Abgeschlossen is the state of a finished sync, diagnostic, or setup step, never of a task |
| Done (a button) and complete (an action) | Fertig, Erledigen | Fertig closes a sheet; Erledigen completes a task; Erledigt is the state |
| Defer and snooze | Verschieben, Ausblenden bis | Verschieben moves a task to a later day ("Auf morgen verschieben"); Ausblenden bis hides a task until a date; a reminder's snooze action is "In einer Stunde erinnern" |
| Plan (verb) | planen | |
| Schedule (the day pane) | Zeitplan | Zeiten vorschlagen proposes one; the Tagesstunden are the day hours |
| Capture (quick add) | Erfassen | |
| Review (the day and the week) | Rückblick | Tagesrückblick and Wochenrückblick; its fields are Erfolge, Hindernisse, Erkenntnisse |
| Memory | Gedächtnis | one entry is a Gedächtniseintrag |
| Assistant, AI | Assistent, KI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | Gewohnheit, Abhaken, Serie, Meilenstein | Abhaken is the check-in action, its entries are Einträge, and a habit's total is its Erledigungen |
| Depends on | Hängt ab von | an Abhängigkeit; a task Wartet auf another |
| Recurrence | Wiederholung | Wiederholen is the field; a recurring task is wiederkehrend |
| Sync, snapshot | Synchronisierung, Snapshot | uploading is Hochladen, fetching Abrufen, and a sync record a Datensatz |
| Event | Ereignis | a calendar event is a Kalenderereignis |
| App icon badge | Kennzeichen | the word Apple's German Mail uses ("Kennzeichen für ungelesene Mails"); macOS Reminders writes the loanword "Badge-Anzahl", which Lorvex does not use; the app icon is the App-Symbol |
| Apple features | Einstellungen, Kalender, Erinnerungen, Kurzbefehle, Siri, Spotlight, Fokus, Systemeinstellungen, Sperrbildschirm | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as du, never Sie. Apple's German system apps on macOS
  26 (among them Reminders, Calendar, Notes, Journal, Mail, Music, Maps, Photos,
  Home, and Find My) use du or dein in more than 4,000 strings and never address
  the reader as Sie; the 38 strings that contain a capitalized Sie use it as the
  third-person pronoun "they" or "it". Buttons, menu items, and intent titles
  are infinitives ("Aufgabe erledigen", "Löschen"); instructions are du
  imperatives ("Füge den ersten Checklistenpunkt hinzu"); an intent's
  description is a third-person statement ("Erledigt eine Lorvex-Aufgabe."); a
  confirmation after an action is a participle ("%@ erledigt."). A pronoun
  inside a sentence is lowercase ("deiner Gewohnheiten").
- Every noun is capitalized, including the nouns in a button ("Aufgabe
  erledigen") and Lorvex's own view names (Heute, Irgendwann, Kalender,
  Gedächtnis); every other word is lowercase, so a button or a menu item is not
  in title case. A compound that contains a Latin name takes a hyphen
  ("Lorvex-Aufgabe", "iCloud-Account", "Widget-Snapshot"). ä, ö, ü, and ß are
  always written out, never as ae, oe, or ue.
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with „ “ (U+201E and U+201C), never with straight quotes or « », and
  only where the English quotes ("Liste „%@“ löschen?", "Lädt „Heute“ erneut
  aus dem Snapshot"). An ellipsis is a no-break space followed by the single
  character … ("Gewohnheit löschen …"), as in Apple's German, which writes
  1,587 of its ellipses that way against 54 after a plain space. "z. B." takes
  a no-break space after "z." so it never splits across lines. The apostrophe
  is ’ and appears once, in "Los geht’s". A spaced en dash – stands for the
  English em dash (Apple's German uses 61 spaced en dashes against 8 spaced em
  dashes).
- The Return key is "Zeilenschalter", as Apple's German system apps (Calculator,
  Freeform) name it ("Aufgabe eingeben, Zeilenschalter drücken"). A clock time
  reads "um 15:00" without "Uhr", because the formatted time already carries
  the locale's form; "Uhrzeit" names a time of day.
- A point groups thousands and a comma marks decimals ("10.000", "2,5 Std.").
  The system's abbreviated durations and relative times end in a period ("30
  Min.", "2 Std.", "vor 2 Wo."), so a sentence never ends on such a
  placeholder: a word follows it ("werden etwa %2$@ frei.") or parentheses
  enclose it ("Letzter Upload (%@)."), so no sentence ends in two periods. A
  point after a numeral also marks an ordinal ("am 15."), so an example number
  in a hint sits inside parentheses ("(z. B. 50).") rather than ending a
  sentence, where "50." would read as "the fiftieth".
- `one` selects only 1, as in English, so a top-level `one` form may leave the
  number out ("Einmal pro Woche") while `other` shows it ("%lld-mal pro Woche");
  a substitution's `one` still contains `%arg`. `other` also covers 0 ("0
  Aufgaben"). A verb agrees with the form ("%lld Aufgabe wartet auf andere
  Aufgaben", "%lld Aufgaben warten auf andere Aufgaben").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation,
  because German compounds are long ("7 Tage" for the menu bar panel's Next 7
  Days switch, "Passt nicht" for Won’t fit, "+%lld mehr" for a small widget's
  overflow, "Synchronisierung" for the Cloud Sync tab). Accessibility labels may
  be longer.
- The capture parser (`LorvexCaptureParser`) reads German day, date, time,
  duration, repeat, and priority words for a user who reads German (de-DE,
  de-AT, de-CH, and any other region), so the German capture hint gives German
  examples („morgen“, „um 15 Uhr“, „jeden Montag“, „20 Min“, „#Liste“). German
  says a clock time with "um" and usually "Uhr", so the time example carries
  both. The umlauts and ß are optional: the parser reads ä, ö, ü, and ß as the
  plain letter and the digraphs ae, oe, ue, and ss as the same letters
  ("übermorgen", "uebermorgen", "ubermorgen"), and the title keeps the letters
  that were typed. German counts a half hour toward the next hour, so "halb
  vier" is 3:30, "viertel nach drei" is 3:15, and "Viertel vor vier" is 3:45;
  "viertel vier", "dreiviertel vier", "fünf nach drei", and "zehn vor vier" are
  times only after "um", since without it they could be words of a title. An
  hour spelled as a word after "um" or "gegen" ("um drei", "gegen vier Uhr") is
  a time, and a bare hour counts only before a word that can follow a time, so
  "um 3 Kuchen" and "Preis um 5 erhöhen" stay in the title. An
  hour from 1 to 6 with no part of the day is in the afternoon ("um 3 Uhr" is
  3 PM) unless it is written with a zero ("06:30"), a part of the day sets the
  hour ("morgens" the morning, "nachmittags" the afternoon, "abends" the
  evening), and "nachts" runs past midnight, so "um 2 Uhr nachts" is 02:00 on
  the next day. An hour count written with h follows the same split as the
  other languages that write it: "15h" and "um 10h" are clock times, "2h" and
  "1h30" are lengths, and "9h" to "12h" alone could be either, so they stay in
  the title. The weeks start on Monday as the app's weeks do, and the weekend is
  Saturday and Sunday ("am Wochenende" is the coming Saturday). A weekday name
  alone or after "am" is the coming one, "diesen Freitag" is this week's, and
  "nächsten Freitag" is next week's. The abbreviations Mo, Di, Mi, Do, Fr, Sa,
  and So are ordinary words too ("so", "do"), so they name a day only after a
  word that points at it ("am Mo", "von Mo bis Mi", "jeden Mo"). No past day is
  read: "gestern", "vorgestern", and "letzten Montag" stay in the title, and so
  does the capitalized noun "Morgen" (the morning) except at the start of the
  line or before a part of the day ("Morgen früh"). "Bis" names a deadline
  ("bis Freitag", "bis zum 15. Oktober") but is also the "to" of a range, so it
  joins two days only after "vom" or "von", or after a first day that has its
  ordinal dot ("3. bis 5. Mai"). A clock time that names a deadline ("bis 17
  Uhr", "vor 17 Uhr", "nach 17 Uhr") stays in the title, while the day before it
  is the due day. "Dringend" and "wichtig" are priority words only at the end of
  the line or before a colon or a comma, since they are ordinary adjectives
  elsewhere.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are what a person says
  to the assistant, so they are du imperatives that name the app exactly once
  and leave it undeclined ("Füge eine Aufgabe zu ${applicationName} hinzu",
  "Erledige eine Aufgabe in ${applicationName}"); a separable verb takes its
  prefix at the end ("hinzu", "vor"). Apple's own German phrases mix
  infinitives and du imperatives; the Lorvex phrases keep the du of the
  interface.

## Dutch conventions

The `nl` catalogs are Standard Dutch as written in the Netherlands; nl-NL,
nl-BE, and every other Dutch locale select them, so Flemish vocabulary is
avoided. They follow Apple's Dutch usage (Instellingen, Agenda, Herinneringen,
Opdrachten) and keep one term per concept across every catalog, so a thing
reads the same on the Mac, iPhone, watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | taak, lijst, tag | all three are de-words (plurals taken, lijsten, tags); a task's checklist is a checklist and its item a checklistonderdeel |
| Inbox (the seeded list) | Inkomend | shown while the list keeps its seeded name |
| Someday | Ooit | capitalized, and quoted where it names the view inside a sentence (‘Ooit’) |
| Due (the deadline field) | Vervaldatum | "Vervaldatum: %@" leads a row; Verlopen is overdue |
| Open (a task not yet done) | Open | the status; Bezig is In Progress and Gestart a started task |
| Blocked, cancelled, completed | Geblokkeerd, Geannuleerd, Voltooid | |
| Done (a button) and complete (an action) | Gereed, Voltooi | Gereed closes a sheet; Voltooi completes a task; Voltooid is the state |
| Defer and snooze | Stel uit, Verberg tot | Stel uit moves a task to a later day ("Verplaats naar morgen" is the Move to Tomorrow button); Verberg tot hides a task until a date; a reminder's snooze action is "Herinner me over 1 uur" |
| Plan (verb) | plannen | |
| Schedule (the day pane) | Planning | Stel tijden voor proposes one; the Daguren are the day hours |
| Capture (quick add) | Vastleggen | |
| Review (the day and the week) | Terugblik | dagterugblik and weekterugblik; its fields are Successen, Obstakels, Inzichten |
| Memory | Geheugen | het-word; one entry is a geheugenitem |
| Assistant, AI | assistent, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | gewoonte, afvinken, reeks, mijlpaal | plural gewoontes; Vink af is the check-in action |
| Depends on | Hangt af van | an afhankelijkheid; a task Wacht op another |
| Recurrence | herhaling | Herhaal is the field; a recurring task is terugkerend |
| Sync, snapshot | synchronisatie, snapshot | uploading is uploaden, fetching ophalen, and a sync record a record |
| Event | activiteit | the word Apple's Agenda app uses |
| App icon badge | Badge | Apple's Reminders writes "aantal badges"; the app icon is the appsymbool, as in Apple's Mail, Music, and TV |
| Agenda (the mobile list mode) | Overzicht | Agenda is Apple's name for the Calendar app, so Lorvex's own Agenda mode takes another word |
| Apple features | Instellingen, Agenda, Herinneringen, Opdrachten, Siri, Spotlight, focus, Systeeminstellingen, toegangsscherm | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The reader is addressed as je and jouw, never u. Apple's Dutch system apps on
  macOS 26 (among them Reminders, Calendar, Notes, Journal, Mail, Music, Maps,
  Photos, Home, and Find My) use je, jij, or jouw in about 4,500 strings and
  never address the reader as u or uw; the lone "u" in its tables is a
  format-specifier key or the abbreviation of "uur". Buttons and menu items are
  singular imperatives ("Voeg toe", "Verwijder", "Wijzig"), and so are intent
  titles ("Voltooi Lorvex-taak") and instructions ("Voeg een taak toe en druk op
  Return"); a confirmation question is an infinitive ("Lijst ‘%@’
  verwijderen?"); an intent's description is a third-person statement
  ("Voltooit een Lorvex-taak."); a confirmation after an action is a participle
  ("%@ voltooid.").
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers, and no noun takes a capital. Weekday and month names
  come from the calendar in lowercase. Only proper names, Apple's feature names,
  and Lorvex's own view names inside a sentence (Vandaag, Ooit, Agenda) take a
  capital. A Dutch compound is one word, and a Latin name joins the Dutch noun
  with a hyphen ("Lorvex-taak", "iCloud-account", "Widget-snapshot",
  "Agenda-activiteit").
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with ‘ ’, never with « » or double quotes, and only where the English
  quotes ("Lijst ‘%@’ verwijderen?"). Apple's Dutch writes the straight single
  quote in 811 of its strings around a placeholder; Lorvex writes the
  typographic form so every quotation mark and the apostrophe ’ ("agenda’s")
  are curly. An ellipsis is the single character … attached to the word, as in
  English ("Verwijder gewoonte…"). A spaced en dash – stands for the
  English em dash, the standard Dutch dash (Apple's Dutch uses 25 spaced en
  dashes against 19 spaced em dashes).
- The Return key is "Return", as in Apple's Dutch system apps ("Voeg een taak
  toe en druk op Return"). A clock time reads "om 17:00".
- A point groups thousands and a comma marks decimals ("10.000", "2,5 uur").
  The system writes a duration as "1 uur, 30 min" and a relative time as "5
  min. geleden", so a sentence may end on either.
- `one` selects only 1, as in English, so a top-level `one` form may leave the
  number out ("Eén keer per week") while `other` shows it ("%lld keer per
  week"); a substitution's `one` still contains `%arg`. `other` also covers 0.
  A verb agrees with the form ("%lld taak wacht op andere taken", "%lld taken
  wachten op andere taken"), and a counted noun that does not vary stays
  alike in both forms ("%1$@ is %2$lld keer voltooid.").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("7 dagen" for the menu bar panel's Next 7 Days switch, "Past niet" for
  Won’t fit, "+%lld meer" for a small widget's overflow). Accessibility labels
  may be longer.
- The capture parser (`LorvexCaptureParser`) reads Dutch day, date, time,
  duration, repeat, and priority words for a user who reads Dutch (nl-NL, nl-BE,
  and any other region), so the Dutch capture hint gives Dutch examples
  (‘morgen’, ‘om 15:00’, ‘elke maandag’, ‘20 min’, ‘#lijst’). Dutch says a clock
  time with "om" and "uur" or a colon, so the time example carries "om". Accents
  are optional: the parser reads é, ë, ï, and ó as the plain letter ("één" and
  "een", "vóór" and "voor", "tweeënhalf" and "tweeenhalf"), and the title keeps
  the letters that were typed. Dutch counts a half hour toward the next hour, so
  "half vier" is 3:30, "kwart over drie" is 3:15, and "kwart voor vier" is 3:45;
  "tien over drie" and "vijf voor half vier" are times only after "om", and "half
  een" needs a word before it, since without one they could be words of a title.
  A count of hours with "uur" is a length when it stands alone ("rapport 2 uur")
  and a clock time after "om", a day, a date, or a part of the day ("om 3 uur",
  "morgen 3 uur", "'s avonds 8 uur"); "3 uur lang" is always a length, and a
  bare hour counts as a time only before a word that can follow one, so "om 3
  koekjes" and "om 5 verhogen" stay in the title. An hour from 1 to 6 with no
  part of the day is in the afternoon ("om 3 uur" is 3 PM) unless it is written
  with a zero ("06:00"), a part of the day sets the hour ("'s ochtends" the
  morning, "'s middags" the afternoon, "'s avonds" the evening), and "'s nachts"
  runs past midnight, so "om 2 uur 's nachts" is 02:00 on the next day. Dutch
  writes hours with "uur" or "u", so "15u" is a clock time and "2h" is a length
  as in English. The weeks start on Monday as the app's weeks do, and the
  weekend is Saturday and Sunday ("in het weekend" is the coming Saturday). A
  weekday name alone or after "op" is the coming one, "deze vrijdag" is this
  week's, and "volgende vrijdag" is next week's. The abbreviations ma, di, wo,
  do, vr, za, and zo are ordinary words too ("zo", "do"), so they name a day
  only after a word that points at it ("op ma", "van ma tot wo", "elke ma"). No
  past day is read: "gisteren", "eergisteren", "vorige maandag", and "afgelopen
  vrijdag" stay in the title. "Tot" names a deadline ("tot vrijdag") but is also
  the "to" of a range, so it joins two days only after "van", while "t/m" and
  "tot en met" need no "van". A clock time that names a deadline ("tot 17 uur",
  "voor 17:00", "na 18 uur") stays in the title, while the day before it is the
  due day. The adverbs "dagelijks" and "wekelijks" repeat a task only at the end
  of the line, or at its start before a colon or a comma, since they are
  adjectives before a noun ("Wekelijks overleg"), and "dringend" and
  "belangrijk" are priority words in the same two places for the same reason.
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are singular
  imperatives that name the app exactly once ("Voeg een taak toe aan
  ${applicationName}"). The phrase that opens the app reads "Open de app
  ${applicationName}": the bare imperative "Open ${applicationName}" is the
  English phrase letter for letter, which `verify_localization_catalog.py`
  rejects as an untranslated phrase.

## Romanian conventions

The `ro` catalogs are Romanian as written in Romania; ro-RO, ro-MD, and every
other Romanian locale select them. They follow Apple's Romanian usage
(Configurări, Calendar, Mementouri, Scurtături) and keep one term per concept
across every catalog, so a thing reads the same on the Mac, iPhone, watch,
widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | sarcină, listă, tag | sarcină and listă are feminine (plurals sarcini, liste), tag neuter (plural taguri); a task's checklist is a listă de control and its item an element |
| Inbox (the seeded list) | Primite | shown while the list keeps its seeded name |
| Someday | Cândva | capitalized, and quoted where it names the view inside a sentence („Cândva”) |
| Due (the deadline field) | Scadență | "Scadență: %@" leads a row; Restantă (Restante in the plural) is overdue |
| Open (a task not yet done) | De făcut | the status; În curs is In Progress and Începută a started task; the lists scope that English calls Open reads Active |
| Blocked, cancelled, completed | Blocată, Anulată, Finalizată | |
| Done (a button) and complete (an action) | Gata, Finalizați | Gata closes a sheet; Finalizați completes a task (Finalizare in an intent title); Finalizată is the state |
| Defer and snooze | Amânați, Ascundeți până la | Amânați moves a task to a later day ("Mutați pe mâine" is the Move to Tomorrow button); Ascundeți până la hides a task until a date; a reminder's snooze action is "Reamintire peste o oră" |
| Plan (verb) | planifica | |
| Schedule (the day pane) | Program | Sugerați ore proposes one; Orele zilei are the day hours |
| Capture (quick add) | Adăugare | |
| Review (the day and the week) | Recapitulare | recapitulare zilnică and săptămânală; its fields are Realizări, Obstacole, Concluzii |
| Memory | Memorie | one entry is an înregistrare |
| Assistant, AI | asistent, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | obicei, bifare, serie, jalon | plural obiceiuri; Bifați is the check-in action |
| Reminder | memento | plural mementouri |
| Depends on | Depinde de | a dependență; a task Așteaptă another |
| Recurrence | repetare | Repetare is the field; one occurrence of a repeat is an apariție |
| Sync, snapshot | sincronizare, instantaneu | uploading is încărcare, fetching preluare |
| Event | eveniment | |
| App icon badge | Insignă | Apple's Reminders writes "contor de insigne"; the app icon is the pictogramă |
| Apple features | Configurări, Calendar, Mementouri, Scurtături, Siri, Spotlight, Concentrare, Configurări sistem, ecranul de blocare | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP |

- The interface addresses the reader in the polite plural, and the Siri phrases
  use the informal singular. Apple's Romanian system apps on macOS 26 (among
  them Reminders, Calendar, Notes, Journal, Shortcuts, Mail, Music, Maps, Photos,
  Home, and Find My) use polite-plural verb forms and vă in about 2,100 strings
  against about 60 singular forms ("Faceți clic", "Creați", "puteți"). Buttons
  and menu items are polite-plural imperatives ("Ștergeți", "Adăugați o
  sarcină"), and so are instructions ("Atingeți ＋"). App Intent titles and
  short titles are verbal nouns ("Finalizare sarcină Lorvex"), as in Apple's
  Shortcuts; an intent's description is a third-person statement ("Finalizează
  o sarcină Lorvex."); a confirmation names the result with "a fost" ("Sarcina
  %@ a fost finalizată."). The abbreviation dvs. appears only where a possessive
  or a pronoun cannot be dropped (the habit reminder, the Memory subtitle, and
  the notices that Lorvex data was deleted from iCloud); everywhere else the
  verb ending or the clitic vă carries the address.
- Text is in sentence case everywhere: window titles, buttons, menu items, tabs,
  and section headers. Weekday and month names come from the calendar in
  lowercase. Only proper names, Apple's feature names, and Lorvex's own view
  names (Astăzi, Mâine, Cândva) take a capital, and a view name inside a
  sentence is quoted („Astăzi”).
- The diacritics are the comma-below ș and ț and the letters ă, â, and î; the
  cedilla forms ş and ţ appear in no string. â stands inside a word and î at its
  start or end, and î stays after a prefix ("reîncărcați").
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with „ ” (U+201E and U+201D), never with straight quotes or « », and
  only where the English quotes ("Ștergeți lista „%@”?"). An ellipsis is the
  single character … attached to the word, as in English ("Ștergeți
  obiceiul…"). A spaced en dash – stands for the English em dash (Apple's
  Romanian uses 54 spaced en dashes against 6 spaced em dashes). Product names
  stay Latin and Lorvex is not declined ("în Lorvex", "sarcină Lorvex", "Tagul
  Lorvex"), while an Apple device name takes its definite article after a
  hyphen ("iPhone-ul asociat").
- The Return key is "Retur", as Apple's Romanian system apps (Calculator, Notes,
  Freeform) name it ("apăsați Retur"). A clock time reads "la 17:00".
- A point groups thousands and a comma marks decimals ("10.000", "2,5 ore").
  The system's abbreviated durations and relative times end in a period ("30
  min.", "2 ore 30 min.", "-2 săpt.") and the relative ones carry a minus sign,
  so a sentence never ends on such a placeholder: a word follows it
  ("aproximativ %@ de muncă.") or parentheses enclose it ("Ultima încărcare
  (%@).").
- `one` selects only 1, `few` selects 0, 2 to 19, 101 to 119, and so on, and a
  fraction, and `other` selects 20 to 100, 120 to 200, and so on. A plural
  entry carries all three, and the `other` form puts "de" between a count and
  its noun ("1 sarcină", "2 sarcini", "20 de sarcini"). A top-level `one` form
  may leave the number out ("O dată pe săptămână", beside "De %lld ori pe
  săptămână" for `few` and "De %lld de ori pe săptămână" for `other`); a
  substitution's `one` still contains `%arg`. A verb or participle agrees with
  the form ("A fost finalizată %arg sarcină", "Au fost finalizate %arg
  sarcini", "Au fost finalizate %arg de sarcini").
- A status word agrees with what it describes: Blocată, Anulată, Finalizată, and
  Începută for a task; the neuter obicei takes the feminine plural ("obiceiuri
  finalizate").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("7 zile" for the menu bar panel's Next 7 Days switch, "Nu încape" for Won’t
  fit, "+%lld în plus" for a small widget's overflow). Accessibility labels may
  be longer.
- The capture parser (`LorvexCaptureParser`) reads Romanian day, date, time,
  duration, repeat, and priority words for a user who reads Romanian (ro-RO,
  ro-MD, and any other region), so the Romanian capture hint gives Romanian
  examples („mâine”, „la 15:00”, „în fiecare luni”, „20 min”, „#listă”).
  Romanian says a clock time with "la" or "ora", so the time example carries
  "la". The diacritics are optional: the parser reads ă, â, and î as the plain
  letter and both the comma-below forms (ș, ț) and the cedilla forms (ş, ţ) as
  s and t ("mâine" and "maine", "marți", "marţi", and "marti"), and the title
  keeps the letters that were typed. A letter typed as a base letter and a
  separate combining accent is left as it is, so a detail word typed that way
  is not read. Romanian adds to the hour it names, where German and Dutch
  count a half hour toward the next one, so "la 3 și jumătate" is 3:30, "la 3
  și un sfert" is 3:15, "la 3 fără un sfert" is 2:45, and "la 3 fără 10" is
  2:50. These spoken forms need "la" or "ora" before the hour,
  since "3 și jumătate" alone is as often an amount ("3 și jumătate kg"), and
  minutes with a unit word ("la 3 și 10 minute") stay in the title whole. A
  bare hour after "la" is a time only where the line goes on with nothing or a
  word that can follow a time ("la 3 cu Ana"), so "la 3 prieteni" and
  "Cumpără pâine la 3 lei" stay in the title. An hour from 1 to 6 with no part
  of the day is in the afternoon ("la ora 3" is 3 PM) unless it is written
  with a zero ("la 03:00"), a part of the day sets the hour ("dimineața" the
  morning, "după-amiaza" the afternoon, "seara" the evening), "noaptea" runs
  past midnight ("la 2 noaptea" is 02:00 on the next day, and "la 12 noaptea"
  and "la miezul nopții" are 00:00 on the next day), and "la prânz" is noon.
  Romanian does not write a clock time with the letter h, so "15h" and "2h"
  are lengths, as in English alone. An amount after "peste", "în", "după", or
  "acum" ("peste 2 ore", "în 10 minute") is a moment, not a length, so it
  stays in the title.
  The weeks start on Monday as the app's weeks do, and the weekend is Saturday
  and Sunday ("în weekend" is the coming Saturday and "weekendul viitor" the
  one after). A weekday name alone or after "la", "pe", "în", or "de" is the
  coming one, "marți asta" is this week's, and "luni viitoare" is next week's.
  "Luni" is also the plural of "lună", so after a count ("peste 3 luni", "două
  luni") or before "de zile" it stays in the title, and "mai" is the month only
  where no adverb of comparison follows it ("3 mai", but "3 mai multe" stays).
  The definite forms "lunea", "martea", "miercurea", "joia", and "vinerea" name
  a day or, in a list, a repeat ("lunea și joia"). "Sâmbăta" and "duminica"
  read like "sâmbătă" and "duminică" once the diacritics are left out, so the
  pair "sâmbătă și duminică" and the phrase "azi noapte", which names the night
  just gone as often as the one to come, are left unread. No past day is read:
  "ieri", "alaltăieri", "luni trecută", and "weekendul trecut" stay in the
  title. "Până" names a deadline ("până vineri") but is also the "to" of a
  range, so it joins two days only after "de la", "din", or "în perioada", or
  after a first date that has its own month ("3 mai până la 5 mai"). "Pentru"
  before a day is a deadline too ("tema pentru luni"), and "în 3 zile" is left
  unread since it may mean within three days, while "peste 3 zile" is a day. A
  clock time that names a deadline ("până la ora 17", "înainte de 17:00",
  "după ora 18") stays in the title, while the day before it is the due day.
  The adverbs "zilnic", "săptămânal", and "lunar" repeat a task only at the end
  of the line, or at its start before a colon or a comma, since they are
  adjectives before a noun ("ședință săptămânală"), and "urgent" and
  "important" are priority words in the same two places for the same reason.
  The feminine and plural forms ("urgentă", "importante") stay in the title,
  since without diacritics they are the nouns "urgență" and "importanță".
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are what a person says
  to the assistant, so they are informal singular imperatives that name the app
  exactly once and leave it undeclined ("Adaugă o sarcină în
  ${applicationName}", "Afișează sarcinile din ${applicationName}"), unlike the
  polite plural of the interface. Apple's own Romanian phrases use both forms
  ("Scrieți o nouă intrare în jurnal în ${applicationName}", "Scrie în
  ${applicationName}"); the singular is the shorter one to say aloud.

## Indonesian conventions

The `id` catalogs are Indonesian as written in Indonesia; id-ID and every
other Indonesian locale select them. They follow Apple's Indonesian usage
(Pengaturan, Kalender, Pengingat, Pintasan, Fokus) and keep one term per
concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts. Indonesian and Malay share much of their
vocabulary but not their word choices, so each catalog keeps to its own
variety: the Indonesian one writes hapus, tanggal, perangkat, and jadwal where
Malay writes padam, tarikh, peranti, and jadual.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | tugas, daftar, label | Apple's Notes and Freeform call a tag Label; a task's checklist is a daftar centang and its item an item |
| Inbox (the seeded list) | Inbox | Apple's Calendar keeps the English word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | Hari Ini, Besok, Kemarin | the navigation button and the date chips; inside a sentence they are lowercase ("hari ini", "besok") |
| Someday | Suatu Hari | |
| Due (the deadline field) | Jatuh Tempo | "jatuh tempo" inside a sentence; Terlewat is overdue |
| Open (a task not yet done) | Belum Selesai | the status and the filter; Sedang Dikerjakan is In Progress and Dimulai a started task |
| Blocked, cancelled, completed | Diblokir, Dibatalkan, Selesai | |
| Done (a button) and complete (an action) | Selesai, Selesaikan | Selesai closes a sheet and is the Completed state; Selesaikan completes a task |
| Defer and snooze | Tunda | one word for both, the one Apple's Clock, Home, and Maps write for snooze; "Tunda ke Besok" moves a task to a later day and "Tunda 1 Jam" snoozes a reminder |
| Plan (verb) | rencanakan | direncanakan is planned, and a task's planned date is its tanggal rencana |
| Schedule (the day pane) | Jadwal | Sarankan Waktu proposes times; Jam Aktif are the day hours |
| Capture (quick add) | Catat | |
| Review (the day and the week) | Tinjauan | Tinjauan Harian and Tinjauan Mingguan; its fields are Pencapaian, Hambatan, Pelajaran |
| Memory | Memori | one entry is an entri memori |
| Assistant, AI | asisten, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | kebiasaan, check-in, rekor, tonggak | rekor is the word Apple's Journal uses for a streak; a habit's goal is its Target |
| Reminder | pengingat | |
| Dependency | Dependensi | a task Menunggu another |
| Recurrence | pengulangan | Ulangi is the field and berulang is recurring |
| Sync, snapshot | penyelarasan, snapshot | selaraskan is the verb, as in Apple's Music and Freeform; uploading is unggah, fetching unduh, and a sync record a rekaman |
| Event | acara | the word Apple's Calendar uses |
| App icon badge | lencana | Apple's Mail writes tanda for its unread badge, a word that also means any mark, so the badge on an app icon takes the more specific one |
| Agenda (the mobile list mode) | Agenda | |
| Apple features | Pengaturan, Kalender, Pengingat, Pintasan, Fokus, Pengaturan Sistem, layar kunci | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed as Anda, with a capital A, and never as kamu.
  Apple's Indonesian system apps and frameworks on macOS 26 (among them Music,
  TV, Find My, Home, Maps, Podcasts, Photos, and Journal) use Anda in 4,818
  strings and never kamu, engkau, or aku. Lorvex leaves the pronoun out
  wherever the sentence carries the address ("Pastikan Lorvex memiliki akses
  kalender di Pengaturan Sistem.") and writes Anda only where a possessive or
  a contrast needs it ("Hari ini milik Anda."). Buttons and menu items are
  root-form verbs ("Hapus Kebiasaan…"), and so are intent titles ("Selesaikan
  Tugas Lorvex", "Ubah Nama Label Lorvex"); instructions are imperatives
  ("Ketuk ＋ untuk mencatat tugas pertama"); a confirmation question names the
  object ("Hapus daftar “%@”?"); an intent's description is a statement that
  opens with an me- verb ("Menyelesaikan tugas Lorvex."); and a confirmation
  after an action is a passive with di- ("%@ diselesaikan.").
- Buttons, menu items, tabs, section and field labels, and intent titles are
  in Title Case wherever the English entry is, with the function words dan,
  atau, di, ke, dari, untuk, yang, dengan, pada, dalam, sebagai, oleh, and
  hingga in lowercase mid-title ("Pindahkan ke Besok"), as Apple's Indonesian
  writes them ("Pengingat Baru", "Catatan Cepat", "Tindakan Cepat"). A
  sentence, a caption, and an entry the English writes in lowercase are in
  sentence case. Weekday and month names come from the calendar, capitalized
  (Senin, Januari).
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with “ ” as in English ("Hapus daftar “%@”?"); Apple's Indonesian
  writes curly double quotes in 1,303 strings and straight ones in 57. An
  ellipsis is the single character … attached to the word (1,473 strings
  against 33 with three dots in Apple's), and a spaced en dash – stands for
  the English em dash, the form Apple's Indonesian uses more often (29
  strings against 24 with a spaced em dash). The Return key is "Return"
  ("tekan Return", as in Apple's Calculator and Freeform).
- A third-party app is "app" ("app kalender lain"; 376 strings in Apple's
  Indonesian against 62 with aplikasi), a file is "file" (718 strings, none
  with berkas), and an email is "email" (226 strings, none with surel).
- A point groups thousands and a comma marks decimals ("10.000", "2,5 jam").
  The system writes a clock time with a point ("17.05"), a duration as "1 j,
  30 mnt", and a relative time as "5 mnt lalu", so a sentence takes such a
  value as a `%@` argument and may end on it. An ordinal is "ke-1", so
  `recurrence.weekday.nth` ("%2$@ %1$@") reads "Sen ke-1" for the first
  Monday, and a list of names reads "A, B, dan C" (narrow "A, B, C").
- Indonesian has the single plural category `other`, so a plural entry is one
  plain string that shows the number wherever the English forms show it
  ("%lld tugas", "%lld kali sehari"), and a noun after a number is not
  reduplicated ("3 tugas", never "3 tugas-tugas"). An entry whose English forms
  leave the number out (the "kali selesai" under the goal ring's large number)
  is a substitution with only `other`.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("Tidak muat" for Won’t fit, "+%lld lainnya" for a small widget's overflow,
  "sisa" as the caption under the remaining-tasks ring, "Item baru" in the
  checklist field of the Mac inspector). Accessibility labels may be longer.
- The capture parser (`LorvexCaptureParser`) has no Indonesian vocabulary: it
  reads English and Chinese words wherever the interface language is
  Indonesian. The capture hint (`capture.footer.words`) therefore gives
  English examples and says so ("Kata bahasa Inggris seperti “tomorrow”,
  “3pm”, “every Monday”, “20 min”, atau “#list” mengisi detail tugas.").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are imperatives that
  name the app exactly once, after "di" ("Catat tugas di
  ${applicationName}") or after "ke" where the English says to ("Tambahkan
  tugas ke ${applicationName}"). The phrase that opens the app reads "Buka
  ${applicationName}".

## Malay conventions

The `ms` catalogs are Malay as written in Malaysia in Rumi script; ms-MY,
ms-SG, ms-BN, and every other Malay locale select them. They follow Apple's
Malay usage (Seting, Kalendar, Peringatan, Pintasan, Fokus) and keep one term
per concept across every catalog, so a thing reads the same on the Mac,
iPhone, watch, widgets, and in Shortcuts. Malay and Indonesian share much of
their vocabulary but not their word choices, so each catalog keeps to its own
variety: the Malay one writes padam, tarikh, peranti, and jadual where
Indonesian writes hapus, tanggal, perangkat, and jadwal.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | tugas, senarai, tag | a task's checklist is a senarai semak, as in Apple's Notes, and its item an item |
| Inbox (the seeded list) | Peti Masuk | Apple's Calendar and Mail word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | Hari Ini, Esok, Semalam | the navigation button and the date chips; inside a sentence they are lowercase ("hari ini", "esok") |
| Someday | Suatu Hari | |
| Due (the deadline field) | Tarikh Jangka | Apple's Reminders word, "tarikh jangka" inside a sentence; Lewat is overdue |
| Open (a task not yet done) | Belum Selesai | the status and the filter; Sedang Berjalan is In Progress and Dimulakan a started task |
| Blocked, cancelled, completed | Disekat, Dibatalkan, Selesai | |
| Done (a button) and complete (an action) | Selesai, Selesaikan | Selesai closes a sheet and is the Completed state; Selesaikan completes a task |
| Defer and snooze | Tangguhkan, Tangguh | Tangguhkan moves a task to a later day ("Tangguhkan hingga Esok"); Tangguh snoozes a reminder ("Tangguh 1 Jam"), because Apple's Clock writes Tidur for snooze, which here would read as sleep |
| Plan (verb) | rancang | dirancang is planned, and a task's planned date is its tarikh rancangan |
| Schedule (the day pane) | Jadual | Cadangkan Masa proposes times; Jam Aktif are the day hours |
| Capture (quick add) | Catat | |
| Review (the day and the week) | Semakan | Semakan Harian and Semakan Mingguan; its fields are Kejayaan, Halangan, Pengajaran |
| Memory | Memori | one entry is an entri memori |
| Assistant, AI | pembantu AI | always with AI, since pembantu alone names any helper; Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | tabiat, check-in, rentetan, tonggak | tabiat is the word Apple's Journal uses for a habit ("Bina Tabiat"); the same app writes pencapaian berterusan for a streak, which is too long for a stat tile; a habit's goal is its Matlamat |
| Reminder | peringatan | Apple's Reminders word |
| Dependency | Kebergantungan | a task Menunggu another |
| Recurrence | perulangan | Ulang is the field and berulang is recurring |
| Sync, snapshot | penyelarasan, syot kilat | selaraskan is the verb; uploading is muat naik, fetching muat turun, and a sync record a rekod |
| Event | peristiwa | the word Apple's Calendar uses |
| App icon badge | lencana | Apple's Mail and Reminders word |
| Agenda (the mobile list mode) | Agenda | |
| Apple features | Seting, Kalendar, Peringatan, Pintasan, Fokus, Seting Sistem, skrin kunci | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed as anda, in lowercase inside a sentence and with a
  capital only where a sentence starts ("Anda sudah bersedia."). Apple's Malay
  system apps and frameworks on macOS 26 (among them Music, TV, Find My, Home,
  Maps, Podcasts, Photos, and Journal) use anda in 4,280 strings and Anda in
  998, and never awak or kamu. Lorvex leaves the pronoun out wherever the
  sentence carries the address and writes anda where a possessive needs it
  ("Tiba masanya untuk tabiat anda"). Buttons and menu items are root-form
  verbs ("Padam Tabiat…"), and so are intent titles ("Selesaikan Tugas
  Lorvex", "Namakan Semula Tag Lorvex"); instructions are imperatives
  ("Ketik ＋ untuk mencatat tugas pertama"), and a request opens with Sila,
  Apple's Malay for please (293 strings: "Sila cuba lagi."); a confirmation
  question names the object ("Padam senarai “%@”?"); an intent's description is
  a statement that opens with a men- verb ("Menyelesaikan tugas Lorvex."); and
  a confirmation after an action is a passive with di- ("%@ diselesaikan.").
- Buttons, menu items, tabs, section and field labels, and intent titles are
  in Title Case wherever the English entry is, with the function words dan,
  atau, di, ke, dari, daripada, untuk, yang, dengan, pada, dalam, sebagai,
  oleh, hingga, and kepada in lowercase mid-title, as Apple's Malay writes
  them ("Peringatan Baharu", "Nota Cepat", "Tindakan Cepat"). A sentence, a
  caption, and an entry the English writes in lowercase are in sentence case.
  Weekday and month names come from the calendar, capitalized (Isnin,
  Januari).
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with “ ” as in English ("Padam senarai “%@”?"); Apple's Malay writes
  curly double quotes in 1,321 strings and straight ones in 41. An ellipsis
  is the single character … attached to the word (1,474 strings against 32
  with three dots in Apple's), and a spaced en dash – stands for the English
  em dash, the form Apple's Malay uses more often (30 strings against 23 with
  a spaced em dash). The Return key is "Return" ("tekan Return", as in
  Apple's Calculator and Freeform).
- Malay spells words as Apple's Malay does: "bahasa Inggeris", "app" for a
  third-party app (376 strings against 62 with aplikasi), "fail" for a file
  (718 strings, 5 with file), "e-mel" for email (145 strings, none with
  email), "peranti" for a device, "Seting" for settings (528 strings, none
  with Tetapan), and "Tambah" for add in buttons, prompts, and sentences alike
  (771 strings against 4 with Tambahkan).
- A comma groups thousands and a point marks decimals ("10,000", "2.5 jam"),
  the reverse of Indonesian. The system writes a clock time in 12 hours with
  PG and PTG ("5:05 PTG"), a duration as "1 j dan 30 min", and a relative time
  as "5 min lalu", so a sentence takes such a value as a `%@` argument and may
  end on it. The ordinal of 1 is "No. 1" and of every later number "ke-2",
  "ke-3", so `recurrence.weekday.nth` ("%2$@ %1$@") reads "Isn No. 1" for the
  first Monday and "Isn ke-2" for the second, and a list of names reads "A, B
  dan C" with no comma before dan (narrow "A, B, C").
- Malay has the single plural category `other`, so a plural entry is one plain
  string that shows the number wherever the English forms show it ("%lld
  tugas", "%lld kali sehari"), and a noun after a number is not reduplicated
  ("3 tugas", never "3 tugas-tugas"). An entry whose English forms leave the
  number out (the "kali selesai" under the goal ring's large number) is a
  substitution with only `other`.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("Tidak muat" for Won’t fit, "+%lld lagi" for a small widget's overflow,
  "berbaki" as the caption under the remaining-tasks ring, "Item baharu" in
  the checklist field of the Mac inspector). Accessibility labels may be
  longer.
- The capture parser (`LorvexCaptureParser`) has no Malay vocabulary: it reads
  English and Chinese words wherever the interface language is Malay. The
  capture hint (`capture.footer.words`) therefore gives English examples and
  says so ("Perkataan bahasa Inggeris seperti “tomorrow”, “3pm”, “every
  Monday”, “20 min” atau “#list” melengkapkan butiran tugas.").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are imperatives that
  name the app exactly once, after "dalam" ("Catat tugas dalam
  ${applicationName}") or after "ke dalam" where the English says to ("Tambah
  tugas ke dalam ${applicationName}"). The phrase that opens the app reads
  "Buka ${applicationName}".

## Vietnamese conventions

The `vi` catalogs are Vietnamese as written in Vietnam; vi-VN and every other
Vietnamese locale select them. They follow Apple's Vietnamese usage (Cài đặt,
Lịch, Lời nhắc, Phím tắt, Tập trung) and keep one term per concept across
every catalog, so a thing reads the same on the Mac, iPhone, watch, widgets,
and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | nhiệm vụ, danh sách, thẻ | Apple's Notes and Freeform call a tag Thẻ; a task's checklist is a checklist, as in Apple's Notes, and its item a mục |
| Inbox (the seeded list) | Hộp thư đến | Apple's Calendar and Mail word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | Hôm nay, Ngày mai, Hôm qua | the navigation button and the date chips; inside a sentence they are lowercase ("hôm nay", "ngày mai") |
| Someday | Một ngày nào đó | |
| Due (the deadline field) | Đến hạn | Quá hạn is overdue |
| Open (a task not yet done) | Chưa hoàn thành | the status and the filter; Đang thực hiện is In Progress and Đã bắt đầu a started task |
| Blocked, cancelled, completed | Bị chặn, Đã hủy, Đã hoàn thành | |
| Done (a button) and complete (an action) | Xong, Hoàn thành | Xong closes a sheet; Hoàn thành completes a task; Đã hoàn thành is the state |
| Defer and snooze | Hoãn, Báo lại | Hoãn moves a task to a later day ("Hoãn đến ngày mai"); Báo lại snoozes a reminder ("Báo lại sau 1 giờ"), the word Apple's Clock, Home, and Maps use |
| Plan (verb) | lên kế hoạch | "đã lên kế hoạch" is planned, and a task's planned date is its ngày lên kế hoạch |
| Schedule (the day pane) | Lịch trình | Gợi ý giờ proposes times; Khung giờ trong ngày are the day hours |
| Capture (quick add) | Ghi nhanh | |
| Review (the day and the week) | Tổng kết | Tổng kết hàng ngày and hàng tuần; its fields are Thành tựu, Trở ngại, Bài học |
| Memory | Bộ nhớ | one entry is a mục ghi nhớ; Apple's Photos uses Kỷ niệm for its own Memories, which is a different feature |
| Assistant, AI | trợ lý, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | thói quen, điểm danh, chuỗi, cột mốc | chuỗi is the word Apple's Journal uses for a streak; a habit's goal is its mục tiêu |
| Reminder | lời nhắc | Apple's Reminders word |
| Dependency | Phụ thuộc | a task Đang chờ another |
| Recurrence | lặp lại | |
| Sync, snapshot | đồng bộ hóa, ảnh chụp nhanh | uploading is tải lên, fetching tải về, and a sync record a bản ghi; the Cloud Sync tab, section, and messages are named Đồng bộ iCloud so the label fits the Mac settings sidebar |
| Event | sự kiện | the word Apple's Calendar uses |
| App icon badge | huy hiệu | Apple's Mail writes biểu tượng for its unread badge, a word that also names the icon itself, so the badge on an app icon takes the more specific one |
| Agenda (the mobile list mode) | Lịch biểu | |
| Apple features | Cài đặt, Lịch, Lời nhắc, Phím tắt, Tập trung, Cài đặt hệ thống, màn hình khóa | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed as bạn, and never as quý khách. Apple's Vietnamese
  system apps and frameworks on macOS 26 (among them Music, TV, Find My, Home,
  Maps, Podcasts, Photos, and Journal) use bạn in 4,939 strings and never quý
  khách. Lorvex leaves the pronoun out wherever the sentence carries the
  address ("Hãy mở lại Lorvex để áp dụng ngôn ngữ mới.") and writes bạn where
  a clause needs a subject ("Bạn cũng có thể thêm hoặc sửa ghi chú."). An
  instruction opens with Hãy, which Apple's Vietnamese writes more often than
  Vui lòng (323 strings against 264). Buttons and menu items are bare verbs
  ("Thêm nhiệm vụ", "Xóa thói quen…"), and so are intent titles ("Hoàn thành
  nhiệm vụ Lorvex", "Đổi tên thẻ Lorvex") and intent descriptions ("Hoàn thành
  một nhiệm vụ Lorvex."); a confirmation after an action opens with Đã ("Đã hoàn
  thành %@."). The assistant's own briefings speak in the first person with
  tôi, and the Mac click is "Bấm" (79 strings in Apple's Vietnamese, none with
  Nhấp).
- Text is in sentence case everywhere: window titles, buttons, menu items,
  tabs, section headers, and intent titles, as in Apple's Vietnamese ("Lời
  nhắc mới", "Ghi chú nhanh", "Thêm vào Lịch"). Only proper names, Apple's
  feature names (Lịch, and Cài đặt where a sentence names the app), and
  Lorvex's own view names inside a sentence take a capital; weekday names come
  from the calendar capitalized (Thứ Hai, Chủ Nhật) and months lowercase
  ("tháng 3").
- Every Vietnamese string is NFC: each letter with its tone mark is one
  precomposed character, never a base letter followed by a combining mark. The
  tone mark sits on the first vowel of oa, oe, and uy, as in Apple's
  Vietnamese ("hóa" in 815 strings and "hoá" in none, "Hủy" and never "Huỷ"),
  so the catalogs write "đồng bộ hóa" and "thủy". Every syllable is separated
  by a space, a daily or weekly cadence is "Hàng ngày" and "Hàng tuần" (Apple
  writes Hàng in 61 strings and Hằng in none), and "Hãy" is the imperative
  marker.
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with “ ” as in English ("Xóa danh sách “%@”?"); Apple's Vietnamese
  writes curly double quotes in 1,303 strings and straight ones in 55. An
  ellipsis is the single character … attached to the word (1,475 strings
  against 32 with three dots in Apple's), and a spaced en dash – stands for
  the English em dash, the form Apple's Vietnamese uses more often (40
  strings against 15 with a spaced em dash). The Return key is "Return" ("nhấn
  Return", as in Apple's Calculator, Freeform, and Notes).
- A point groups thousands and a comma marks decimals ("10.000", "2,5 giờ").
  The system writes a clock time in 24 hours ("17:05"), a duration as "1 giờ,
  30 phút", and a relative time as "5 phút trước" or "sau 2 giờ nữa", so a
  sentence takes such a value as a `%@` argument and may end on it. Its
  ordinal is "thứ 1", which beside a short weekday name ("Thứ 2" is Monday)
  would read "Thứ 2 thứ 1", so `recurrence.weekday.nth` writes "%2$@ (lần
  %1$@)", "Thứ 2 (lần thứ 1)", and a list of names reads "A, B và C" (narrow
  "A, B, C").
- Vietnamese has the single plural category `other`, so a plural entry is one
  plain string that shows the number wherever the English forms show it
  ("%lld nhiệm vụ", "%lld lần mỗi ngày"), and a noun does not change after a
  number. An entry whose English forms leave the number out (the "lần hoàn
  thành" under the goal ring's large number) is a substitution with only
  `other`.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("Không vừa" for Won’t fit, "+%lld nữa" for a small widget's overflow,
  "%lld xong hôm nay" for the done-today count under a small widget's ring,
  "còn" as the caption under the remaining-tasks ring, "Đồng bộ iCloud" for
  the Cloud Sync tab of the Mac settings sidebar). Accessibility labels may be
  longer.
- The capture parser (`LorvexCaptureParser`) has no Vietnamese vocabulary: it
  reads English and Chinese words wherever the interface language is
  Vietnamese. The capture hint (`capture.footer.words`) therefore gives
  English examples and says so ("Các từ tiếng Anh như “tomorrow”, “3pm”,
  “every Monday”, “20 min” hoặc “#list” sẽ điền chi tiết cho nhiệm vụ.").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are imperatives that
  name the app exactly once, after "trong" ("Ghi nhanh nhiệm vụ trong
  ${applicationName}") or after "vào" where the English says to ("Thêm nhiệm
  vụ vào ${applicationName}"). The phrase that opens the app reads "Mở
  ${applicationName}".

## Turkish conventions

The `tr` catalogs are Turkish as written in Turkey; tr-TR, tr-CY, and every
other Turkish locale select them. They follow Apple's Turkish usage (Ayarlar,
Takvim, Anımsatıcılar, Kestirmeler, Odak) and keep one term per concept across
every catalog, so a thing reads the same on the Mac, iPhone, watch, widgets,
and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | görev, liste, etiket | görev is Apple's Shortcuts word for a task and Etiket Apple's Notes word for a tag; a task's checklist is a kontrol listesi, the ordinary Turkish word, where Apple's Shortcuts writes Denetim Listesi and Notes writes Yapılacaklar Listesi, which would name a second to-do list, and its item is an öğe |
| Inbox (the seeded list) | Gelen Kutusu | Apple's Shortcuts word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | Bugün, Yarın, Dün | the navigation button and the date chips; inside a sentence they are lowercase ("bugün", "yarın") |
| Someday | Bir gün | quoted inside a sentence, with a suffix straight after the closing quote ("“Bir gün”e taşı") |
| Due (the deadline field) | Son tarih | the plain word for a deadline, where Apple's Reminders writes Hedeflenen Tarih; Gecikmiş is overdue |
| Open (a task not yet done) | Açık | the status and the filter; Devam ediyor is In Progress and Başlandı a started task |
| Blocked, cancelled, completed | Engellendi, İptal edildi, Tamamlandı | |
| Done (a button) and complete (an action) | Bitti, Tamamla | Bitti closes a sheet, as in Apple's apps (587 of Apple's strings that read Done); Tamamla completes a task; Tamamlandı is the Completed state |
| Defer and snooze | Ertele | one word for both, the one Apple's Clock writes for snooze; "Yarına ertele" moves a task to a later day and "1 saat sonra anımsat" snoozes a reminder, as Apple's Mail and Reminders write "1 Saat Sonra Anımsat" |
| Plan (verb) | planla | "planlandı" is planned |
| Schedule (the day pane) | Program | Apple's Home writes Plan for a schedule, which Lorvex keeps for the verb planla |
| Capture (quick add) | Hızlı ekle | |
| Review (the day and the week) | Gözden geçirme | Günlük and Haftalık are its two modes; its fields are Başarılar, Engeller, Öğrenilenler |
| Memory | Bellek | one entry is a bellek girdisi |
| Assistant, AI | asistan, yapay zekâ | zekâ keeps its circumflex, as in Apple's Turkish; Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | alışkanlık, işaretleme, seri, kilometre taşı | seri is the word Apple's Journal uses for a streak; İşaretle logs a check-in |
| Reminder | anımsatıcı | Apple's Reminders word (1,174 strings, and none with hatırlatıcı) |
| Dependency | bağımlılık | Bağımlılıklar is the Waits on field |
| Recurrence | yineleme | Yineleme is the field, as in Apple's Calendar, and yinelenen is recurring |
| Sync, snapshot | eşzamanlama, anlık görüntü | eşzamanla is the verb, as in Apple's Music and TV (senkron appears in one string), so the toggle reads "iCloud ile eşzamanla" and the feature "iCloud eşzamanlaması" |
| Event | etkinlik | the word Apple's Calendar uses |
| App icon badge | işaret | Apple's Reminders word, "Uygulama simgesi işareti" |
| Appearance (light, dark, system) | Görünüş (Açık, Koyu, Sistem) | Görünüş names Apple's Appearance setting (41 strings, among them the Appearance pane of System Settings and its App Intents), and Açık and Koyu are its Light and Dark (28 and 27 strings); "Sistem saptanmışı" is System Default |
| Widget | araç takımı | Apple's macOS 26 word (208 strings against 3 with widget) |
| Agenda (the mobile list mode) | Ajanda | |
| Apple features | Ayarlar, Takvim, Anımsatıcılar, Kestirmeler, Odak, Sistem Ayarları, Kilitli Ekran | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed formally, in the second person plural, and never as
  sen. Apple's Turkish strings on macOS 26 (435,075 in the system apps,
  frameworks, and extensions, among them Podcasts, Home, Maps, Photos,
  Journal, and Wallet) carry a second-person-plural possessive (-ınız, -iniz,
  -unuz, -ünüz) in 24,018 strings and the pronoun siz in 1,955, against 89
  with sen, most of them in the sensitive-content warnings. An instruction is
  a polite plural imperative ("Yeni dili uygulamak için Lorvex’i yeniden
  başlatın."), the form of 14,501 of Apple's sentences of four words or more
  against 1,084 with the singular. The word lütfen appears only where the
  English says please ("Bir sorun oluştu. Lütfen yeniden deneyin."; Apple's
  Turkish has it in 2,637 strings). A button, menu item, tab, or intent title
  is the bare stem ("Ekle", "Sil", "Düzenle", "Vazgeç", "Lorvex görevini
  tamamla"), as in Apple's Turkish (Vazgeç in 2,178 strings and İptal in none,
  Sil in 1,076, Ekle in 324 and Ekleyin as a label in none). An intent's
  description is a polite plural imperative ("Bir Lorvex görevini
  tamamlayın."); a confirmation after an action is a past statement that
  puts the value after a colon ("Tamamlandı: %@."); and a confirmation
  question puts the noun after the quoted value ("“%@” listesi silinsin
  mi?").
- Text is in sentence case: window titles, buttons, menu items, tabs, section
  headers, and intent titles capitalize only the first word ("Yeni liste",
  "Hızlı ekle", "Son tarih", "Lorvex görevi ekle"). This follows the app's own
  sentence-case rule and departs from Apple's Turkish, which capitalizes each
  word of a two-word label (57,605 strings against 7,323 in sentence case,
  "Yeni Pencere"), so a Lorvex label reads lower-cased beside a system one.
  Names keep their capitals (Lorvex, Takvim, Anımsatıcılar, Gelen Kutusu), and
  weekday and month names come from the calendar capitalized (Pazartesi,
  Ocak). Turkish has a dotted and a dotless i in both cases: the capital of i
  is İ and the lowercase of I is ı, so a word that begins with the dotted
  vowel starts with İ ("İptal edildi", "İyi", "İşaretle"), as in Apple's
  Turkish (24,621 strings with İ). Search folds İ and ı to i.
- No ending ever attaches to a value that arrives at run time. A task title,
  list name, or date follows a colon at the end of the sentence ("Sil: %@",
  "Yarına ertelendi: %@.", "Lorvex’e eklendi: %@."), or it is quoted with the
  noun after it ("“%@” görevini aç", "“%@” listesi"), so the case ending or
  possessive sits on the noun. A fixed product or app name takes an
  apostrophe and the ending that follows its pronunciation (Lorvex’te,
  Lorvex’i, Lorvex’e, iCloud’a, iCloud’dan, Takvim’e, Ayarlar’ı, Kilitli
  Ekran’da, Mac’te, and with a possessive "iPhone’unuz" and "Mac’inizde").
  Apple's Turkish writes the curly apostrophe ’ in 38,573 strings and the
  straight one in 828, and "Takvim’e Ekle" for its own Add to Calendar.
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with “ ” as in English; Apple's Turkish writes curly double quotes in
  15,833 strings and straight ones in 145. An ellipsis is the single
  character … attached to the word (8,579 strings against 275 with three dots
  in Apple's), and a spaced en dash – stands for the English em dash, the
  form Apple's Turkish uses more often (227 strings against 116 with a spaced
  em dash). The Return key is "Return" with tuşu and the ending on the
  noun ("Return tuşuna basın"; 55 strings in Apple's Turkish, among them its
  Calculator's).
- Turkish spells words as Apple's Turkish does: "uygulama" for an app (7,673
  strings), "dosya" for a file (4,375), "sözcük" for a word (247 against 23
  with kelime), and "yapay zekâ" with the circumflex (43 strings, none
  without).
- A point groups thousands and a comma marks decimals ("10.000", "2,5"). The
  system writes a clock time in 24 hours ("17:05"), a duration as "1 sa. 30
  dk.", and a relative time as "5 dakika önce" or "2 saat sonra", so a
  sentence takes such a value as a `%@` argument and may end on it. Its
  ordinal is "1.", and a weekday is the calendar's short name, so
  `recurrence.weekday.nth` ("%1$@ %2$@") reads "1. Pzt", the last is "son
  Pzt" and the second to last "sondan 2. Pzt". A list of names reads "A, B ve
  C" (narrow "A, B, C").
- A number followed by a full stop reads as an ordinal in Turkish ("50." is
  "ellinci", the fiftieth), so a sample number never closes a sentence: the
  milestone hints put it inside parentheses ("Toplam tamamlama sayısı (örneğin
  50). Alışkanlık devam eder.").
- Turkish has the plural categories `one` and `other`, where `one` selects
  only 1, and a noun stays singular after a number ("3 görev", never "3
  görevler"). A `one` form leaves the number out where the English does
  ("Günde bir kez" beside "Günde %lld kez"), and an entry whose English forms
  leave the number out under a large figure (the "tamamlama" under the goal
  ring's count) is a substitution with `one` and `other`. A batch dialog that
  reports two counts joins its clauses with a semicolon ("3 görev tamamlandı;
  1 görev atlandı.").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("Sığmıyor" for Won’t fit, "+%lld daha" for a small widget's overflow,
  "kaldı" as the caption under the remaining-tasks ring, "dk" for minutes on a
  complication, "Hepsi tamam" for an empty day). Accessibility labels may be
  longer. A placeholder in a narrow sheet field stays about as long as the
  English one ("Bir teşvik sözü ekleyin" for "Add an encouraging line" on the
  habit sheet).
- The capture parser (`LorvexCaptureParser`) has no Turkish vocabulary: it
  reads English and Chinese words wherever the interface language is Turkish.
  The capture hint (`capture.footer.words`) therefore gives English examples
  and says so ("Satır başına bir görev. İngilizce “tomorrow”, “3pm”, “every
  Monday”, “20 min” veya “#list” gibi sözcükler görevin ayrıntılarını
  doldurur.").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are imperatives that
  name the app exactly once and put the word uygulaması after it with the
  ending the verb needs, so the token never takes a suffix ("${applicationName}
  uygulamasına görev ekle", "${applicationName} uygulamasında görev tamamla",
  "${applicationName} uygulamasını aç"). Apple's own Turkish phrases do the
  same: 106 of the 154 translated strings that carry the token put
  Uygulamasında or uygulamasına after it, and none attaches an ending to the
  token itself.

## Thai conventions

The `th` catalogs are Thai as written in Thailand; th-TH and every other Thai
locale select them. They follow Apple's Thai usage (การตั้งค่า, ปฏิทิน,
เตือนความจำ, คำสั่งลัด, โฟกัส) and keep one term per concept across every
catalog, so a thing reads the same on the Mac, iPhone, watch, widgets, and in
Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | งาน, ลิสต์, แท็ก | ลิสต์ is Apple's Reminders word for a list and แท็ก its Notes word for a tag; a task's checklist is an เช็คลิสต์, as in Apple's Notes, and its item a รายการ |
| Inbox (the seeded list) | กล่องเข้า | Apple's Shortcuts word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | วันนี้, พรุ่งนี้, เมื่อวาน | the navigation button and the date chips |
| Someday | สักวัน | quoted “สักวัน” inside a sentence and unquoted on a button ("ย้ายไปสักวัน") |
| Due (the deadline field) | วันถึงกำหนด | Apple's Reminders word; ถึงกำหนด heads a table column and เกินกำหนด is overdue |
| Open (a task not yet done) | ยังไม่เสร็จ | the status and the filter; กำลังดำเนินการ is In Progress and เริ่มแล้ว a started task |
| Blocked, cancelled, completed | ถูกปิดกั้น, ยกเลิกแล้ว, เสร็จแล้ว | |
| Done (a button) and complete (an action) | เสร็จสิ้น, ทำเสร็จ | เสร็จสิ้น closes a sheet, as in Apple's apps (587 of Apple's strings that read Done); ทำเสร็จ completes a task; เสร็จแล้ว is the Completed state |
| Defer and snooze | เลื่อน | one word for both, the one Apple's Reminders writes for snooze; "เลื่อนไปพรุ่งนี้" moves a task to a later day and "เลื่อน 1 ชั่วโมง" snoozes a reminder |
| Plan (verb) | วางแผน | วางแผนไว้ is planned |
| Schedule (the day pane) | กำหนดการ | Apple's Calendar names its agenda มุมมองกำหนดการ, and the Agenda row below takes the same word; Apple's other apps write กำหนดเวลา for a schedule, which reads as a time limit |
| Capture (quick add) | จดงาน | |
| Review (the day and the week) | ทบทวน | รายวัน and รายสัปดาห์ are its two modes; its fields are ความสำเร็จ, อุปสรรค, สิ่งที่ได้เรียนรู้ |
| Memory | หน่วยความจำ | one entry is a รายการหน่วยความจำ; Apple's Photos writes ความทรงจำ for its own Memories, which is a different feature |
| Assistant, AI | ผู้ช่วย, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | นิสัย, เช็คอิน, สถิติต่อเนื่อง, ก้าวสำคัญ | Apple's Journal writes ช่วงเวลาเขียนที่ติดกัน for its writing streak, which is too long for a stat tile; เช็คอิน is the word of Apple's Wallet and App Intents |
| Reminder | เตือนความจำ | Apple's Reminders word |
| Dependency | ต้องรอ | the Waits on field; งานที่ต้องรอ is a task's dependencies |
| Recurrence | ทำประจำ | the word of Apple's Calendar (กิจกรรมทำประจำ) |
| Sync, snapshot | เชื่อมข้อมูล, สแนปช็อต | เชื่อมข้อมูล is Apple's word for sync (1,853 strings against 2 with ซิงค์), as in "การเชื่อมข้อมูล iCloud" |
| Event | กิจกรรม | the word Apple's Calendar uses |
| App icon badge | ป้ายกำกับ | Apple's Reminders word |
| Appearance (light, dark, system) | รูปแบบ (สว่าง, มืด, ระบบ) | รูปแบบ names Apple's Appearance setting (34 strings, among them the Appearance pane of System Settings and its App Intents), and สว่าง and มืด are its Light and Dark (26 strings each); รูปลักษณ์ is Image Playground's word for the look of a generated picture, and it is not used for the setting |
| Agenda (the mobile list mode) | กำหนดการ | |
| Apple features | การตั้งค่า, ปฏิทิน, เตือนความจำ, คำสั่งลัด, โฟกัส, การตั้งค่าระบบ, หน้าจอล็อค | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed neutrally, with no politeness particle. Apple's
  Thai strings on macOS 26 (422,120 in the system apps, frameworks, and
  extensions, among them Podcasts, Home, Maps, Photos, Journal, and Wallet)
  carry คุณ in 44,995 strings (ของคุณ in 26,071), ครับ in 7 and ค่ะ in none.
  Lorvex writes คุณ only where a possessive or a contrast needs it (106 of its
  2,416 Thai texts: "ข้อมูลของคุณ") and never ครับ, ค่ะ, or คะ. A request opens
  with โปรด where the English says please (Apple's Thai has โปรด in 3,903
  strings and กรุณา in 10), and an instruction is a bare verb phrase ("ติดตั้ง
  Lorvex ใหม่จากไฟล์ดาวน์โหลดต้นฉบับ"). A button, menu item, tab, or intent title is a
  bare verb ("เพิ่ม", "ลบ", "แก้ไข", "จดงาน Lorvex"), as in Apple's Thai (ลบ in
  653 strings, เพิ่ม in 323); an intent's description is a bare verb phrase
  ("เลื่อนงาน Lorvex ไปเป็นพรุ่งนี้"); a confirmation after an action ends in
  แล้ว ("จดงาน %@ ใน Lorvex แล้ว"); and a yes-or-no question ends in หรือไม่
  ("ลบลิสต์ “%@” หรือไม่").
- Thai has no letter case, and no space between the words of a clause. A space
  separates phrases and sentences, so a long string breaks into spaced
  clauses ("ยังไม่มีแท็ก พิมพ์แท็กแล้วกด Return"), and a clause itself is
  written solid. A Latin word, a number, or a placeholder beside Thai text has
  a space on each side ("เปิดใน Lorvex", "วันนี้อีก %lld งาน", "ทำเสร็จ
  %1$lld รายการ"), as in Apple's Thai (67,499 strings with a space between
  Latin and Thai against 74 without). A sentence has no final period (1,326
  of Apple's 422,120 strings end in one), consecutive sentences are separated
  by a space, and no string carries a zero-width space (6 in Apple's) or
  another invisible break mark: the text engine finds the line breaks inside a
  clause. A question has no question mark (323 of Apple's strings have one).
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with “ ” and a space outside each quote where the Thai text goes on
  ("ลบลิสต์ “%@” หรือไม่"); Apple's Thai writes curly double quotes in 15,474
  strings and straight ones in 378. An ellipsis is the single character …
  (8,729 strings against 31 with three dots in Apple's), and a spaced en dash
  – stands for the English em dash, the form Apple's Thai uses more often
  (276 strings against 128 with a spaced em dash). The Return key is "Return"
  after กด ("กด Return", as in Apple's Calculator and Books).
- Thai spells words as Apple's Thai does: "แอป" for an app (6,472 strings
  against 1,403 with แอปพลิเคชัน), "ไฟล์" for a file (7,135 against 20 with
  แฟ้ม), "ล็อค" (3,837 against 188 with ล็อก), and "เวอร์ชั่น" for version
  (1,527, none with เวอร์ชัน).
- Digits are Latin (Apple's Thai has no Thai digit in 422,120 strings), a comma
  groups thousands, and a point marks decimals ("10,000", "2.5"). The system
  writes a clock time in 24 hours ("17:05"), a duration as "1 ชม. 30 นาที", and
  a relative time as "5 นาทีที่ผ่านมา" or "ในอีก 2 ชั่วโมง", so a sentence takes
  such a value as a `%@` argument. Dates follow the user's calendar, which is
  the Buddhist one on a device set to Thailand ("3 ต.ค. 2569" for 3 October
  2026), so Lorvex's own Thai text never writes a year and no sentence mixes
  the two eras. The ordinal is "ที่ 1", so `recurrence.weekday.nth`
  ("%2$@ %1$@") reads "จันทร์ ที่ 1", the last is "จันทร์ สุดท้าย" and the
  second to last "จันทร์ ที่ 2 จากท้าย". A list of names is spaced and takes
  และ before the last ("A B และ C").
- Thai has the single plural category `other`, so a plural entry is one plain
  string that shows the number wherever the English forms show it ("วันละ
  %lld ครั้ง", "%lld งาน"), and a classifier follows the number: รายการ for
  items and tasks counted in a sentence, ครั้ง for times, and วัน, สัปดาห์,
  and เดือน for spans. An entry whose English forms leave the number out is a
  substitution with only `other`. A batch dialog that reports two counts is
  one plain numbered string ("ทำเสร็จ %1$lld รายการ ข้าม %2$lld รายการ").
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation
  ("ไม่พอดี" for Won’t fit, "อีก %lld" for a small widget's overflow, "เหลือ"
  as the caption under the remaining-tasks ring, "นาที" for minutes on a
  complication, "เรียบร้อยหมดแล้ว" for an empty day). Accessibility labels may
  be longer. A placeholder in a narrow sheet field stays about as long as the
  English one ("เพิ่มประโยคให้กำลังใจ" for "Add an encouraging line" on the
  habit sheet).
- The capture parser (`LorvexCaptureParser`) has no Thai vocabulary: it reads
  English and Chinese words wherever the interface language is Thai. The
  capture hint (`capture.footer.words`) therefore gives English examples and
  says so ("หนึ่งบรรทัดต่อหนึ่งงาน คำภาษาอังกฤษอย่าง “tomorrow”, “3pm”, “every
  Monday”, “20 min” หรือ “#list” จะเติมรายละเอียดของงานให้").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are bare verb phrases
  that name the app exactly once, after ใน ("เพิ่มงานใน ${applicationName}",
  "ทำงานให้เสร็จใน ${applicationName}"); Apple's Thai puts the token after ใน
  in 104 of its 153 translated strings that carry it. The phrase that opens
  the app reads "เปิด ${applicationName}".

## Greek conventions

The `el` catalogs are Greek as written in Greece; el-GR, el-CY, and every other
Greek locale select them. They follow Apple's Greek usage (Ρυθμίσεις,
Ημερολόγιο, Υπομνήσεις, Συντομεύσεις, Συγκέντρωση) and keep one term per
concept across every catalog, so a thing reads the same on the Mac, iPhone,
watch, widgets, and in Shortcuts.

| Concept | Term | Note |
|---|---|---|
| Task, list, tag | εργασία, λίστα, ετικέτα | Apple's Shortcuts words for a task and a list, and Notes' word for a tag; a task's checklist is a λίστα ελέγχου, as in Apple's Notes, and its item a στοιχείο |
| Inbox (the seeded list) | Εισερχόμενα | Apple's Shortcuts word; shown while the list keeps its seeded name |
| Today, Tomorrow, Yesterday | Σήμερα, Αύριο, Χθες | the navigation button and the date chips; inside a sentence they are lowercase ("σήμερα", "αύριο") |
| Someday | Κάποτε | quoted «Κάποτε» inside a sentence |
| Due (the deadline field) | Προθεσμία | Apple's Reminders and Shortcuts word; Εκπρόθεσμη is overdue |
| Open (a task not yet done) | Ανοιχτή | the status; Ανοιχτές is the filter, Σε εξέλιξη is In Progress and Ξεκίνησε a started task |
| Blocked, cancelled, completed | Αποκλεισμένη, Ακυρώθηκε, Ολοκληρώθηκε | a status word agrees with εργασία, so it is feminine |
| Done (a button) and complete (an action) | Τέλος, Ολοκλήρωση | Τέλος closes a sheet, as in Apple's apps (587 of Apple's strings that read Done); Ολοκλήρωση completes a task |
| Defer and snooze | Αναβολή | one word for both, the one Apple's Clock, Reminders, and Home write for snooze; "Αναβολή για αύριο" moves a task to a later day and "Αναβολή κατά 1 ώρα" snoozes a reminder |
| Plan (verb) | προγραμματισμός | Προγραμματισμένο is planned |
| Schedule (the day pane) | Πρόγραμμα | Apple's Home word |
| Capture (quick add) | Γρήγορη προσθήκη | |
| Review (the day and the week) | Ανασκόπηση | Ημερήσια and Εβδομαδιαία are its two modes; its fields are Επιτυχίες, Εμπόδια, Διδάγματα |
| Memory | Μνήμη | one entry is a καταχώριση μνήμης; Apple's Photos writes Αναμνήσεις for its own Memories, which is a different feature |
| Assistant, AI | βοηθός, AI | Claude and MCP stay as they are |
| Habit, check-in, streak, milestone | συνήθεια, καταγραφή, σερί, ορόσημο | σερί is the word Apple's Journal uses for a streak and takes the genitive ("Σερί %lld ημερών"); Καταγραφή logs a check-in |
| Celebrate (a milestone) | γιορτάζω, εορτασμός | the verb is the hints' ("Γιορτάστε όταν φτάσετε …", "που αξίζει να γιορτάσετε"), as in Apple's Journal ("Πώς γιορτάζετε αυτήν την ημέρα;"), and the field label "Όριο εορτασμού" takes the noun Apple's Messages writes for its Celebration effect |
| Reminder | υπόμνηση | Apple's Reminders word (1,154 strings against 121 with υπενθύμιση); υπενθυμίζει is the verb |
| Dependency | εξάρτηση | Εξαρτάται από is the Waits on field |
| Recurrence | επανάληψη | Apple's Calendar and Shortcuts word |
| Sync, snapshot | συγχρονισμός, στιγμιότυπο | the Mac settings tab for Cloud Sync is named Συγχρονισμός alone, and its switch reads "Συγχρονισμός με το iCloud" |
| Event | γεγονός | the word Apple's Calendar uses |
| All day | Ολοήμερο, όλη μέρα | Ολοήμερο is the word of Apple's Calendar and Shortcuts (14 of the 16 strings that read All Day; Calendar writes Όλη την ημέρα in the other 2); the lowercase label in the week grid's time gutter reads "όλη μέρα", so that it wraps between its two words where the gutter is narrow |
| App icon badge | ταμπέλα | Apple's Reminders word |
| Appearance (light, dark, system) | Εμφάνιση (Ανοιχτό, Σκούρο, Σύστημα) | Εμφάνιση names Apple's Appearance setting (41 strings, among them the Appearance pane of System Settings and its App Intents); the pane writes the feminine Ανοιχτόχρωμη and Σκούρα for Light and Dark, which do not fit under the picker's thumbnails, so the picker takes the neuter Ανοιχτό and Σκούρο that Apple's Appearance App Intents write for the values light and dark |
| Widget | widget | in Latin letters, as in Apple's Greek (210 strings) |
| Agenda (the mobile list mode) | Ατζέντα | |
| Apple features | Ρυθμίσεις, Ημερολόγιο, Υπομνήσεις, Συντομεύσεις, Συγκέντρωση, Ρυθμίσεις συστήματος, οθόνη κλειδώματος | product names stay: Lorvex, iCloud, CloudKit, Apple Watch, CarPlay, Claude, MCP, Siri, Spotlight |

- The reader is addressed formally, in the second person plural, and never
  with σου. Apple's Greek strings on macOS 26 (434,998 in the system apps,
  frameworks, and extensions, among them Podcasts, Home, Maps, Photos,
  Journal, and Wallet) carry σας in 24,831 strings and σου in 207, most of
  them in the sensitive-content warnings and the Apple ID setup text. An
  instruction is a polite plural imperative ("Επιλέξτε", "Δοκιμάστε",
  "Πληκτρολογήστε", "Ελέγξτε τη σύνδεσή σας και δοκιμάστε ξανά."), the form
  of 10,342 of Apple's sentences of four words or more against 149 with the
  singular, and Μπορείτε opens 3,201 of its strings against 23 for Μπορείς.
  There is no please word, since Apple's Greek has Παρακαλώ in 3 strings and
  Παρακαλούμε in 2: where the English says please, the polite plural
  imperative stands alone ("Παρουσιάστηκε πρόβλημα. Δοκιμάστε ξανά."). A
  button, menu item, tab, or intent title is a verbal noun ("Προσθήκη",
  "Διαγραφή", "Ακύρωση", "Ολοκλήρωση εργασίας Lorvex"), as in Apple's Greek
  (Ακύρωση in 2,163 strings, Διαγραφή in 612, Προσθήκη in 342). An intent's
  description is a polite plural imperative ("Ολοκληρώστε μια εργασία
  Lorvex."); a confirmation after an action is a past statement ("Η εργασία
  %@ ολοκληρώθηκε."); and a confirmation question opens with Να and takes the
  question mark ("Να διαγραφεί η λίστα «%@»;", the shape of 584 of Apple's
  titles).
- Greek is written in the monotonic system: one accent (tonos) on the stressed
  syllable of every word of two or more syllables, a diaeresis where two
  vowels are read apart, and no breathing or circumflex mark (Apple's Greek
  has no polytonic mark in 434,998 strings). A capital that opens a word keeps
  its accent ("Άνοιγμα", "Έως"), and a word set wholly in capitals loses it
  (3,111 of Apple's Greek strings contain an all-capital word of three or more
  letters without an accent, and one contains such a word with an accent on its
  first letter). The only all-capital word in the catalogs is the button ΟΚ,
  which Apple writes in Greek letters more often than in Latin ones (760
  strings against 663).
- Text is in sentence case: window titles, buttons, menu items, tabs, section
  headers, and intent titles capitalize only the first word ("Νέα λίστα",
  "Γρήγορη προσθήκη", "Ρυθμίσεις συστήματος"), as in Apple's Greek (48,139
  two-word labels in sentence case against 1,480 with a capital on each
  word). Names keep their capitals, and weekday and month names come from the
  calendar (Δευτέρα, Οκτωβρίου).
- Greek nouns, articles, and adjectives agree in gender, number, and case, so
  no declined word sits beside a value that arrives at run time. A value
  follows a colon label ("Πιο δυνατές ημέρες: %@", "Επόμενο: %lld ημέρες"),
  follows a noun in apposition ("Το γεγονός ημερολογίου %@ ενημερώθηκε στο
  Lorvex."), or the whole phrase that agrees with it sits inside the plural
  variation ("%arg εργασία ολοκληρώθηκε σήμερα" and "%arg εργασίες
  ολοκληρώθηκαν σήμερα"). Lorvex takes the neuter article ("το Lorvex", "του
  Lorvex"), as Apple's Greek does for Latin-script product names: the neuter
  article precedes Mac, iPhone, iCloud, and the like in 17,422 of its strings,
  and no other article does.
- User content, and Lorvex's own view and button names inside a sentence, are
  quoted with « » where the English quotes them; Apple's Greek writes
  guillemets in 29,848 strings, curly double quotes in 39, and straight ones
  in 109. An ellipsis is the single character … (10,416 strings against 62
  with three dots in Apple's), and a spaced en dash – stands for the English
  em dash (1,487 strings against 76 with a spaced em dash). The Return key is
  "Return" with the article before it ("πατήστε το Return", as in Apple's
  Calculator and Books).
- The question mark is the semicolon ;, the ASCII character that Apple's Greek
  uses (8,475 of its strings end in one, and 2 use the separate Greek
  question mark character), so a semicolon never separates two clauses: a
  batch dialog that reports two counts joins them with a comma
  ("Ολοκληρώθηκαν 3 εργασίες, παραλείφθηκε 1 εργασία."), and every string that
  asks something ends in ; ("Να διαγραφεί αυτό το επαναλαμβανόμενο γεγονός;").
- A point groups thousands and a comma marks decimals ("10.000", "2,5"). The
  system writes a clock time in the region's clock ("5:05 μμ" on a 12-hour
  clock), a duration as "1 ώ. 30 λ.", and a relative time as "πριν από 5
  λεπτά" or "σε 2 ώρες" (abbreviated on a chip: "σε 3 ημ.", "3 ημ. πριν"), so
  a sentence takes such a value as a `%@` argument. Its ordinal is the bare
  number and a weekday is the calendar's short name, so
  `recurrence.weekday.nth` ("%1$@η %2$@") reads "1η Δευ", the last is
  "τελευταία Δευ" and the second to last "2η από το τέλος Δευ". The feminine
  ending is right for six weekdays and wrong for the neuter Σάββατο (short
  name Σάβ), whose ordinal is "1ο" and whose last is "τελευταίο"; one template
  cannot express both. A list of names reads "A, B και C" (narrow "A, B, C").
- A count of a total reads "3 από 5", the form of Apple's Greek for "%1$lld of
  %2$lld" (9 strings, among them Books and Notes). The habits header puts each
  of its three counts after a short period label and leaves out the word for
  done ("Σήμερα: 8 από 9 · Αυτή την εβδομάδα: 0 από 2 · Αυτόν τον μήνα: 0 από
  1"), since the full sentence is longer and the line sits under the Συνήθειες
  title. The small widget's footer likewise counts "3 ολοκληρώθηκαν" without
  σήμερα, and its accessibility label keeps the full "%arg εργασίες
  ολοκληρώθηκαν σήμερα".
- Greek has the plural categories `one` and `other`, where `one` selects only
  1, and a `one` form leaves the number out where the English does ("Μία φορά
  την ημέρα" beside "%lld φορές την ημέρα"). A phrase that needs the plural
  forms of a noun and its predicate puts both inside the variation.
- Compact surfaces (the watch, widgets, CarPlay, the menu bar panel, toolbar
  buttons, segmented controls, the time column of suggested times, and App
  Shortcut short titles) use shorter wording than a literal translation ("Δεν
  χωράει" for Won’t fit, "+%lld ακόμη" for a small widget's overflow, "ακόμη"
  as the caption under the remaining-tasks ring, "λ." for minutes on a
  complication, "Όλα καθαρά" for an empty day). Accessibility labels may be
  longer. A placeholder in a narrow sheet field stays about as long as the
  English one ("Προσθέστε ενθάρρυνση" for "Add an encouraging line" on the
  habit sheet).
- The capture parser (`LorvexCaptureParser`) has no Greek vocabulary: it reads
  English and Chinese words wherever the interface language is Greek. The
  capture hint (`capture.footer.words`) therefore gives English examples in
  « » and says so ("Μία εργασία ανά γραμμή. Αγγλικές λέξεις όπως «tomorrow»,
  «3pm», «every Monday», «20 min» ή «#list» συμπληρώνουν τις λεπτομέρειές
  της.").
- Siri and Shortcuts phrases in `AppShortcuts.xcstrings` are verbal nouns that
  name the app exactly once, in guillemets after στο ("Προσθήκη εργασίας στο
  «${applicationName}»") or με ("Μετακίνηση εργασίας στο σήμερα με
  «${applicationName}»"). The phrase that opens the app reads "Άνοιγμα του
  «${applicationName}»". Apple's own Greek phrases take this form: of the 153
  translated strings that carry the token, 150 put it in guillemets and 81 open
  with a verbal noun, and none opens with a singular imperative.

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
   Ukrainian, Polish, Japanese, Korean, Traditional Chinese, Hindi, Arabic,
   Persian, Urdu, Hebrew, German, Dutch, Romanian, Indonesian, Malay,
   Vietnamese, Turkish, Thai, and Greek ones: one term per concept across every
   catalog, the form of address and the evidence for it, punctuation and
   quotation marks, spacing around numbers and Latin words.
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
