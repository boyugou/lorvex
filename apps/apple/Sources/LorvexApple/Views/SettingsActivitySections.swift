import LorvexCore
import LorvexDomain
import SwiftUI

extension SettingsView {
  var logsSection: some View {
    Section(String(localized: "settings.activity.recent_logs", defaultValue: "Recent Logs", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsActivityFeed(
        count: store.runtimeDiagnostics?.recentLogs.entries.count ?? 0,
        accessibilityIdentifier: "settings.activity.logsToggle"
      ) {
        ForEach(store.runtimeDiagnostics?.recentLogs.entries ?? []) { entry in
          RuntimeEntryRow(
            // `origin` carries per-row provenance (the `error_logs.source`
            // column, e.g. `metrickit.crash`); the stream-level `source`
            // collapses every error_log row to `error_log`, so prefer the
            // finer origin when present to label crash/hang/sync rows apart.
            title: entry.summary,
            subtitle: "\(entry.origin ?? entry.source) · \(entry.level.rawValue)",
            timestamp: entry.timestamp
          )
        }
      } empty: {
        LorvexEmptyStatePanel(
          title: String(localized: "settings.activity.no_recent_logs.title", defaultValue: "No recent logs", table: "Localizable", bundle: LorvexL10n.bundle),
          message: String(
            localized: "settings.activity.no_recent_logs",
            defaultValue: "No recent logs loaded.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: "doc.text.magnifyingglass",
          tint: .secondary,
          style: .inline
        )
      }
    }
  }
}

/// The rows of a diagnostics feed in Settings › Diagnostics, folded by
/// default: one disclosure row naming how many of the newest entries it holds
/// (the panel loads only the newest few, never the whole log), and the
/// entries only once the user opens it. Even that slice is a list a person
/// reads only while troubleshooting, so unfolded it would push every section
/// after it down. An empty feed shows `empty` directly, with nothing to fold.
/// The caller wraps the rows in its section.
private struct SettingsActivityFeed<Rows: View, Empty: View>: View {
  let count: Int
  let accessibilityIdentifier: String
  @ViewBuilder let rows: () -> Rows
  @ViewBuilder let empty: () -> Empty
  @State private var isExpanded = false

  var body: some View {
    if count == 0 {
      empty()
    } else {
      SettingsAdvancedDisclosureButton(
        isExpanded: $isExpanded,
        title: LocalizedStringResource(
          "settings.activity.latest_entry_count", defaultValue: "Latest Entries (\(count))",
          table: "Localizable", bundle: LorvexL10n.bundle),
        accessibilityIdentifier: accessibilityIdentifier)
      if isExpanded {
        rows()
      }
    }
  }
}

/// The AI changelog's group in Settings › Diagnostics: how long the log of
/// assistant writes is kept, then the log itself as a folded feed, with what
/// the retention choice does as the group's footer. Keeping the control at
/// the top of the group it governs leaves it in place however far the
/// unfolded log runs.
///
/// The retention picker writes the account-scoped virtual
/// `ai_changelog_retention_policy` preference (``ChangelogRetentionPolicy``),
/// the same value an assistant sets via `set_preference`: the sync sweep trims
/// older entries, and "Off" stops recording and purges existing entries on
/// every synced device.
struct SettingsChangelogSection: View {
  @Bindable var store: AppStore

  @State private var current: ChangelogRetentionPolicy = .maximum
  @State private var selection: String = ChangelogRetentionPolicy.maximum.wireValue
  @State private var isLoaded = false

  private static let presets: [ChangelogRetentionPolicy] = [
    .maximum, .days(90), .days(30), .days(7), .off,
  ]

  var body: some View {
    Section {
      Picker(
        String(
          localized: "settings.activity.retention.label", defaultValue: "Keep AI activity log",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        selection: $selection
      ) {
        ForEach(options, id: \.wireValue) { policy in
          Text(Self.label(for: policy)).tag(policy.wireValue)
        }
      }
      .onChange(of: selection) { _, newValue in persist(newValue) }
      .accessibilityIdentifier("settings.activity.retention.picker")

      SettingsActivityFeed(
        count: store.runtimeDiagnostics?.changelog.entries.count ?? 0,
        accessibilityIdentifier: "settings.activity.changelogToggle"
      ) {
        ForEach(store.runtimeDiagnostics?.changelog.entries ?? []) { entry in
          RuntimeEntryRow(
            title: entry.summary,
            subtitle: "\(entry.entityType) · \(entry.operation)",
            timestamp: entry.timestamp,
            fallbackDetail: entry.initiatedBy
          )
        }
      } empty: {
        LorvexEmptyStatePanel(
          title: String(localized: "settings.activity.no_changelog_entries.title", defaultValue: "No changelog entries", table: "Localizable", bundle: LorvexL10n.bundle),
          message: String(
            localized: "settings.activity.no_changelog_entries",
            defaultValue: "No changelog entries loaded.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: "clock.arrow.circlepath",
          tint: .secondary,
          style: .inline
        )
      }
    } header: {
      Text(String(localized: "settings.activity.ai_changelog", defaultValue: "AI Changelog", table: "Localizable", bundle: LorvexL10n.bundle))
    } footer: {
      Text(footnote)
    }
    .task {
      let policy = await store.loadChangelogRetentionPolicy()
      current = policy
      selection = policy.wireValue
      isLoaded = true
    }
  }

  /// Preset options plus the current stored policy when it is a custom day count
  /// (an assistant can set any positive N via `set_preference`), so the picker
  /// always has a tag matching the selection and never silently rewrites it.
  private var options: [ChangelogRetentionPolicy] {
    var result = Self.presets
    if !result.contains(where: { $0.wireValue == current.wireValue }) {
      result.append(current)
    }
    return result
  }

  private var footnote: String {
    if case .off = ChangelogRetentionPolicy.parse(selection) {
      return String(
        localized: "settings.activity.retention.footer.off",
        defaultValue: "Off stops recording and clears existing entries on all your devices.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "settings.activity.retention.footer",
      defaultValue:
        "Older entries are trimmed on sync. Off stops recording and clears existing entries on all your devices.",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  private func persist(_ wire: String) {
    // Skip a no-op write. The load assigns `selection` and flips `isLoaded` in
    // one synchronous batch, so `.onChange` fires with `isLoaded` already true;
    // without the value check every appearance of the pane would re-persist a
    // stored policy other than the default, bumping the retention version on
    // every device and writing an `ai_changelog` row into the very log the
    // user is trimming.
    guard isLoaded, wire != current.wireValue else { return }
    let policy = ChangelogRetentionPolicy.parse(wire)
    current = policy
    Task { await store.saveChangelogRetentionPolicy(policy) }
  }

  private static func label(for policy: ChangelogRetentionPolicy) -> String {
    switch policy {
    case .maximum:
      let entries = Int(SyncNaming.auditMaxEntriesSafeguard)
      return String(
        localized: "settings.activity.retention.maximum", defaultValue: "Maximum (\(entries) entries)",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .off:
      return String(
        localized: "settings.activity.retention.off", defaultValue: "Off (never store)",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .days(let n):
      return String(
        localized: "settings.activity.retention.days", defaultValue: "\(Int(n)) days",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// One diagnostics row: the summary over its source line, with when it happened
/// at the trailing edge in the viewer's own time zone. `timestamp` is the feed's
/// ISO-8601 UTC string; an entry from today shows its time alone, an older one
/// its date and time, and the hover tooltip carries the full date. A missing or
/// unparsable timestamp falls back to `fallbackDetail`.
struct RuntimeEntryRow: View {
  let title: String
  let subtitle: String
  let timestamp: String?
  var fallbackDetail: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(displayTitle)
          .lineLimit(2)
        Text(subtitle)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if let date {
        Text(Self.shortStamp(date))
          .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(date.formatted(date: .complete, time: .standard))
      } else if let detail = timestamp ?? fallbackDetail {
        Text(detail)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(format: accessibilityLabelFormat, displayTitle, subtitle))
  }

  private var date: Date? {
    guard let timestamp else { return nil }
    return LorvexDateFormatters.iso8601Fractional.date(from: timestamp)
      ?? LorvexDateFormatters.iso8601.date(from: timestamp)
  }

  private static func shortStamp(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
      ? date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: LorvexClockFormat.displayLocale))
      : date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: LorvexClockFormat.displayLocale))
  }

  private var displayTitle: String {
    title.isEmpty
      ? String(localized: "settings.activity.untitled_event", defaultValue: "Untitled event", table: "Localizable", bundle: LorvexL10n.bundle)
      : title
  }

  private var accessibilityLabelFormat: String {
    String(localized: "settings.activity.entry.a11y", defaultValue: "%@, %@", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
