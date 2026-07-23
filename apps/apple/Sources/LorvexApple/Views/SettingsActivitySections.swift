import LorvexCore
import LorvexDomain
import SwiftUI

extension SettingsView {
  var changelogSection: some View {
    Section(String(localized: "settings.activity.ai_changelog", defaultValue: "AI Changelog", table: "Localizable", bundle: LorvexL10n.bundle)) {
      if let entries = store.runtimeDiagnostics?.changelog.entries, !entries.isEmpty {
        ForEach(entries) { entry in
          RuntimeEntryRow(
            title: entry.summary,
            subtitle: "\(entry.entityType) · \(entry.operation)",
            detail: entry.timestamp ?? entry.initiatedBy
          )
        }
      } else {
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
  }

  var logsSection: some View {
    Section(String(localized: "settings.activity.recent_logs", defaultValue: "Recent Logs", table: "Localizable", bundle: LorvexL10n.bundle)) {
      if let entries = store.runtimeDiagnostics?.recentLogs.entries, !entries.isEmpty {
        ForEach(entries) { entry in
          RuntimeEntryRow(
            // `origin` carries per-row provenance (the `error_logs.source`
            // column, e.g. `metrickit.crash`); the stream-level `source`
            // collapses every error_log row to `error_log`, so prefer the
            // finer origin when present to label crash/hang/sync rows apart.
            title: entry.summary,
            subtitle: "\(entry.origin ?? entry.source) · \(entry.level.rawValue)",
            detail: entry.timestamp
          )
        }
      } else {
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

struct RuntimeEntryRow: View {
  let title: String
  let subtitle: String
  let detail: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(displayTitle)
          .lineLimit(2)
        Text(subtitle)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if let detail {
        Text(detail)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(format: accessibilityLabelFormat, displayTitle, subtitle))
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
