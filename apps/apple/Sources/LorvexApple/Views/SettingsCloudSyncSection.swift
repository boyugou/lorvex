import LorvexCore
import SwiftUI
import LorvexCloudSync

// MARK: - Cloud Sync tab

extension SettingsView {
  @ViewBuilder
  var cloudSyncSection: some View {
    Section(String(localized: "settings.cloud_sync.section", defaultValue: "iCloud Sync", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCloudSyncModePanel(mode: $settings.cloudSyncMode)
        .disabled(
          cloudDeleteInProgress || store.isDataImportRunning || store.isLocalFactoryResetRunning)
        .onChange(of: settings.cloudSyncMode) { _, mode in
          switch mode {
          case .off:
            store.cloudSyncMode = .off
          case .live, .recordPlan:
            // Turning sync back on is the explicit re-opt-in after a Lorvex
            // iCloud-data deletion: lift the durable pause and enqueue the
            // re-upload now, so the first live cycle (after relaunch) resumes
            // instead of wedging at the consent gate. A no-op unless a
            // deletion pause is standing.
            // Capture ordering now: a toggle made before an explicit deletion
            // finishes is superseded by that deletion's terminal Off state,
            // even if a newly-created Task would start after deletion returns.
            if let request = store.makeCloudDeletionReenableRequest() {
              Task {
                await store.liftCloudDeletionPauseForExplicitReenable(request: request)
              }
            }
          }
        }
    }

    let statusReport = store.cloudSyncStatusReport
    Section(String(localized: "settings.cloud_sync.status_section", defaultValue: "Status", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCloudSyncOverviewPanel(rows: cloudSyncOverviewRows(statusReport))
      if statusReport.accountAvailability == .noAccount
        || statusReport.accountAvailability == .restricted
      {
        openICloudSettingsButton
      }
      if showsCloudSyncPausedNotice {
        resumeCloudSyncButton
      }
    }

    Section(String(localized: "settings.cloud_sync.last_cycle_section", defaultValue: "Last Cycle", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCloudSyncCyclePanel(
        subscriptionError: store.lastCloudSyncSubscriptionErrorMessage,
        report: store.lastCloudSyncCycleReport
      )
    }
  }

  /// The paused notice (and its resume action) shows only while sync is
  /// nominally running: an external zone deletion or account switch pauses the
  /// engine while the mode stays Live, which would otherwise look like sync
  /// silently doing nothing. After the in-app iCloud-data deletion the mode is
  /// Off, so the state is already honest without a second banner.
  private var showsCloudSyncPausedNotice: Bool {
    store.cloudSyncMode == .live && store.cloudSyncPauseReason != nil
  }

  private var cloudSyncPausedDetail: String {
    switch store.cloudSyncPauseReason {
    case .userDeletedZone:
      // The retry hint covers the crash window between the durable local pause
      // and the remote deletion barrier: in that state no resume affordance can
      // engage, and re-running the (idempotent) deletion is the recovery path.
      return String(
        localized: "settings.cloud_sync.paused.user_deleted_zone",
        defaultValue:
          "Lorvex data was deleted from iCloud. Sync stays paused so this Mac doesn’t re-upload it without your consent.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ) + " "
        + String(
          localized: "settings.cloud_sync.paused.user_deleted_zone.retry_hint",
          defaultValue:
            "If the deletion was interrupted before it finished, run Delete iCloud Data again to complete it safely.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        )
    case .accountChanged:
      return String(
        localized: "settings.cloud_sync.paused.account_changed",
        defaultValue:
          "The signed-in iCloud account changed. Sync is paused so this Mac’s data isn’t mixed into a different account.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .adoptionInProgress, .backfillFailed:
      return String(
        localized: "settings.cloud_sync.paused.backfill_failed",
        defaultValue: "Preparing the re-upload failed. Resuming will retry it.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case nil:
      return ""
    }
  }

  @ViewBuilder
  private var resumeCloudSyncButton: some View {
    Button {
      resumeSyncInProgress = true
      Task {
        let request = await store.makeCloudSyncResumeRequest()
        resumeSyncInProgress = false
        guard let request else { return }
        pendingCloudSyncResumeRequest = request
        showResumeSyncConfirmation = true
      }
    } label: {
      if resumeSyncInProgress {
        ProgressView().controlSize(.small)
      } else {
        Label(
          String(
            localized: "settings.cloud_sync.resume.action", defaultValue: "Re-upload & Resume Sync…",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "arrow.clockwise.icloud")
      }
    }
    .disabled(resumeSyncInProgress)
    .accessibilityIdentifier("settings.cloudSync.resume")
  }

  private func cloudSyncOverviewRows(_ report: CloudSyncStatusReport) -> [SettingsCloudSyncOverviewRow] {
    var rows = [
      SettingsCloudSyncOverviewRow(
        id: "mode",
        title: String(localized: "settings.cloud_sync.mode", defaultValue: "Sync Mode", table: "Localizable", bundle: LorvexL10n.bundle),
        value: report.mode.localizedSettingsTitle,
        detail: report.localizedSettingsSummary,
        systemImage: report.isOperational ? "icloud.fill" : "icloud.slash",
        level: report.isOperational ? .success : .neutral
      ),
      SettingsCloudSyncOverviewRow(
        id: "account",
        title: String(localized: "settings.cloud_sync.account", defaultValue: "Account", table: "Localizable", bundle: LorvexL10n.bundle),
        value: report.accountAvailability.localizedSettingsStatusLabel,
        detail: report.accountAvailability.userFacingMessage,
        systemImage: "person.crop.circle.badge.checkmark",
        level: report.accountAvailability == .available ? .success : .warning
      ),
      SettingsCloudSyncOverviewRow(
        id: "pending",
        title: String(localized: "settings.cloud_sync.pending_changes", defaultValue: "Pending Changes", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(report.pendingCount)",
        detail: String(
          localized: "settings.cloud_sync.pending_detail",
          defaultValue: "Local changes waiting for the next sync cycle.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "tray.and.arrow.up",
        level: report.pendingCount > 0 ? .warning : .neutral
      ),
    ]

    if let lastAt = report.lastPullAt {
      rows.append(
        SettingsCloudSyncOverviewRow(
          id: "last-sync",
          title: String(localized: "settings.cloud_sync.last_sync", defaultValue: "Last Sync", table: "Localizable", bundle: LorvexL10n.bundle),
          value: cloudSyncRelativeDateString(for: lastAt),
          detail: report.lastPullError ?? String(
            localized: "settings.cloud_sync.complete",
            defaultValue: "Complete",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: report.lastPullError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill",
          level: report.lastPullError == nil ? .success : .warning
        )
      )
    }

    if showsCloudSyncPausedNotice {
      rows.insert(
        SettingsCloudSyncOverviewRow(
          id: "paused",
          title: String(
            localized: "settings.cloud_sync.paused", defaultValue: "Sync Paused",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          value: String(
            localized: "settings.cloud_sync.paused.value", defaultValue: "Action needed",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          detail: cloudSyncPausedDetail,
          systemImage: "pause.circle.fill",
          level: .warning
        ),
        at: 0
      )
    }

    if settings.cloudSyncMode != store.cloudSyncMode {
      rows.insert(
        SettingsCloudSyncOverviewRow(
          id: "restart-required",
          title: String(
            localized: "settings.cloud_sync.restart_required",
            defaultValue: "Restart Required",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          value: String(
            localized: "settings.cloud_sync.pending_mode",
            defaultValue: "Pending",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          detail: String(
            localized: "settings.cloud_sync.restart_detail",
            defaultValue: "The selected sync mode will fully take effect after restarting Lorvex.",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "arrow.clockwise.circle",
          level: .warning
        ),
        at: 1
      )
    }

    return rows
  }

  @ViewBuilder
  private var openICloudSettingsButton: some View {
    if let iCloudSettingsURL {
      OpenSystemSettingsButton(
        label: String(
          localized: "settings.cloud_sync.open_icloud_settings",
          defaultValue: "Open iCloud Settings",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        settingsURL: iCloudSettingsURL
      )
    }
  }

  private var iCloudSettingsURL: URL? {
    URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud")
  }
}

private struct SettingsCloudSyncModePanel: View {
  @Binding var mode: CloudSyncMode

  var body: some View {
    Group {
      Picker(
        String(localized: "settings.cloud_sync.mode", defaultValue: "Sync Mode", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: $mode
      ) {
        // `.recordPlan` is a developer/debug mode — keep it out of the
        // user-facing picker (Off / Live), unless it is somehow the current
        // selection, so the picker still reflects the active mode.
        ForEach(CloudSyncMode.allCases.filter { $0 != .recordPlan || mode == .recordPlan }) { item in
          Text(item.localizedSettingsTitle).tag(item)
        }
      }
      .accessibilityIdentifier("settings.cloudSync.modePanel")

      Text(mode.localizedSettingsDetail)
        .foregroundStyle(.secondary)
        .font(LorvexDesign.Typography.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)

      if mode != .off {
        Label(
          String(
            localized: "settings.cloud_sync.restart_notice",
            defaultValue: "Changes take effect after restarting the app.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: "arrow.clockwise"
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("settings.cloudSync.restartNotice")
      }
    }
  }
}

private struct SettingsCloudSyncOverviewRow: Identifiable {
  let id: String
  let title: String
  let value: String
  let detail: String
  let systemImage: String
  let level: SettingsStatusLevel
}

private struct SettingsCloudSyncOverviewPanel: View {
  let rows: [SettingsCloudSyncOverviewRow]

  var body: some View {
    ForEach(rows) { row in
      SettingsCloudSyncOverviewItem(row: row)
    }
    .accessibilityIdentifier("settings.cloudSync.overview")
  }
}

private struct SettingsCloudSyncOverviewItem: View {
  let row: SettingsCloudSyncOverviewRow

  var body: some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        Text(row.value)
          .foregroundStyle(.primary)
          .monospacedDigit()
        Text(row.detail)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: false, vertical: true)
      }
    } label: {
      Label(row.title, systemImage: row.systemImage)
        .foregroundStyle(row.level == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(row.level.color))
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.cloudSync.overview.\(row.id)")
  }
}
