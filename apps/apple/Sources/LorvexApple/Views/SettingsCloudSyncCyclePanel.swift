import LorvexCore
import SwiftUI
import LorvexCloudSync

// MARK: - Last Sync Cycle panel

struct SettingsCloudSyncCyclePanel: View {
  let subscriptionError: String?
  let report: CloudSyncCycleReport?
  @State private var advancedExpanded = false

  var body: some View {
    Group {
      SettingsCloudSyncCycleSubscriptionRow(error: subscriptionError)
        .accessibilityIdentifier("settings.cloudSync.cycle")

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
        tint: .blue
      ),
      SettingsCloudSyncMetricRow(
        id: "failed",
        title: String(localized: "settings.cloud_sync.failed_pushes", defaultValue: "Failed Pushes", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.failedPushCount)",
        systemImage: "exclamationmark.triangle.fill",
        tint: report.failedPushCount > 0 ? .orange : .secondary
      ),
      SettingsCloudSyncMetricRow(
        id: "fetched",
        title: String(localized: "settings.cloud_sync.fetched_records", defaultValue: "Fetched Records", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.fetchedRecordCount)",
        systemImage: "arrow.down.doc",
        tint: .blue
      ),
      SettingsCloudSyncMetricRow(
        id: "applied",
        title: String(localized: "settings.cloud_sync.applied", defaultValue: "Applied", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.applied)",
        systemImage: "checkmark.circle.fill",
        tint: .green
      ),
      SettingsCloudSyncMetricRow(
        id: "skipped",
        title: String(localized: "settings.cloud_sync.skipped", defaultValue: "Skipped", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.skipped)",
        systemImage: "forward.end.fill",
        tint: .secondary
      ),
      SettingsCloudSyncMetricRow(
        id: "deferred",
        title: String(localized: "settings.cloud_sync.deferred", defaultValue: "Deferred", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.deferred)",
        systemImage: "clock.fill",
        tint: .orange
      ),
      SettingsCloudSyncMetricRow(
        id: "remapped",
        title: String(localized: "settings.cloud_sync.remapped", defaultValue: "Remapped", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.remapped)",
        systemImage: "arrow.triangle.branch",
        tint: .purple
      ),
      SettingsCloudSyncMetricRow(
        id: "replayed",
        title: String(localized: "settings.cloud_sync.replayed", defaultValue: "Replayed", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.inbound.drainReplayed)",
        systemImage: "arrow.counterclockwise",
        tint: .teal
      ),
      SettingsCloudSyncMetricRow(
        id: "fetch-state",
        title: String(localized: "settings.cloud_sync.fetch_state", defaultValue: "Fetch State", table: "Localizable", bundle: LorvexL10n.bundle),
        value: report.moreInboundComing
          ? String(localized: "settings.cloud_sync.more_available", defaultValue: "More Available", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "settings.cloud_sync.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "tray.full",
        tint: report.moreInboundComing ? .orange : .green
      ),
    ]

    if report.inbound.undecodable > 0 {
      rows.append(
        SettingsCloudSyncMetricRow(
          id: "undecodable",
          title: String(localized: "settings.cloud_sync.undecodable", defaultValue: "Undecodable", table: "Localizable", bundle: LorvexL10n.bundle),
          value: "\(report.inbound.undecodable)",
          systemImage: "xmark.octagon.fill",
          tint: .red
        )
      )
    }

    return rows
  }
}

private struct SettingsCloudSyncCycleSubscriptionRow: View {
  let error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Label(
          String(localized: "settings.cloud_sync.subscription", defaultValue: "Subscription", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(error == nil ? Color.green : Color.orange)

        Spacer()

        Text(error == nil
          ? String(localized: "settings.cloud_sync.ready", defaultValue: "Ready", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "settings.cloud_sync.failed", defaultValue: "Failed", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(error == nil ? .green : .orange)
      }

      if let error {
        Text(error)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(String(
            localized: "settings.cloud_sync.subscription_error",
            defaultValue: "Subscription Error",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
      }
    }
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
    VStack(alignment: .leading, spacing: 3) {
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
