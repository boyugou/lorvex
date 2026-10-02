import Foundation
import LorvexCarPlay
import Testing
@testable import LorvexCore
@testable import LorvexApple
@testable import LorvexMobile
@testable import LorvexSystemIntents
@testable import LorvexWatch
@testable import LorvexWidgetExtension
@testable import LorvexWidgetIntents
import LorvexWidgetKitSupport
import LorvexWidgetViews

/// Verifies the Localizable.xcstrings catalog: presence of required keys,
/// non-empty source values, complete shipped-language values, and correct JSON
/// structure.
///
/// A `.xcstrings` catalog is a build input, not a build output: SwiftPM compiles
/// it into `<language>.lproj/Localizable.strings` inside the module's resource
/// bundle and does not copy the catalog itself. So the tests that check what was
/// authored read the catalog from `Sources/`, and the tests that check what a
/// module actually ships read the compiled `.lproj` payload out of its bundle.
/// Neither path needs a particular locale, so both run under SwiftPM and Xcode.
struct LocalizationTests {

    // MARK: - Catalog structure

    @Test("The language picker offers every shipped language, each by its own name")
    func languagePickerOffersEveryShippedLanguage() throws {
        let languages = try shippedCatalogLanguageIDs()
        #expect(Set(AppLanguage.selectable.map(\.rawValue)) == Set(languages))
        for language in AppLanguage.selectable {
            #expect(!language.endonym.isEmpty, "\(language.rawValue) has no endonym")
        }
    }

    @Test("Every module bundle ships a compiled string table per shipped language")
    func moduleBundlesShipCompiledStringTables() throws {
        let languages = try shippedCatalogLanguageIDs()
        for module in Self.shippedBundles() {
            for language in languages {
                let lproj = try #require(
                    module.bundle.url(forResource: language, withExtension: "lproj"),
                    "\(module.name) bundle has no \(language).lproj"
                )
                let strings = try loadInfoPlistStrings(lproj.appending(path: "Localizable.strings"))
                #expect(
                    !strings.isEmpty,
                    "\(module.name)/\(language).lproj/Localizable.strings is empty"
                )
            }
        }
    }

    @Test("Catalog parses as valid JSON")
    func catalogParsesAsJSON() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let sourceLanguage = try #require(json["sourceLanguage"] as? String)
        #expect(!sourceLanguage.isEmpty)
        #expect(json["version"] as? String == "1.0")
    }

    @Test("Every shipped catalog declares the same source language")
    func shippedCatalogsShareSourceLanguage() throws {
        let sourceLanguages = try shippedCatalogSourceLanguages()
        #expect(sourceLanguages.count == 1, "Source language drift across catalogs: \(sourceLanguages)")
    }

    // MARK: - Required key presence

    private static let requiredKeys: [String] = [
        "sidebar.item.today",
        "sidebar.item.tasks",
        "sidebar.item.lists",
        "sidebar.item.calendar",
        "sidebar.item.habits",
        "sidebar.item.reviews",
        "sidebar.item.memory",
        "sidebar.settings",
        "habits.header.done.today",
        "window.title.task_detail",
        "task_command.show_detail",
        "task_command.save",
        "task_command.start",
        "task_command.pause",
        "task_command.defer_to_tomorrow",
        "task_command.complete",
        "task_command.reopen",
        "task_command.cancel",
        "app.command.refresh",
        "settings.cloud_sync.pending_detail",
    ]

    @Test("All required catalog keys are present")
    func allRequiredKeysPresent() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let strings = try #require(json["strings"] as? [String: Any])

        for key in Self.requiredKeys {
            #expect(strings[key] != nil, "Missing catalog key: \(key)")
        }
    }

    // MARK: - Source-language value completeness

    @Test("All required keys have non-empty source-language values")
    func allRequiredKeysHaveNonEmptySourceValues() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let strings = try #require(json["strings"] as? [String: Any])
        let sourceLanguage = try #require(json["sourceLanguage"] as? String)

        for key in Self.requiredKeys {
            guard let entry = strings[key] as? [String: Any] else { continue }
            guard let localizations = entry["localizations"] as? [String: Any],
                  let localization = localizations[sourceLanguage] as? [String: Any],
                  let stringUnit = localization["stringUnit"] as? [String: Any],
                  let value = stringUnit["value"] as? String else {
                Issue.record("Key '\(key)' has no \(sourceLanguage) stringUnit.value")
                continue
            }
            #expect(!value.isEmpty, "Key '\(key)' has an empty \(sourceLanguage) value")
        }
    }

    // MARK: - Extraction state

    @Test("All catalog entries use extractionState 'manual'")
    func allEntriesAreManuallyExtracted() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let strings = try #require(json["strings"] as? [String: Any])

        for (key, value) in strings {
            guard let entry = value as? [String: Any] else { continue }
            let state = entry["extractionState"] as? String
            #expect(state == "manual", "Key '\(key)' has extractionState '\(state ?? "nil")'; expected 'manual'")
        }
    }

    // MARK: - Shipped language completeness

    /// Reads the catalog at `url` and returns its `strings` map, failing the
    /// test if the file is missing or malformed.
    private func loadStrings(_ url: URL?) throws -> [String: Any] {
        let json = try loadCatalog(url)
        return try #require(json["strings"] as? [String: Any])
    }

    private func loadCatalog(_ url: URL?) throws -> [String: Any] {
        let url = try #require(url, "catalog URL is nil — no Localizable.xcstrings in the source tree")
        let data = try Data(contentsOf: url)
        return try #require(
            try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(url.lastPathComponent) is not valid JSON"
        )
    }

    /// Returns every localization ID declared by a catalog. The source language
    /// is included even if an entry omits an explicit source block.
    private func catalogLanguageIDs(_ url: URL?) throws -> [String] {
        let json = try loadCatalog(url)
        let sourceLanguage = try #require(json["sourceLanguage"] as? String)
        let strings = try #require(json["strings"] as? [String: Any])
        var languages = Set([sourceLanguage])
        for value in strings.values {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            languages.formUnion(localizations.keys)
        }
        return languages.sorted()
    }

    /// Records an issue for every entry in `strings` whose `localizations` lack
    /// a non-empty `stringUnit.value` for a shipped language. New languages are
    /// discovered from the catalogs, so this test does not need edits when
    /// Lorvex adds another shipped language.
    private func assertEveryKeyHasLanguages(
        _ strings: [String: Any],
        catalog: String,
        languages: [String]
    ) {
        for (key, value) in strings {
            guard let entry = value as? [String: Any] else { continue }
            let localizations = entry["localizations"] as? [String: Any]
            for language in languages {
                guard let localization = localizations?[language] as? [String: Any] else {
                    Issue.record("\(catalog): key '\(key)' has no \(language) translation")
                    continue
                }
                // Plural-variation entries carry per-category stringUnits
                // instead of a single one; the mandatory CLDR category is
                // "other".
                if let plural =
                    (localization["variations"] as? [String: Any])?["plural"] as? [String: Any]
                {
                    guard let other = plural["other"] as? [String: Any],
                          let unit = other["stringUnit"] as? [String: Any],
                          let otherValue = unit["value"] as? String else {
                        Issue.record(
                            "\(catalog): key '\(key)' \(language) plural lacks an 'other' form")
                        continue
                    }
                    #expect(
                        !otherValue.isEmpty,
                        "\(catalog): key '\(key)' has an empty \(language) plural 'other'")
                    continue
                }
                guard let stringUnit = localization["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String else {
                    Issue.record("\(catalog): key '\(key)' has no \(language) translation")
                    continue
                }
                #expect(!value.isEmpty, "\(catalog): key '\(key)' has an empty \(language) value")
            }
        }
    }

    /// Count-interpolating Siri dialogs must stay CLDR plural entries, or the
    /// source language reads "1 open tasks" (a plain entry has no singular
    /// form). Structural, so it runs regardless of whether the toolchain
    /// compiled the catalog into per-language `.lproj` bundles.
    @Test("Count-driven dialogs carry English plural variations")
    func countDrivenStringsUsePluralVariations() throws {
        func englishPluralForms(_ url: URL?, _ key: String) throws -> (one: String, other: String) {
            let strings = try loadStrings(url)
            let entry = try #require(strings[key] as? [String: Any], "missing catalog key: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let english = try #require(localizations["en"] as? [String: Any], "\(key) missing en")
            let plural = try #require(
                (english["variations"] as? [String: Any])?["plural"] as? [String: Any],
                "\(key) en is not a plural variation")
            func form(_ category: String) throws -> String {
                let unit = try #require(
                    (plural[category] as? [String: Any])?["stringUnit"] as? [String: Any],
                    "\(key) plural missing '\(category)'")
                return try #require(unit["value"] as? String)
            }
            return (try form("one"), try form("other"))
        }

        let systemDialogKeys = [
            "system.status.overview.read.summary_dialog",
            "system.list.read.names_dialog",
            "system.task.upcoming.read.dialog",
            "system.task.deferred.read.dialog",
            "system.task.reminders.set.dialog",
            "system.habit.reminders.read.dialog_count",
            "system.task.reminders.due.read.names_dialog",
            "system.task.reminders.upcoming.read.names_dialog",
            "system.review.weekly.read.week_of_dialog",
            "system.task.dependency.read.waiting_dialog",
            "system.task.dependency.read.waits_on_dialog",
            "system.list.health.read.overdue_dialog",
        ]
        for key in systemDialogKeys {
            let forms = try englishPluralForms(Self.sourceCatalogURL("LorvexSystemIntents"), key)
            #expect(
                forms.one != forms.other,
                "\(key) English one/other must differ so Siri never says '1 … tasks'")
        }
    }

    @Test("Every LorvexApple key is translated into every shipped language")
    func lorvexAppleCatalogIsFullyTranslatedToShippedLanguages() throws {
        let strings = try loadStrings(Self.sourceCatalogURL("LorvexApple"))
        let languages = try shippedCatalogLanguageIDs()
        assertEveryKeyHasLanguages(strings, catalog: "LorvexApple", languages: languages)
    }

    @Test("LorvexMobile catalog exists and parses as JSON")
    func mobileCatalogExistsAndParses() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexMobile"))
        let sourceLanguage = try #require(json["sourceLanguage"] as? String)
        #expect(try shippedCatalogSourceLanguages().contains(sourceLanguage))
    }

    @Test("Every LorvexMobile key is translated into every shipped language")
    func mobileCatalogIsFullyTranslatedToShippedLanguages() throws {
        let strings = try loadStrings(Self.sourceCatalogURL("LorvexMobile"))
        let languages = try shippedCatalogLanguageIDs()
        assertEveryKeyHasLanguages(strings, catalog: "LorvexMobile", languages: languages)
    }

    @Test("Every shipped module catalog is translated into every shipped language")
    func moduleCatalogsAreFullyTranslatedToShippedLanguages() throws {
        let languages = try shippedCatalogLanguageIDs()

        for catalog in try shippedModuleCatalogs() {
            let strings = try loadStrings(catalog.url)
            assertEveryKeyHasLanguages(strings, catalog: catalog.name, languages: languages)
        }
    }

    @Test("Shipping bundle plists declare every shipped catalog language")
    func shippingBundlePlistsDeclareEveryShippedCatalogLanguage() throws {
        let languages = try shippedCatalogLanguageIDs()
        let sourceLanguages = try shippedCatalogSourceLanguages()
        let sourceLanguage = try #require(sourceLanguages.first)
        let configURL = try #require(Self.packageRootURL()?.appending(path: "Config"))
        let plistURLs = try FileManager.default.contentsOfDirectory(
            at: configURL,
            includingPropertiesForKeys: nil
        )
            .filter { $0.lastPathComponent.hasSuffix("-Info.plist") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!plistURLs.isEmpty, "No shipping bundle Info.plist files found in Config")

        for plistURL in plistURLs {
            let data = try Data(contentsOf: plistURL)
            let plist = try #require(
                try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                "\(plistURL.lastPathComponent) is not a dictionary plist"
            )
            let localizations = try #require(
                plist["CFBundleLocalizations"] as? [String],
                "\(plistURL.lastPathComponent) missing CFBundleLocalizations"
            )
            #expect(
                localizations.sorted() == languages,
                "\(plistURL.lastPathComponent) CFBundleLocalizations \(localizations.sorted()) != \(languages)"
            )
            if let developmentRegion = plist["CFBundleDevelopmentRegion"] as? String,
               developmentRegion != "$(DEVELOPMENT_LANGUAGE)" {
                #expect(
                    developmentRegion == sourceLanguage,
                    "\(plistURL.lastPathComponent) CFBundleDevelopmentRegion \(developmentRegion) != \(sourceLanguage)"
                )
            }
        }
    }

    @Test("Shipping bundle InfoPlist strings cover every localized system-facing value")
    func shippingBundleInfoPlistStringsCoverSystemFacingValues() throws {
        let languages = try shippedCatalogLanguageIDs()
        let configURL = try #require(Self.packageRootURL()?.appending(path: "Config"))
        let localizedInfoRoot = configURL.appending(path: "InfoPlist")
        let bundleResourceTargets: [String: String] = [
            "LorvexMobileApp-Info.plist": "LorvexMobileApp",
            "LorvexWatchApp-Info.plist": "LorvexWatchApp",
            "LorvexWatchComplication-Info.plist": "LorvexWatchComplication",
            "LorvexWidgets-Info.plist": "LorvexWidgets",
        ]

        for (plistName, resourceTarget) in bundleResourceTargets.sorted(by: { $0.key < $1.key }) {
            let plistURL = configURL.appending(path: plistName)
            let data = try Data(contentsOf: plistURL)
            let plist = try #require(
                try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                "\(plistName) is not a dictionary plist"
            )
            let requiredKeys = localizedInfoPlistKeys(in: plist)
            #expect(!requiredKeys.isEmpty, "\(plistName) has no localized Info.plist keys")

            for language in languages {
                let stringsURL = localizedInfoRoot
                    .appending(path: resourceTarget)
                    .appending(path: "\(language).lproj")
                    .appending(path: "InfoPlist.strings")
                let strings = try loadInfoPlistStrings(stringsURL)
                for key in requiredKeys {
                    let value = strings[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    #expect(
                        !value.isEmpty,
                        "\(stringsURL.path) missing non-empty localization for \(key)"
                    )
                }
            }
        }
    }

    @Test("Native Mobile lookups resolve the selected language and typed arguments")
    func nativeMobileLookupsResolveNonEnglishValues() throws {
        let zhHansBundle = try #require(
            MobileL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })

        #expect(
            String(
                localized: "tab.today", defaultValue: "Today",
                table: "Localizable", bundle: zhHansBundle
            ) == "今天"
        )
        #expect(
            String(
                localized: "notification.snooze.body", defaultValue: "Snoozed reminder",
                table: "Localizable", bundle: zhHansBundle
            ) == "已延后的提醒"
        )
        let remaining = 3
        #expect(
            String(
                localized: "habits.detail.period_remaining",
                defaultValue: "\(remaining) to go",
                table: "Localizable", bundle: zhHansBundle
            ) == "还差 3\u{00A0}次"
        )
    }

    @Test("Native Mobile count grammar and composed messages resolve correctly")
    func nativeMobileCountGrammarAndComposedMessagesResolveCorrectly() throws {
        func languageBundle(_ language: String) throws -> Bundle {
            try #require(
                MobileL10n.bundle.url(forResource: language, withExtension: "lproj")
                    .flatMap { Bundle(url: $0) })
        }

        let english = try languageBundle("en")
        func retention(_ days: Int, in bundle: Bundle) -> String {
            String(
                localized: "settings.activity.retention.days", defaultValue: "\(days) days",
                table: "Localizable", bundle: bundle)
        }
        #expect(retention(1, in: english) == "1 day")
        #expect(retention(30, in: english) == "30 days")
        let weeks = 1
        let targetMetDays = 1
        let partialDays = 2
        let weeksText = String(
            localized: "habits.detail.heatmap.weeks_count",
            defaultValue: "\(weeks) weeks",
            table: "Localizable", bundle: english)
        let targetMetText = String(
            localized: "habits.detail.heatmap.met_days_count",
            defaultValue: "Target met on \(targetMetDays) days",
            table: "Localizable", bundle: english)
        let partialText = String(
            localized: "habits.detail.heatmap.partial_days_count",
            defaultValue: "\(partialDays) partial days",
            table: "Localizable", bundle: english)
        let heatmapFormat = String(
            localized: "habits.detail.heatmap.a11y",
            defaultValue: "Completion heatmap covering %1$@. %2$@. %3$@.",
            table: "Localizable", bundle: english)
        #expect(
            String(format: heatmapFormat, weeksText, targetMetText, partialText)
                == "Completion heatmap covering 1 week. Target met on 1 day. 2 partial days."
        )

        // Spanish verbs agree with the count, so a count string varies by plural
        // even where English writes every form alike.
        let spanish = try languageBundle("es")
        func remaining(_ count: Int, in bundle: Bundle) -> String {
            String(
                localized: "habits.detail.period_remaining", defaultValue: "\(count) to go",
                table: "Localizable", bundle: bundle)
        }
        #expect(remaining(1, in: english) == "1 to go")
        #expect(remaining(1, in: spanish) == "Falta 1")
        #expect(remaining(3, in: spanish) == "Faltan 3")

        let simplifiedChinese = try languageBundle("zh-Hans")
        let finished = 3
        #expect(
            String(
                localized: "review.calm.finished",
                defaultValue: "You finished \(finished) tasks.",
                table: "Localizable", bundle: simplifiedChinese
            ) == "你完成了 3\u{00A0}项任务。"
        )
    }

    // MARK: - Native runtime resolution guardrails

    /// Proves native `String(localized:table:bundle:)` resolves the per-language
    /// value compiled into the SwiftPM module bundle. This is the foundation the
    /// native-localization runtime rests on: on the Xcode-26 toolchain the gate
    /// compiles each
    /// `.xcstrings` into per-language `.lproj/*.strings`, so native resolution —
    /// not a hand-rolled JSON reader — returns the translated string. Expected
    /// values are read from the catalog, so this is not brittle to translation
    /// edits.
    @Test("Native resolution returns the per-language catalog value")
    func nativeResolutionReturnsPerLanguageValue() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let strings = try #require(json["strings"] as? [String: Any])
        func catalogValue(_ language: String) throws -> String {
            let entry = try #require(strings["sidebar.item.today"] as? [String: Any])
            let locs = try #require(entry["localizations"] as? [String: Any])
            let loc = try #require(locs[language] as? [String: Any])
            let unit = try #require(loc["stringUnit"] as? [String: Any])
            return try #require(unit["value"] as? String)
        }
        let enValue = try catalogValue("en")
        let zhHansValue = try catalogValue("zh-Hans")
        #expect(enValue != zhHansValue, "fixture key must differ across en/zh-Hans to prove language switching")

        let bundle = LorvexL10n.bundle
        let enBundle = try #require(bundle.url(forResource: "en", withExtension: "lproj").flatMap { Bundle(url: $0) })
        let zhHansBundle = try #require(bundle.url(forResource: "zh-Hans", withExtension: "lproj").flatMap { Bundle(url: $0) })
        #expect(String(localized: "sidebar.item.today", table: "Localizable", bundle: enBundle) == enValue)
        #expect(String(localized: "sidebar.item.today", table: "Localizable", bundle: zhHansBundle) == zhHansValue)
    }

    /// Proves native plural resolution selects the correct CLDR category from the
    /// compiled `.stringsdict` using an explicit key plus an interpolated `Int`
    /// in `defaultValue` — the form that replaces the custom `LorvexPluralRules`
    /// engine. English's `one` and `other` categories select distinct forms,
    /// proving the native platform performs the category lookup rather than a
    /// hand-rolled switch.
    @Test("Native plural resolution selects the CLDR category from the stringsdict")
    func nativePluralResolutionSelectsCldrCategory() throws {
        let json = try loadCatalog(Self.sourceCatalogURL("LorvexApple"))
        let strings = try #require(json["strings"] as? [String: Any])
        func pluralForm(_ language: String, _ category: String) throws -> String {
            let entry = try #require(strings["habits.milestone.value.count"] as? [String: Any])
            let locs = try #require(entry["localizations"] as? [String: Any])
            let loc = try #require(locs[language] as? [String: Any])
            let plural = try #require((loc["variations"] as? [String: Any])?["plural"] as? [String: Any])
            let unit = try #require((plural[category] as? [String: Any])?["stringUnit"] as? [String: Any])
            return try #require(unit["value"] as? String)
        }
        let bundle = LorvexL10n.bundle
        let enBundle = try #require(bundle.url(forResource: "en", withExtension: "lproj").flatMap { Bundle(url: $0) })
        func native(_ b: Bundle, _ n: Int, locale: Locale) -> String {
            String(
                localized: "habits.milestone.value.count", defaultValue: "\(n) completions",
                table: "Localizable", bundle: b, locale: locale)
        }
        // English: the interpolated count selects one vs other, matching the catalog forms.
        let english = Locale(identifier: "en")
        #expect(native(enBundle, 1, locale: english) == String(format: try pluralForm("en", "one"), 1))
        #expect(native(enBundle, 5, locale: english) == String(format: try pluralForm("en", "other"), 5))
        #expect(native(enBundle, 1, locale: english) != native(enBundle, 5, locale: english))
    }

    @Test("Native plural interpolation preserves multi-placeholder argument order")
    func nativePluralInterpolationPreservesMultipleArguments() throws {
        let appleEnglish = try #require(
            LorvexL10n.bundle.url(forResource: "en", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })
        func archiveMessage(count: Int, name: String) -> String {
            String(
                localized: "list_row.archive.nonempty_count_message",
                defaultValue: "“\(name)” can’t be deleted while it still holds \(count) tasks. Archive it instead to retire it while keeping its tasks and history. You can unarchive it later.",
                table: "Localizable",
                bundle: appleEnglish)
        }
        #expect(archiveMessage(count: 1, name: "Work").contains("1 task"))
        #expect(!archiveMessage(count: 1, name: "Work").contains("1 tasks"))
        #expect(archiveMessage(count: 2, name: "Work").contains("“Work”"))
        #expect(archiveMessage(count: 2, name: "Work").contains("2 tasks"))

        let widgetEnglish = try #require(
            WidgetL10n.bundle.url(forResource: "en", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })
        func progress(completed: Int, total: Int) -> String {
            String(
                localized: "widget.progress.a11y",
                defaultValue: "\(completed) of \(total) tasks completed today",
                table: "Localizable",
                bundle: widgetEnglish)
        }
        #expect(progress(completed: 1, total: 1) == "1 of 1 task completed today")
        #expect(progress(completed: 1, total: 2) == "1 of 2 tasks completed today")
    }

    @Test("Deferred App-Intent plural resources retain their key, bundle, and arguments")
    func deferredAppIntentPluralResourcesResolveNatively() {
        func dialog(count: Int) -> String {
            let tag = "work"
            let summary = "Plan, ship"
            let resource = LocalizedStringResource(
                "system.tag.find_tasks.dialog",
                defaultValue: "\(count) Lorvex tasks tagged \(tag): \(summary)",
                table: "Localizable",
                locale: Locale(identifier: "en"),
                bundle: SystemL10n.bundle)
            return String(localized: resource)
        }
        #expect(dialog(count: 1) == "1 Lorvex task tagged work: Plan, ship")
        #expect(dialog(count: 2) == "2 Lorvex tasks tagged work: Plan, ship")
    }

    @Test("Siri reads a task's status as one whole sentence in the request language")
    func readTaskDialogIsOneSentencePerStatus() {
        func dialog(_ status: LorvexTask.Status, _ language: String) -> String {
            var resource = ReadLorvexTaskIntent.dialog(title: "Pay rent", status: status)
            resource.locale = Locale(identifier: language)
            return String(localized: resource)
        }
        #expect(dialog(.open, "en") == "Pay rent is still open.")
        #expect(dialog(.inProgress, "en") == "Pay rent is in progress.")
        #expect(dialog(.completed, "en") == "Pay rent is done.")
        #expect(dialog(.cancelled, "es") == "La tarea “Pay rent” se canceló.")
        #expect(dialog(.someday, "zh-Hans") == "“Pay rent”放在“将来某天”里。")
    }

    @Test("Production plural call sites use native interpolation, not a custom runtime")
    func productionPluralCallSitesUseNativeInterpolation() throws {
        let root = try #require(Self.packageRootURL())
        let sources = root.appending(path: "Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))
        let forbidden = ["pluralString(", "lorvexPlural(", ".plural(", ".catalogPlural("]
        var swiftFileCount = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            swiftFileCount += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still routes plural text through custom runtime marker \(marker)")
            }
        }
        #expect(swiftFileCount > 0)
    }

    @Test("Apple uses native bundle-qualified String-Catalog lookups")
    func appleUsesNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexApple")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))
        let forbidden = [
            "LorvexL10n.catalog.",
            "LorvexLocalizedCatalog(",
        ]
        var nativeReferenceCount = 0
        var swiftFileCount = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            swiftFileCount += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired Apple localization marker \(marker)")
            }
            #expect(
                source.range(
                    of: #"\.lorvex\s*\(\s*key:"#,
                    options: .regularExpression) == nil,
                "\(file.lastPathComponent) still uses the retired .lorvex localization factory")
            nativeReferenceCount += source.components(
                separatedBy: "bundle: LorvexL10n.bundle"
            ).count - 1
        }
        #expect(swiftFileCount > 0)
        #expect(nativeReferenceCount > 0, "Expected native Apple catalog references")
    }

    @Test("Mobile uses native bundle-qualified String-Catalog lookups")
    func mobileUsesNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexMobile")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))
        let forbidden = [
            "MobileL10n.string(",
            "MobileL10n.text(",
            "MobileL10n.resource(",
            "MobileL10n.catalog.",
            "LorvexLocalizedCatalog(",
        ]
        var nativeReferenceCount = 0
        var swiftFileCount = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            swiftFileCount += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired Mobile localization marker \(marker)")
            }
            nativeReferenceCount += source.components(
                separatedBy: "bundle: MobileL10n.bundle"
            ).count - 1
        }
        #expect(swiftFileCount > 0)
        #expect(nativeReferenceCount > 0, "Expected native Mobile catalog references")
    }

    @Test("Notification localization remains eager and module-owned")
    func notificationLocalizationRemainsEagerAndModuleOwned() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexMobile")
        let providers = [
            "MobileTaskReminderStrings.swift",
            "MobileHabitReminderStrings.swift",
            "MobileSnoozeNotificationStrings.swift",
        ]

        for provider in providers {
            let source = try String(
                contentsOf: sourceRoot.appending(path: provider),
                encoding: .utf8)
            #expect(
                source.range(
                    of: #"String\s*\(\s*localized:"#,
                    options: .regularExpression) != nil,
                "\(provider) must resolve eagerly")
            #expect(
                source.contains("table: \"Localizable\"")
                    && source.contains("bundle: MobileL10n.bundle"),
                "\(provider) must use the Mobile catalog explicitly")
            #expect(
                !source.contains("LocalizedStringResource("),
                "\(provider) must return notification-ready String values")
        }
    }

    @Test("WidgetViews uses native bundle-qualified String-Catalog lookups")
    func widgetViewsUsesNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexWidgetViews")
        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty)

        let forbidden = [
            "WidgetL10n.string(",
            "WidgetL10n.text(",
            "WidgetL10n.resource(",
            "LorvexLocalizedCatalog(",
        ]
        var nativeReferenceCount = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired WidgetViews localization marker \(marker)")
            }
            nativeReferenceCount += source.components(
                separatedBy: "bundle: WidgetL10n.bundle"
            ).count - 1
        }
        #expect(nativeReferenceCount > 0, "Expected native WidgetViews catalog references")
    }

    @Test("Widget support surfaces use native bundle-qualified String-Catalog lookups")
    func widgetSupportSurfacesUseNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoots = [
            root.appending(path: "Sources/LorvexWidgetKitSupport"),
            root.appending(path: "Sources/LorvexWidgetExtension"),
            root.appending(path: "Sources/LorvexWatch"),
            root.appending(path: "Sources/LorvexWidgetIntents"),
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot in
            try FileManager.default.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "swift" }
        }
        #expect(!swiftFiles.isEmpty)

        let forbidden = [
            "WidgetSupportL10n.string(",
            "WidgetSupportL10n.text(",
            "WidgetSupportL10n.resource(",
            "WidgetSupportL10n.catalog.",
            "WidgetConfigL10n",
        ]
        var nativeReferenceCount = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired widget localization marker \(marker)")
            }
            if !file.pathComponents.contains("LorvexWatch") {
                #expect(
                    !source.contains("LorvexLocalizedCatalog("),
                    "\(file.lastPathComponent) still constructs the retired WidgetSupport catalog reader")
            }
            nativeReferenceCount += source.components(
                separatedBy: "bundle: WidgetSupportL10n.bundle"
            ).count - 1
        }
        #expect(nativeReferenceCount > 0, "Expected native WidgetSupport catalog references")
    }

    @Test("Watch uses native bundle-qualified String-Catalog lookups")
    func watchUsesNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexWatch")
        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty)

        let forbidden = [
            "WatchL10n.string(",
            "WatchL10n.text(",
            "WatchL10n.resource(",
            "WatchL10n.catalog.",
            "LorvexLocalizedCatalog(",
        ]
        var nativeReferenceCount = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired Watch localization marker \(marker)")
            }
            nativeReferenceCount += source.components(
                separatedBy: "bundle: WatchL10n.bundle"
            ).count - 1
        }
        #expect(nativeReferenceCount > 0, "Expected native Watch catalog references")
    }

    @Test("System Intents uses native bundle-qualified String-Catalog lookups")
    func systemIntentsUsesNativeBundleQualifiedLookups() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexSystemIntents")
        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty)

        let forbidden = [
            "SystemL10n.string(",
            "SystemL10n.text(",
            "SystemL10n.resource(",
            "SystemL10n.catalog.",
            "LorvexLocalizedCatalog(",
        ]
        var nativeReferenceCount = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbidden {
                #expect(
                    !source.contains(marker),
                    "\(file.lastPathComponent) still uses retired System Intents localization marker \(marker)")
            }
            nativeReferenceCount += source.components(
                separatedBy: "bundle: SystemL10n.bundle"
            ).count - 1
        }
        #expect(nativeReferenceCount > 0, "Expected native System Intents catalog references")

        let focusFilterSource = try String(
            contentsOf: sourceRoot.appending(path: "LorvexFocusFilterIntent.swift"),
            encoding: .utf8)
        for key in [
            "system.focus_filter.entity.list", "system.focus_filter.all_lists",
            "system.focus_filter.parameter.lists",
        ] {
            #expect(
                focusFilterSource.contains("\"\(key)\""),
                "The Focus filter must read \(key) from the System Intents catalog")
        }
    }

    @Test("Widget gallery metadata stays deferred and bundle-qualified")
    func widgetGalleryMetadataStaysDeferredAndBundleQualified() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoot = root.appending(path: "Sources/LorvexWidgetExtension")
        let widgets = [
            (
                file: "LorvexTodayWidget.swift",
                nameKey: "widget.today.name",
                descriptionKey: "widget.today.desc"
            ),
            (
                file: "LorvexHabitsWidget.swift",
                nameKey: "widget.habits.name",
                descriptionKey: "widget.habits.desc"
            ),
            (
                file: "LorvexProgressWidget.swift",
                nameKey: "widget.progress.name",
                descriptionKey: "widget.progress.desc"
            ),
        ]

        for widget in widgets {
            let source = try String(
                contentsOf: sourceRoot.appending(path: widget.file),
                encoding: .utf8)
            let collapsed = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(
                collapsed.contains(".configurationDisplayName( LocalizedStringResource("),
                "\(widget.file) must defer its gallery display name through LocalizedStringResource")
            #expect(
                collapsed.contains(".description( LocalizedStringResource("),
                "\(widget.file) must defer its gallery description through LocalizedStringResource")
            #expect(source.contains("\"\(widget.nameKey)\""))
            #expect(source.contains("\"\(widget.descriptionKey)\""))
            #expect(
                source.components(separatedBy: "bundle: WidgetSupportL10n.bundle").count - 1 >= 2,
                "\(widget.file) must explicitly bind both gallery resources to WidgetSupportL10n.bundle")
        }
    }

    @Test("Native Today widget metadata resolves a non-English catalog value")
    func nativeTodayWidgetMetadataResolvesNonEnglishValue() throws {
        let simplifiedChinese = try #require(
            WidgetSupportL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })

        #expect(
            String(
                localized: "widget.today.name",
                defaultValue: "Today",
                table: "Localizable",
                bundle: simplifiedChinese
            ) == "今天")
        #expect(
            String(
                localized: "widget.today.desc",
                defaultValue: "See today's tasks at a glance.",
                table: "Localizable",
                bundle: simplifiedChinese
            ) == "一眼查看今天的任务。")
    }

    @Test("Watch complication metadata stays deferred and bundle-qualified")
    func watchComplicationMetadataStaysDeferredAndBundleQualified() throws {
        let root = try #require(Self.packageRootURL())
        let file = root.appending(
            path: "Sources/LorvexWatch/LorvexWatchComplicationWidget.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let collapsed = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        #expect(
            collapsed.contains(".configurationDisplayName(LocalizedStringResource("),
            "Watch complication must defer its gallery display name through LocalizedStringResource")
        #expect(
            collapsed.contains(".description(LocalizedStringResource("),
            "Watch complication must defer its gallery description through LocalizedStringResource")
        #expect(source.contains("\"watch.complication.name\""))
        #expect(source.contains("\"watch.complication.description\""))
        #expect(
            source.components(separatedBy: "bundle: WatchL10n.bundle").count - 1 >= 2,
            "Watch complication must explicitly bind both gallery resources to WatchL10n.bundle")
    }

    @Test("Native Watch metadata resolves a non-English catalog value")
    func nativeWatchMetadataResolvesNonEnglishValue() throws {
        let simplifiedChinese = try #require(
            WatchL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })

        #expect(
            String(
                localized: "watch.complication.description",
                defaultValue: "Shows how many tasks are left today and the one at the top.",
                table: "Localizable",
                bundle: simplifiedChinese
            ) == "显示今天还剩几项任务，以及排在最前面的一项。")
    }

    @Test("Native WidgetViews interpolation preserves plural categories and argument order")
    func nativeWidgetViewsInterpolationPreservesPluralCategoriesAndArguments() throws {
        func languageBundle(_ language: String) throws -> Bundle {
            try #require(
                WidgetL10n.bundle.url(forResource: language, withExtension: "lproj")
                .flatMap { Bundle(url: $0) })
        }

        let english = try languageBundle("en")
        func habitProgress(done: Int, total: Int) -> String {
            String(
                localized: "widget.habits.circular.a11y",
                defaultValue: "\(done) of \(total) habits done",
                table: "Localizable",
                bundle: english)
        }
        #expect(habitProgress(done: 1, total: 1) == "1 of 1 habit done")
        #expect(habitProgress(done: 1, total: 2) == "1 of 2 habits done")

        func inlineProgress(completed: Int, total: Int) -> String {
            String(
                localized: "widget.progress.inline",
                defaultValue: "\(completed)/\(total) tasks",
                table: "Localizable",
                bundle: english)
        }
        #expect(inlineProgress(completed: 1, total: 1) == "1/1 task")
        #expect(inlineProgress(completed: 1, total: 2) == "1/2 tasks")

        let simplifiedChinese = try languageBundle("zh-Hans")
        let hidden = 3
        let done = 2
        #expect(
            String(
                localized: "widget.foot.more_today",
                defaultValue: "\(hidden) more today",
                table: "Localizable",
                bundle: simplifiedChinese) == "另有 3\u{00A0}项")
        #expect(
            String(
                localized: "widget.foot.done_today",
                defaultValue: "\(done) done today",
                table: "Localizable",
                bundle: simplifiedChinese) == "今天已完成 2\u{00A0}项")

        let title = "Write"
        let action = String(
            localized: "widget.action.complete.a11y",
            defaultValue: "Complete \(title)",
            table: "Localizable",
            bundle: simplifiedChinese)
        #expect(action == "完成“Write”")
    }

    /// Guards the App-Intent request-locale seam. A composed process-locale
    /// `String` is no safer than an inline helper lookup: either one freezes the
    /// wrong language before Siri or Shortcuts can resolve the request locale.
    /// Every production dialog therefore carries a deferred
    /// `LocalizedStringResource`; `IntentDialog(stringLiteral:)` has no allowed
    /// production use in either intent target.
    @Test("Every App-Intent dialog defers to the request locale")
    func appIntentDialogsUseRequestLocaleResources() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoots = [
            root.appending(path: "Sources/LorvexSystemIntents"),
            root.appending(path: "Sources/LorvexWidgetIntents"),
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot in
            try FileManager.default.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
        }
        #expect(!swiftFiles.isEmpty)

        var dialogConstructions = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let compact = source.filter { !$0.isWhitespace }
            #expect(
                !compact.contains("IntentDialog(stringLiteral:"),
                "\(file.lastPathComponent): IntentDialog(stringLiteral:) resolves before the App-Intent request locale; use a bundle-qualified LocalizedStringResource"
            )
            dialogConstructions += source.components(separatedBy: "IntentDialog(").count - 1
        }
        #expect(dialogConstructions > 0, "Expected IntentDialog constructions across the intent targets")
    }

    @Test("Batch task dialogs retain operation-specific deferred result summaries")
    func batchTaskDialogsRetainOperationSpecificDeferredResultSummaries() throws {
        let root = try #require(Self.packageRootURL())
        let cases = [
            ("BatchCompleteLorvexTasksIntent.swift", "system.task.batch.complete.dialog"),
            ("BatchDeferLorvexTasksIntent.swift", "system.task.batch.defer.dialog"),
            ("BatchReopenLorvexTasksIntent.swift", "system.task.batch.reopen.dialog"),
        ]

        for (fileName, key) in cases {
            let file = root.appending(path: "Sources/LorvexSystemIntents/\(fileName)")
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("\"\(key)\""), "\(fileName) must own its operation-specific dialog key")
            #expect(
                source.contains("result.changedIDs.count"),
                "\(fileName) must report the number of tasks actually changed")
            #expect(
                source.contains("result.skipped.count"),
                "\(fileName) must report skipped task IDs rather than implying total success")
            #expect(
                source.contains("bundle: SystemL10n.bundle"),
                "\(fileName) must defer its dialog through the System Intents bundle")
        }
    }

    @Test("App Intent metadata stays extractor-compatible")
    func appIntentMetadataUsesStaticMainBundleResources() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoots = [
            root.appending(path: "Sources/LorvexWidgetExtension"),
            root.appending(path: "Sources/LorvexWidgetIntents"),
            root.appending(path: "Sources/LorvexSystemIntents"),
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot in
            try FileManager.default.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
        }

        #expect(!swiftFiles.isEmpty)
        let forbiddenMarkers = [
            "SystemL10n.resource(",
            "WidgetSupportL10n.resource(",
            "WidgetL10n.resource(",
            "static var title",
            "static var description",
            "static var typeDisplayRepresentation",
            "static var caseDisplayRepresentations",
        ]
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in forbiddenMarkers {
                #expect(!source.contains(marker), "\(file.lastPathComponent) contains extractor-unsafe metadata marker: \(marker)")
            }
        }
    }

    // L10n-H1 regression guard: `LocalizedStringResource` defaults `bundle`
    // to `.main`, which is the host app, not the module that owns the
    // catalog — every construction in these directories must carry an
    // explicit `bundle:` argument (a plain `Bundle`/`BundleDescription`
    // value passed to the literal initializer, never a wrapper function —
    // see `appIntentMetadataUsesStaticMainBundleResources` above) or
    // Siri/Shortcuts/widget metadata silently falls back to English. Every
    // call site in this codebase writes `table: "Localizable"` immediately
    // before `bundle:`, so a call ending in `table: "Localizable")` with no
    // `bundle:` argument is exactly the regression this guards against.
    @Test("Every App Intent / widget LocalizedStringResource specifies an explicit bundle")
    func appIntentAndWidgetResourcesAlwaysSpecifyBundle() throws {
        let root = try #require(Self.packageRootURL())
        let sourceRoots = [
            root.appending(path: "Sources/LorvexWidgetExtension"),
            root.appending(path: "Sources/LorvexWidgetIntents"),
            root.appending(path: "Sources/LorvexSystemIntents"),
            root.appending(path: "Sources/LorvexWatch"),
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot in
            try FileManager.default.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
        }

        #expect(!swiftFiles.isEmpty)
        var totalCalls = 0
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            totalCalls += source.components(separatedBy: "LocalizedStringResource(").count - 1
            #expect(
                !source.contains("table: \"Localizable\")"),
                "\(file.lastPathComponent) has a LocalizedStringResource(...) call ending right after table:, with no bundle: argument"
            )
        }
        #expect(totalCalls > 0, "Expected at least one LocalizedStringResource( construction across these directories")
    }

    /// Returns the Simplified Chinese translation `bundle` ships for `key`, read
    /// from its compiled `zh-Hans.lproj/Localizable.strings`, or `nil` when the
    /// bundle ships no Simplified Chinese table or the table omits the key.
    ///
    /// Reading the compiled table is what makes a negative result meaningful: it
    /// says the module genuinely cannot resolve the key at runtime, not merely
    /// that some authored file is missing.
    private func simplifiedChineseCatalogValue(in bundle: Bundle, key: String) throws -> String? {
        guard let lproj = bundle.url(forResource: "zh-Hans", withExtension: "lproj") else {
            return nil
        }
        let table = lproj.appending(path: "Localizable.strings")
        guard FileManager.default.fileExists(atPath: table.path) else { return nil }
        return try loadInfoPlistStrings(table)[key]
    }

    @Test("Representative intent / widget-config resources resolve their own module bundle, not the main bundle")
    func appIntentAndWidgetConfigResourcesResolveModuleBundle() throws {
        // Mirrors the audit's own probe (L10n-H1): a lookup against the main
        // app bundle finds only the English default because LorvexApple's own
        // catalog never defines these module-owned keys, while a lookup
        // against the correct module bundle finds the zh-Hans translation.
        // One representative per fixed module: an intent title
        // (LorvexSystemIntents), a widget intent title (LorvexWidgetIntents),
        // and a widget-config title (LorvexWidgetExtension).
        struct Representative {
            let name: String
            let resource: LocalizedStringResource
            let moduleBundle: Bundle
            let key: String
            let defaultValue: String
            let expectedSimplifiedChinese: String
        }

        let representatives = [
            Representative(
                name: "LorvexSystemIntents intent title",
                resource: CompleteLorvexTaskIntent.title,
                moduleBundle: SystemL10n.bundle,
                key: "system.task.complete.title",
                defaultValue: "Complete Lorvex Task",
                expectedSimplifiedChinese: "完成 Lorvex 任务"),
            Representative(
                name: "LorvexWidgetIntents widget intent title",
                resource: WidgetCompleteTaskIntent.title,
                moduleBundle: WidgetSupportL10n.bundle,
                key: "widget.intent.complete.title",
                defaultValue: "Complete Task",
                expectedSimplifiedChinese: "完成任务"),
            Representative(
                name: "LorvexWidgetExtension widget-config title",
                resource: LorvexTodayWidgetConfigurationIntent.title,
                moduleBundle: WidgetL10n.bundle,
                key: "widget.config.today.title",
                defaultValue: "Today",
                expectedSimplifiedChinese: "今天"),
        ]

        for representative in representatives {
            guard case .atURL(let resourceBundleURL) = representative.resource.bundle else {
                Issue.record("\(representative.name): expected an explicit module bundle URL, not \(representative.resource.bundle)")
                continue
            }
            #expect(
                resourceBundleURL == representative.moduleBundle.bundleURL,
                "\(representative.name) should carry its own module bundle instead of defaulting to .main"
            )

            let moduleSimplifiedChinese = try simplifiedChineseCatalogValue(in: representative.moduleBundle, key: representative.key)
            #expect(
                moduleSimplifiedChinese == representative.expectedSimplifiedChinese,
                "\(representative.name): expected the zh-Hans catalog translation for '\(representative.key)' from its module bundle"
            )
            #expect(moduleSimplifiedChinese != representative.defaultValue)

            // Contrast: the main app bundle's own catalog never defines this
            // module-owned key, so a lookup there would have fallen through
            // to the English default before this fix.
            let mainSimplifiedChinese = try simplifiedChineseCatalogValue(in: Bundle.main, key: representative.key)
            #expect(
                mainSimplifiedChinese == nil,
                "\(representative.name): the main bundle catalog should not own '\(representative.key)'"
            )
        }
    }

    @Test("Widget-config keys resolve to a non-English translation from the owning module bundle")
    func widgetConfigKeysResolveNonEnglishFromOwningBundle() throws {
        // Proves the resolved bundle carries real translations rather than only
        // the English source default — the exact failure when bundle resolution
        // misses the LorvexWidgetViews catalog.
        let simplifiedChinese = try simplifiedChineseCatalogValue(
            in: WidgetL10n.bundle, key: "widget.config.today.title")
        #expect(simplifiedChinese == "今天")
        #expect(simplifiedChinese != "Today")
    }

    @Test("Native System Intents lookup resolves a non-English compiled catalog")
    func nativeSystemIntentLookupResolvesNonEnglishValue() throws {
        let simplifiedChinese = try #require(
            SystemL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj")
                .flatMap { Bundle(url: $0) })
        let completed = 1
        let target = 2
        let progress = String(
            localized: "system.entity.habit.progress.today",
            defaultValue: "\(completed)/\(target) today",
            table: "Localizable",
            bundle: simplifiedChinese)

        #expect(progress == "今日 1/2")
    }

    private struct ShippedCatalog {
        let name: String
        var url: URL? { LocalizationTests.sourceCatalogURL(name) }
    }

    private func shippedCatalogs() throws -> [ShippedCatalog] {
        [
            ShippedCatalog(name: "LorvexApple"),
            ShippedCatalog(name: "LorvexMobile"),
            ShippedCatalog(name: "LorvexSystemIntents"),
            ShippedCatalog(name: "LorvexWatch"),
            ShippedCatalog(name: "LorvexWidgetKitSupport"),
            ShippedCatalog(name: "LorvexWidgetViews"),
            ShippedCatalog(name: "LorvexCarPlay"),
        ]
    }

    private func shippedModuleCatalogs() throws -> [ShippedCatalog] {
        Array(try shippedCatalogs().dropFirst())
    }

    private func shippedCatalogLanguageIDs() throws -> [String] {
        var languages: Set<String> = []
        for catalog in try shippedCatalogs() {
            languages.formUnion(try catalogLanguageIDs(catalog.url))
        }
        return languages.sorted()
    }

    private func shippedCatalogSourceLanguages() throws -> [String] {
        var languages: Set<String> = []
        for catalog in try shippedCatalogs() {
            let json = try loadCatalog(catalog.url)
            let sourceLanguage = try #require(
                json["sourceLanguage"] as? String,
                "\(catalog.name) catalog missing sourceLanguage"
            )
            languages.insert(sourceLanguage)
        }
        return languages.sorted()
    }

    /// The authored catalog for a module, located in the source tree by the
    /// module's `Sources/` directory name. The build product carries only the
    /// compiled `.lproj` tables, so an assertion about catalog structure —
    /// source language, key coverage, extraction state — reads the file here.
    private static func sourceCatalogURL(_ module: String) -> URL? {
        packageRootURL()?
            .appendingPathComponent("Sources/\(module)/Resources/Localizable.xcstrings")
    }

    private struct ShippedBundle {
        let name: String
        let bundle: Bundle
    }

    /// The resource bundle each localized module ships. A module's authored
    /// catalog is compiled into `<language>.lproj/Localizable.strings` here, so
    /// this is what an assertion about a delivered build reads.
    private static func shippedBundles() -> [ShippedBundle] {
        [
            ShippedBundle(name: "LorvexApple", bundle: LorvexL10n.bundle),
            ShippedBundle(name: "LorvexMobile", bundle: MobileL10n.bundle),
            ShippedBundle(name: "LorvexSystemIntents", bundle: SystemL10n.bundle),
            ShippedBundle(name: "LorvexWatch", bundle: WatchL10n.bundle),
            ShippedBundle(name: "LorvexWidgetKitSupport", bundle: WidgetSupportL10n.bundle),
            ShippedBundle(name: "LorvexWidgetViews", bundle: WidgetL10n.bundle),
            ShippedBundle(name: "LorvexCarPlay", bundle: CarPlayL10n.bundle),
            ShippedBundle(name: "LorvexCore", bundle: CoreL10n.bundle),
        ]
    }

    private static func packageRootURL() -> URL? {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizedInfoPlistKeys(in plist: [String: Any]) -> [String] {
        var keys = Set<String>()
        for key in [
            "CFBundleDisplayName",
            "CFBundleName",
        ] where plist[key] is String {
            keys.insert(key)
        }

        let shortcutItems = plist["UIApplicationShortcutItems"] as? [[String: Any]] ?? []
        for item in shortcutItems {
            for key in ["UIApplicationShortcutItemTitle", "UIApplicationShortcutItemSubtitle"] {
                if let value = item[key] as? String {
                    keys.insert(value)
                }
            }
        }
        return keys.sorted()
    }

    private func loadInfoPlistStrings(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            "\(url.path) is not a string table"
        )
    }
}
