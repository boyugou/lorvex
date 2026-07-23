# Numeric/count grammar follow-up — Apple String Catalogs

This plan tracks the one open localization work item: making the flat numeric
format keys in the Apple catalogs grammatically correct across the 13-language
set. Runtime localization is fully native (see `../LOCALIZATION.md` for the
current architecture); native interpolation alone preserves a flat entry's
existing grammar, so each key below needs the disposition recorded for it. The
validation contracts at the end govern how this work is proven.

## Open semantic follow-up — Apple numeric/count grammar

This follow-up is independent of the completed native-runtime migration. A
source-and-catalog audit found **54 direct flat numeric-printf calls covering 50
unique Apple keys**. At the audit point, all 50 corresponding entries in
`Sources/LorvexApple/Resources/Localizable.xcstrings` were flat `stringUnit`
entries. Replacing `String(format:)` with native interpolation alone preserves
their existing grammar; it does not create plural variations.

The disposition is:

- **13 plural/split keys.** These need a native plural variation or a split into
  independently pluralized phrases: `a11y.list.format`,
  `a11y.task.minutes_format`, `calendar.all_day.more.a11y`,
  `calendar.overflow.more_events.a11y`, `habit.heatmap.a11y.summary`,
  `habits.heatmap.summary_a11y`,
  `habits.milestone.value.streak_days`,
  `habits.milestone.value.streak_weeks`,
  `habits.milestone.value.streak_months`,
  `habits.reminders.window.preview`, `recurrence.summary.interval`,
  `settings.activity.retention.days.custom`, and
  `settings.data_import.summary.more_errors_count`. The two heatmap summaries
  contain multiple independent counts and must be split rather than assigned
  one arbitrary plural selector. `recurrence.summary.interval` must become
  frequency-specific whole-clause plurals instead of composing a number with a
  separately translated plural unit. Representative call sites are
  `Views/HabitHeatmapStatsLine.swift`, `Views/HabitHeatmapView.swift`,
  `Views/HabitReminderEditorSupport.swift`,
  `Support/TaskRecurrenceLocalization.swift`, and
  `Views/CalendarEventRepeatField.swift`.
- **16 count-neutral rewrites.** These currently imply an inflected noun or
  adjective in several translations; prefer a label-plus-number form such as
  `Selected: N`, `Open: N`, or `Requested: N` instead of multiplying plural
  branches: `focus.selection.count`, `tasks.selection.count`,
  `habits.row.today_progress_a11y`, `habits.row.total_metric`,
  `habits.summary.on_track`, `list_detail.count.matching`,
  `list_detail.count.shown_next_page`, `list_detail.summary`,
  `list_row.counts`, `menubar.due_count`, `recurrence.summary.skipped`,
  `reviews.weekly.task.deferred_count`,
  `settings.data_import.summary.category_imported_count`,
  `settings.diagnostics.reminder_requests.detail`,
  `sidebar.list_scope.done_count`, and `today.header.overdue_count`.
  Evidence is concentrated in `Views/ListDetailPane.swift`,
  `Views/ListCatalogRow.swift`, `Views/TodayHeaderView.swift`,
  `Views/SettingsDiagnosticsSection.swift`, and
  `Support/DataImportExportLocalization.swift`.
- **2 compact duration-unit entries need an explicit policy:**
  `common.duration.days_short` and `common.duration.months_short` in
  `Support/LorvexDurationLabel.swift`. Either every locale must use a genuinely
  invariant abbreviation, or the catalog must carry plural forms; the current
  flat Polish day and Italian month values are not valid for `1`.
- **18 count-neutral calls are mechanical native-interpolation migrations:**
  `common.duration.minutes_short`, `common.duration.weeks_short`,
  `habits.milestone.next`, `habits.milestone.progress_a11y`,
  `habits.reminders.hint.monthly`, `habits.reminders.hint.multi`,
  `habits.reminders.hint.times_per_week`, `habits.requirement.month_day`,
  `habits.requirement.per_day`, `habits.requirement.per_week`,
  `habits.requirement.per_month`, `habits.row.progress_meter_a11y`,
  `habits.sheet.cadence.month_day_label`,
  `habits.sheet.cadence.spread_n_days`,
  `reviews.daily.rating_accessibility`,
  `task_detail.notes.character_limit`, `today.header.todo_count`, and
  `today.header.focused_count`.
- The fiftieth key, `settings.data_import.summary.category_skipped_count`, is a
  raw numeric component whose entry is count-neutral, but its call must migrate
  with `settings.data_import.summary.category_imported_with_skipped`; otherwise
  the surrounding fixed-plural “skipped” adjective remains wrong for one item.

Do not mark this section complete until the catalog variations/wording and
non-English singular/few/many tests land. The completed L2 native-API gate and
this semantic grammar gate are deliberately separate claims.

## Code-only validation boundary

The gate's catalog-compilation step followed by `swift test` proves real
per-language resolution and native plural categories by loading a specific
`.lproj` sub-bundle (the `locale:` argument only affects number/date formatting,
never table selection — force language via the bundle). When running a focused
raw `swift test` manually, run `./script/compile_xcstrings.sh` first.
`verify_all.sh` + the XcodeGen Release-link leg prove both build systems compile
the migrated sources against the macOS-26 SDK and stage the catalogs. None of the
code-only gates prove on-device rendering (truncation, RTL mirroring, Dynamic
Type, live Siri/widget-gallery metadata) — that is the host-required tier of L5
(pseudolanguage + screenshot matrix), which stays a manual pre-release checklist,
not wired into the gate. In particular, the live Widget Gallery presentation of
the four deferred name/description pairs and the Watch complication-gallery
name/description remains a manual L5 check even though their catalog ownership,
language completeness, and source wiring are gated.

## Invariants to preserve

- Every framework string passes its owning `bundle:` explicitly (the L1 fix;
  guarded by `appIntentAndWidgetResourcesAlwaysSpecifyBundle`).
- App-Intent metadata stays a static `LocalizedStringResource` literal (extractor
  requirement; guarded by `appIntentMetadataUsesStaticMainBundleResources`).
- The verifier's per-module "referenced count > 0" assertion must survive each
  scanner retarget, so a silently-empty scan fails instead of passing a missing
  key. The merged scan covers legacy helpers, bundle-qualified native
  `String(localized:)`, native `Text`, and bundle-owned
  `LocalizedStringResource`; resource references never count toward the wrong
  catalog merely because another catalog uses the same key.
