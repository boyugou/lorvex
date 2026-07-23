# Apple Localization Architecture Audit

Primary sources:

- [Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Preparing your app's text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)
- [Using generated localizable symbols](https://developer.apple.com/documentation/xcode/using-generated-localizable-symbols-in-your-code)
- [LocalizedStringResource](https://developer.apple.com/documentation/foundation/localizedstringresource)
- [Testing localizations when running your app](https://developer.apple.com/documentation/xcode/testing-localizations-when-running-your-app)
- [Choosing localization regions and scripts](https://developer.apple.com/documentation/xcode/choosing-localization-regions-and-scripts)
- [Code-along: Explore localization with Xcode — WWDC25](https://developer.apple.com/videos/play/wwdc2025/225/)

Last verified: 2026-07-10 against code snapshot `77e2b5f76b`

## Overall Verdict

Lorvex has a strong localization foundation, but the current implementation is
not yet the optimal/final Apple architecture. Catalog organization, bundle
metadata, placeholder validation, and source-key verification are unusually
thorough. Runtime lookup and translation-quality evidence have important gaps,
including one confirmed bundle bug on system-facing App Intent metadata.

No database or CloudKit schema change is required to correct this architecture.

## Current Shipping Surface

- Seven module-owned `Localizable.xcstrings` catalogs.
- 2,281 keys and 30,440 translated string units, including 59 keys with plural
  variations.
- Thirteen declared languages in every catalog: `de`, `en`, `es`, `fr`, `it`,
  `ja`, `ko`, `pl`, `pt`, `ru`, `tr`, `zh-Hans`, and `zh-Hant`.
- Five target-specific InfoPlist localization trees, each containing all 13
  languages (65 `InfoPlist.strings` files total).
- macOS and mobile expose an in-app language picker; the change requires a
  relaunch/reopen.
- No repository-managed App Store Connect metadata/screenshot localization set
  was found. Binary localization and storefront localization are therefore at
  different readiness levels.

The read-only source verifier passes and proves structural completeness, key
existence, language-set parity, placeholder parity, English-default parity for
the main/mobile helpers, InfoPlist coverage, and selected App Intent metadata
rules. It does not prove semantic translation quality or runtime rendering in
each locale.

## What Is Already Well Designed

1. String Catalogs are the correct current Apple source format.
2. Catalog ownership follows resource-bundle/module boundaries, avoiding an
   assumption that framework strings live in `Bundle.main`.
3. The locale set is discovered from catalog data and enforced across every
   shipping surface instead of hardcoding an English/Chinese pair.
4. Plural forms exist for languages such as Russian and Polish rather than
   assembling English-style singular/plural fragments in views.
5. InfoPlist permission text, widgets, Watch, CarPlay, App Intents, and ordinary
   macOS/mobile UI are included in the same governance process.
6. The translation-pack workflow rejects stale occurrences, empty values, path
   traversal, missing languages, and printf-placeholder drift before writing.
7. Date-only storage/parsing is separated from locale-dependent presentation;
   visible calendar labels generally use locale-aware formatters.

## L10N-H1 — App Intent and Widget Metadata Defaults to the Wrong Bundle

Severity: High

Apple documents that `LocalizedStringResource` defaults to the main bundle and
that code in a framework/package must specify the resource bundle. Lorvex has
approximately 468 calls in `LorvexSystemIntents`, 19 in `LorvexWidgetIntents`,
and 10 in `LorvexWidgetExtension` that construct resources without a bundle.
Their catalogs are packaged in separate SwiftPM resource bundles, not in the
main app's `Localizable.strings`.

A read-only probe against the staged macOS artifact confirmed the behavior for
`system.task.complete.title` at German locale:

- lookup from the app bundle: `Complete Lorvex Task` (English fallback);
- lookup from `LorvexApple_LorvexSystemIntents.bundle`:
  `Lorvex-Aufgabe abschließen`.

Dynamic intent dialogs that use `SystemL10n` can find the module catalog, while
many static titles, descriptions, entity names, case labels, and parameter
labels cannot. This can leave Shortcuts/Siri/widget configuration metadata in
English even when the catalog is complete.

Required direction: construct every late-bound resource with the correct module
bundle (or a generated symbol that carries it), and add artifact-level runtime
tests for representative App Intent and widget metadata in multiple locales.

## L10N-H2 — Custom Runtime Reimplements Native Plural and Locale Resolution

Severity: Medium-High architecture debt

`LorvexLocalizedCatalog` parses raw `.xcstrings` JSON itself, chooses a language,
parses plural dictionaries, and delegates CLDR category selection to
`LorvexPluralRules`. Resolved values are then often wrapped as string literals,
which discards the native deferred localization contract.

This duplicates behavior that compiled String Catalogs, `LocalizedStringResource`,
and Foundation already provide. It is especially risky because the plural-rule
switch only models the current 13 languages, while the documented expansion
plan adds Hindi, Ukrainian, Romanian, Bengali, Greek, Tamil, Telugu, Marathi,
Malayalam, and others with additional plural rules. Unknown languages currently
fall into `other`, which will be grammatically wrong for several planned
locales. Generic `pt` also leaves the intended Portuguese regional rule
ambiguous.

Required direction: make compiled catalogs and native localized interpolation
the production authority. Use explicit module bundles (`#bundle`/bundle-aware
resources), native plural variations, and Xcode-generated localizable symbols.
Keep a small compatibility adapter only where the non-Xcode SwiftPM packaging
path genuinely requires it; do not make a hand-maintained CLDR engine the
cross-platform product contract.

## L10N-M1 — “Translated” State Does Not Mean the Translation Is Complete

Severity: Medium product-quality gap

All 30,440 units are marked `translated`, and every locale has every key. The
verifier accepts any non-empty value with matching placeholders. It does not
detect a copied English fallback or judge meaning.

At least 32 clearly user-facing keys are currently copied unchanged from
English into all 12 non-English languages. Examples include `Copied`, calendar
filter/settings screens, Cloud Sync mode explanations, database status labels,
assistant-context deletion confirmation, and several accessibility labels.
Brand names, provider names, format-only values, and legitimate cognates were
excluded from that conservative count.

Only 715 of 2,281 keys (about 31%) carry translator comments. Coverage is strong
for System Intents but low in the two largest ordinary UI catalogs and nearly
absent in CarPlay and WidgetKitSupport. Apple recommends comments describing
the interface, context, variables, and placeholders; the current shortage makes
semantic translation mistakes more likely.

Required direction: distinguish `translated`, `machine translated`, and
`human-reviewed` release evidence; reject suspicious all-locale English clones
unless allowlisted; add/generate contextual comments; and run native-speaker
review on privacy, destructive actions, onboarding, sync, calendar, and
accessibility text before advertising a language as complete.

## L10N-M2 — The In-App Language Choice Is Not a Proven Cross-Surface Policy

Severity: Medium behavior gap

`AppLanguage.apply()` writes `AppleLanguages` to `UserDefaults.standard` for the
current process/bundle. The main app, widget extension, Watch app, and other
extensions have distinct preference domains, so the claim that this setting is
shared by every Apple surface is not established. The system's per-app language
setting is separately managed by iOS/macOS.

App Intents add another locale dimension: Apple documents that Siri/Shortcuts
may execute an intent in a locale different from the app's current locale.
Late-bound `LocalizedStringResource` supports that behavior, but eager
`SystemL10n.string` lookup followed by `IntentDialog(stringLiteral:)` fixes the
dialog to the process locale instead of the request's locale.

Required direction: choose one explicit policy:

1. Prefer Apple's system per-app language and remove the redundant in-app
   override; or
2. Store an app-owned language choice in a deliberately shared location and
   pass the selected locale explicitly through every app/extension lookup.

Regardless of that choice, preserve App Intents' system-request locale for
Siri/Shortcuts results rather than forcing the foreground app locale.

## L10N-M3 — Tests Prove Structure, Not the User Experience

Severity: Medium release-evidence gap

The repository documentation explicitly states that its Swift tests do not
render translated output for a selected runtime locale. No committed
pseudolanguage, double-length, forced-right-to-left, or per-locale screenshot
matrix was found. RTL languages are intentionally deferred.

Required release evidence should include:

- runtime lookup from every resource bundle, including system-facing metadata;
- German or French for expansion pressure, Russian/Polish for plurals,
  Japanese/Korean, and both Chinese scripts;
- multiple regions independently of language;
- Xcode double-length and right-to-left pseudolanguages even before shipping an
  RTL translation;
- Dynamic Type, VoiceOver, widgets, Watch complications, Shortcuts, Siri, and
  permission dialogs;
- native-speaker screenshots for destructive/privacy-sensitive workflows.

## L10N-M4 — Locale and Storefront Scope Is Not Yet Final

Severity: Low-Medium product decision

Apple recommends selecting the most specific language/region or script that
matches the actual translation. Lorvex correctly distinguishes both Chinese
scripts but otherwise uses language-only identifiers. Before release, decide
whether `pt` is neutral, Brazilian, or European Portuguese and whether the
English/Spanish translations are intentionally region-neutral.

App Store Connect descriptions, keywords, screenshots, promotional text, and
support metadata are localized separately from the binary. No versioned
storefront-localization source was found, so shipping 13 binary languages does
not yet imply 13 localized App Store presentations.

## Recommended Final Architecture

1. Keep the seven module/resource ownership boundaries.
2. Make Apple's compiled String Catalog runtime authoritative.
3. Enable Xcode-generated localization symbols for compile-time key and
   placeholder safety.
4. Require an explicit module bundle for every framework/package resource,
   especially all App Intent and widget metadata.
5. Use native interpolation/plural variations and `FormatStyle`; retire the
   custom CLDR switch as production behavior.
6. Define one cross-process language-selection policy and a separate App Intent
   request-locale policy.
7. Add semantic translation review and runtime/screenshot release gates in
   addition to the existing structural verifier.
8. Version App Store metadata localizations beside the release process.

The existing catalogs and translations can be migrated in place. This is a
runtime/tooling cleanup, not a reason to rename keys wholesale or alter user
data schemas.
