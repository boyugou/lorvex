import LorvexCore
import SwiftUI
import LorvexCloudSync

// MARK: - Last Sync Cycle panel

/// The Last Cycle group: the last sync pass's record counters behind
/// Advanced, or "Sync has not run yet."
struct SettingsCloudSyncCyclePanel: View {
  let report: CloudSyncCycleReport?
  @State private var advancedExpanded = false

  var body: some View {
    Group {
      if let report {
        // The per-cycle CloudKit record counters are troubleshooting detail —
        // keep them available but collapsed behind Advanced.
        SettingsAdvancedDisclosureButton(
          isExpanded: $advancedExpanded,
          accessibilityIdentifier: "settings.cloudSync.advancedToggle")

        if advancedExpanded {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: LorvexDesign.Spacing.s)],
            alignment: .leading,
            spacing: LorvexDesign.Spacing.s
          ) {
            ForEach(metricRows(report)) { row in
              SettingsCloudSyncMetricTile(row: row)
            }
          }
        }
      } else {
        Text(LocalizedStringResource("settings.cloud_sync.not_run_yet", defaultValue: "Sync has not run yet.", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityLabel(String(
            localized: "settings.cloud_sync.cycle_summary.a11y",
            defaultValue: "Sync cycle summary",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
      }
    }
  }

  private func metricRows(_ report: CloudSyncCycleReport) -> [SettingsCloudSyncMetricRow] {
    var rows = [
      SettingsCloudSyncMetricRow(
        id: "pushed",
        title: String(localized: "settings.cloud_sync.pushed_records", defaultValue: "Pushed Records", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.pushedRecordCount)",
        systemImage: "arrow.up.doc",
        tint: LorvexDesign.Palette.neutral
      ),
      SettingsCloudSyncMetricRow(
        id: "failed",
        title: String(localized: "settings.cloud_sync.failed_pushes", defaultValue: "Failed Pushes", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.failedPushCount)",
        systemImage: "exclamationmark.triangle.fill",
        tint: report.failedPushCount > 0 ? LorvexDesign.Palette.warning : LorvexDesign.Palette.neutral
      ),
      SettingsCloudSyncMetricRow(
        id: "fetched",
        title: String(localized: "settings.cloud_sync.fetched_records", defaultValue: "Fetched Records", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.fetchedRecordCount)",
        systemImage: "arrow.down.doc",
        tint: LorvexDesign.Palette.neutral
      ),
      SettingsCloudSyncMetricRow(
        id: "applied",
        title: String(localized: "settings.cloud_sync.applied", defaultValue: "Applied", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.applied)",
        systemImage: "checkmark.circle.fill",
        tint: LorvexDesign.Palette.success
      ),
      SettingsCloudSyncMetricRow(
        id: "skipped",
        title: String(localized: "settings.cloud_sync.skipped", defaultValue: "Skipped", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.skipped)",
        systemImage: "forward.end.fill",
        tint: LorvexDesign.Palette.neutral
      ),
      SettingsCloudSyncMetricRow(
        id: "deferred",
        title: String(localized: "settings.cloud_sync.deferred", defaultValue: "Deferred", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.deferred)",
        systemImage: "clock.fill",
        tint: LorvexDesign.Palette.warning
      ),
      SettingsCloudSyncMetricRow(
        id: "remapped",
        title: String(localized: "settings.cloud_sync.remapped", defaultValue: "Remapped", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.remapped)",
        systemImage: "arrow.triangle.branch",
        tint: LorvexDesign.Palette.neutral
      ),
      SettingsCloudSyncMetricRow(
        id: "replayed",
        title: String(localized: "settings.cloud_sync.replayed", defaultValue: "Replayed", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.drainReplayed)",
        systemImage: "arrow.counterclockwise",
        tint: LorvexDesign.Palette.neutral
      ),
    ]

    if report.inbound.undecodable > 0 {
      rows.append(
        SettingsCloudSyncMetricRow(
          id: "undecodable",
          title: String(localized: "settings.cloud_sync.undecodable", defaultValue: "Undecodable", table: "Localizable", bundle: LorvexL10n.bundle),
          value: "\(report.inbound.undecodable)",
          systemImage: "xmark.octagon.fill",
          tint: LorvexDesign.Palette.error
        )
      )
    }

    return rows
  }
}

private struct SettingsCloudSyncMetricRow: Identifiable {
  let id: String
  let title: String
  let value: String
  let systemImage: String
  let tint: Color
}

private struct SettingsCloudSyncMetricTile: View {
  let row: SettingsCloudSyncMetricRow

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Label(row.title, systemImage: row.systemImage)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(row.tint)
        .lineLimit(1)
      Text(row.value)
        .font(LorvexDesign.Typography.primaryEmphasis.monospacedDigit())
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
    .padding(LorvexDesign.Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(row.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.cloudSync.metric.\(row.id)")
  }
}
