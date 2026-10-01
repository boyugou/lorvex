import LorvexCore
import LorvexDomain
import SwiftUI

extension SettingsView {
  var changelogSection: some View {
    SettingsActivityLogSection(
      title: String(localized: "settings.activity.ai_changelog", defaultValue: "AI Changelog", table: "Localizable", bundle: LorvexL10n.bundle),
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
  }

  var logsSection: some View {
    SettingsActivityLogSection(
      title: String(localized: "settings.activity.recent_logs", defaultValue: "Recent Logs", table: "Localizable", bundle: LorvexL10n.bundle),
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

/// A diagnostics feed in the Activity pane, folded by default: the section
/// shows one disclosure row carrying the entry count, and the rows appear only
/// once the user opens it. The feeds run to hundreds of rows a person reads
/// only while troubleshooting, so unfolded they would bury the retention
/// control and every section after them. An empty feed shows `empty` directly,
/// with nothing to fold.
private struct SettingsActivityLogSection<Rows: View, Empty: View>: View {
  let title: String
  let count: Int
  let accessibilityIdentifier: String
  @ViewBuilder let rows: () -> Rows
  @ViewBuilder let empty: () -> Empty
  @State private var isExpanded = false

  var body: some View {
    Section(title) {
      if count == 0 {
        empty()
      } else {
        SettingsAdvancedDisclosureButton(
          isExpanded: $isExpanded,
          title: LocalizedStringResource(
            "settings.activity.entry_count", defaultValue: "Entries (\(count))",
            table: "Localizable", bundle: LorvexL10n.bundle),
          accessibilityIdentifier: accessibilityIdentifier)
        if isExpanded {
          rows()
        }
      }
    }
  }
}

/// Retention control for the AI changelog: how long the append-only audit trail
/// of assistant writes is kept before the sync sweep trims it. "Off" stops
/// recording new entries and purges existing ones on every synced device. Writes
/// the account-scoped virtual `ai_changelog_retention_policy` preference
/// (``ChangelogRetentionPolicy``) — the same value an assistant sets via
/// `set_preference`.
struct SettingsChangelogRetentionRow: View {
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

      Text(footnote)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    } header: {
      Text(String(
        localized: "settings.activity.retention.title", defaultValue: "Activity Log Retention",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
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
    guard isLoaded else { return }
    let policy = ChangelogRetentionPolicy.parse(wire)
    current = policy
    Task { await store.saveChangelogRetentionPolicy(policy) }
  }

  private static func label(for policy: ChangelogRetentionPolicy) -> String {
    switch policy {
    case .maximum:
      return String(
        localized: "settings.activity.retention.maximum",
        defaultValue: "Maximum (10,000 entries)",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .off:
      return String(
        localized: "settings.activity.retention.off", defaultValue: "Off (never store)",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .days(let n):
      switch n {
      case 90:
        return String(
          localized: "settings.activity.retention.days.90", defaultValue: "90 days",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      case 30:
        return String(
          localized: "settings.activity.retention.days.30", defaultValue: "30 days",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      case 7:
        return String(
          localized: "settings.activity.retention.days.7", defaultValue: "7 days",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      default:
        return String(
          format: String(
            localized: "settings.activity.retention.days.custom", defaultValue: "%lld days",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          Int(n))
      }
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
