import AppIntents

/// Registers Lorvex's flagship App Shortcuts with the system.
///
/// The system only surfaces a small number of an app's `AppShortcut`s (about
/// ten) in Spotlight, the Shortcuts app, and Siri, and the App Intents metadata
/// processor warns once that budget is exceeded. This provider therefore
/// registers a curated set of the highest-value entry points.
///
/// Curation applies only to the auto-registered shortcut phrases. Every other
/// `AppIntent` in `LorvexSystemIntents` stays fully invokable — a user can still
/// add it to a shortcut, run it from the Shortcuts app, or trigger it from an
/// automation. `SYSTEM_INTENTS_ACTIONS` in `script/release_strategy.py` mirrors
/// this registered set and is enforced against it by
/// `script/verify_system_entrypoints.py`.
///
/// Localization uses the two mechanisms App Intents provides, because the two
/// arguments have different types:
/// - `shortTitle` is a `LocalizedStringResource`, so it routes through the
///   module catalog (`table: "Localizable", bundle: SystemL10n.bundle`) exactly
///   like every intent `title` — the request-locale seam in `docs/LOCALIZATION.md`.
/// - `phrases` are `AppShortcutPhrase` values, a distinct type that cannot carry
///   a `table:`/`bundle:` argument. The App Intents metadata extractor localizes
///   them through a separate, specially-named `AppShortcuts.xcstrings`
///   (`Resources/AppShortcuts.xcstrings`), keyed by the English phrase with the
///   literal `${applicationName}` token — never through `Localizable.xcstrings`.
///   The catalog compiles to `AppShortcuts.strings` beside the metadata: Xcode's
///   `ExtractAppIntentsMetadata` phase writes both on iOS, and macOS release
///   staging (`script/extract_app_intents_metadata.py`) writes both into the
///   app bundle. No Swift code references its keys,
///   so `script/verify_localization_catalog.py` checks it on its own: every
///   phrase and translation names the app exactly once, and every shipped
///   language translates every phrase.
struct LorvexShortcutsProvider: AppShortcutsProvider {
  static let shortcutTileColor: ShortcutTileColor = .blue

  static var appShortcuts: [AppShortcut] {
    // Explicit `return` of an array opts out of the `@AppShortcutsBuilder`
    // result builder (which would treat the literal as one component).
    return [
      AppShortcut(
        intent: CaptureLorvexTaskIntent(),
        phrases: [
          "Capture a task in \(.applicationName)",
          "Add a task to \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.capture.short_title", defaultValue: "Capture Task", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "plus"
      ),
      AppShortcut(
        intent: OpenLorvexIntent(destination: .today),
        phrases: [
          "Open \(.applicationName)",
          "Open today in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.open.short_title", defaultValue: "Open Lorvex", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "sun.max"
      ),
      AppShortcut(
        intent: ReadLorvexOverviewIntent(),
        phrases: [
          "Read overview in \(.applicationName)",
          "Show Lorvex overview in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.overview.short_title", defaultValue: "Overview", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "rectangle.3.group"
      ),
      AppShortcut(
        intent: CompleteLorvexTaskIntent(),
        phrases: [
          "Complete a task in \(.applicationName)",
          "Mark a task done in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.complete.short_title", defaultValue: "Complete Task", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "checkmark.circle"
      ),
      AppShortcut(
        intent: DeferLorvexTaskIntent(),
        phrases: [
          "Defer a task in \(.applicationName)",
          "Schedule a task for tomorrow in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.defer.short_title", defaultValue: "Defer Task", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "calendar.badge.clock"
      ),
      AppShortcut(
        intent: PlanLorvexTaskForTodayIntent(),
        phrases: [
          "Plan a task for today in \(.applicationName)",
          "Move a task to today in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.plan_today.short_title", defaultValue: "Plan for Today", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "sun.max.circle"
      ),
      AppShortcut(
        intent: ListLorvexTasksIntent(),
        phrases: ["List tasks in \(.applicationName)"],
        shortTitle: LocalizedStringResource("system.shortcut.list.short_title", defaultValue: "List Tasks", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "list.bullet.rectangle"
      ),
      AppShortcut(
        intent: SearchLorvexTasksIntent(),
        phrases: ["Search tasks in \(.applicationName)"],
        shortTitle: LocalizedStringResource("system.shortcut.search.short_title", defaultValue: "Search Tasks", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "text.magnifyingglass"
      ),
      AppShortcut(
        intent: CreateLorvexHabitIntent(),
        phrases: [
          "Create habit in \(.applicationName)",
          "Add habit in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.create_habit.short_title", defaultValue: "Create Habit", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "repeat.circle"
      ),
      AppShortcut(
        intent: ReadLorvexWeeklyReviewIntent(),
        phrases: [
          "Read weekly review in \(.applicationName)",
          "Show weekly review in \(.applicationName)",
        ],
        shortTitle: LocalizedStringResource("system.shortcut.weekly_review.short_title", defaultValue: "Weekly Review", table: "Localizable", bundle: SystemL10n.bundle),
        systemImageName: "calendar.badge.checkmark"
      ),
    ]
  }
}
