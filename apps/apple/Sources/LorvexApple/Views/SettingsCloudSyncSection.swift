import LorvexCore
import SwiftUI
import LorvexCloudSync

// MARK: - Cloud Sync tab

extension SettingsView {
  @ViewBuilder
  var cloudSyncSection: some View {
    // The switch names its setting, so its group carries no header; what the
    // current mode means is the footer directly under it.
    Section {
      SettingsCloudSyncModePanel(mode: $settings.cloudSyncMode)
        .disabled(
          cloudDeleteInProgress || store.isDataImportRunning || store.isLocalFactoryResetRunning)
        .onChange(of: settings.cloudSyncMode) { _, mode in
          switch mode {
          case .off:
            store.turnOffCloudSync()
          case .live:
            // Takes effect at once. Turning sync back on is also the explicit
            // re-opt-in after a Lorvex iCloud-data deletion, which the store
            // honors by lifting that pause before its first cycle.
            store.turnOnCloudSync(settings: settings)
          }
        }
    } footer: {
      Text(settings.cloudSyncMode.localizedSettingsDetail)
    }

    let statusReport = store.cloudSyncStatusReport
    Section(String(localized: "settings.cloud_sync.status_section", defaultValue: "Status", table: "Localizable", bundle: LorvexL10n.bundle)) {
      SettingsCloudSyncOverviewPanel(rows: cloudSyncOverviewRows(statusReport))
      if statusReport.accountAvailability == .noAccount
        || statusReport.accountAvailability == .restricted
      {
        SettingsTrailingActionRow { openICloudSettingsButton }
      }
      if showsCloudSyncPausedNotice {
        SettingsTrailingActionRow { resumeCloudSyncButton }
      }
    }

    // With sync off and no pass yet, an empty Last Cycle group says nothing.
    if statusReport.mode != .off || store.lastCloudSyncCycleReport != nil {
      Section(String(localized: "settings.cloud_sync.last_cycle_section", defaultValue: "Last Cycle", table: "Localizable", bundle: LorvexL10n.bundle)) {
        SettingsCloudSyncCyclePanel(report: store.lastCloudSyncCycleReport)
      }
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

  /// The Status rows. A row is tinted only when something needs the user:
  /// an account that blocks sync, an upload that failed, a standing pause.
  /// With sync off the mode row would only repeat the picker above and the
  /// account has not been checked, so both are left out; the pending row stays
  /// neutral and says what uploads once sync is turned on.
  private func cloudSyncOverviewRows(_ report: CloudSyncStatusReport) -> [SettingsCloudSyncOverviewRow] {
    let accountUnchecked =
      report.mode == .off && report.accountAvailability == .couldNotDetermine
    var rows = [
      SettingsCloudSyncOverviewRow(
        id: "mode",
        title: CloudSyncMode.localizedSettingsStatusTitle,
        value: report.mode.localizedSettingsTitle,
        detail: report.localizedSettingsSummary,
        systemImage: report.isOperational ? "icloud.fill" : "icloud.slash",
        level: report.isOperational ? .success : .neutral
      ),
      SettingsCloudSyncOverviewRow(
        id: "account",
        title: String(localized: "settings.cloud_sync.account", defaultValue: "Account", table: "Localizable", bundle: LorvexL10n.bundle),
        value: accountUnchecked
          ? String(
            localized: "settings.cloud_sync.account.not_checked", defaultValue: "Not checked",
            table: "Localizable", bundle: LorvexL10n.bundle)
          : report.accountAvailability.localizedSettingsStatusLabel,
        detail: accountUnchecked
          ? String(
            localized: "settings.cloud_sync.account.not_checked_detail",
            defaultValue: "iCloud is checked once sync is turned on.",
            table: "Localizable", bundle: LorvexL10n.bundle)
          : report.accountAvailability.userFacingMessage,
        systemImage: accountUnchecked ? "person.crop.circle" : "person.crop.circle.badge.checkmark",
        level: accountUnchecked
          ? .neutral : (report.accountAvailability == .available ? .success : .warning)
      ),
      SettingsCloudSyncOverviewRow(
        id: "pending",
        title: String(localized: "settings.cloud_sync.pending_changes", defaultValue: "Pending Changes", table: "Localizable", bundle: LorvexL10n.bundle),
        value: report.pendingCount.formatted(),
        detail: cloudSyncPendingDetail(report),
        systemImage: "tray.and.arrow.up",
        level: cloudSyncPushError(report) == nil ? .neutral : .warning
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

    if report.mode == .off {
      rows.removeAll { $0.id == "mode" || ($0.id == "account" && accountUnchecked) }
    }
    return rows
  }

  /// The error of the last upload attempt, only while sync is live: with sync
  /// off nothing uploads, so an error kept from before the mode changed
  /// describes nothing the user can act on.
  private func cloudSyncPushError(_ report: CloudSyncStatusReport) -> String? {
    report.mode == .live ? report.lastPushError : nil
  }

  /// What the pending count means right now: why the last upload failed,
  /// where the changes go while sync is off, or that they wait for the next
  /// cycle.
  private func cloudSyncPendingDetail(_ report: CloudSyncStatusReport) -> String {
    if let error = cloudSyncPushError(report) {
      return error
    }
    if report.mode == .off && report.pendingCount > 0 {
      return String(
        localized: "settings.cloud_sync.pending_detail_off",
        defaultValue: "Local changes that upload once iCloud sync is turned on.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    return String(
      localized: "settings.cloud_sync.pending_detail",
      defaultValue: "Local changes waiting for the next sync cycle.",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
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

/// The iCloud sync switch; the enclosing group's footer says what the
/// current mode means.
private struct SettingsCloudSyncModePanel: View {
  @Binding var mode: CloudSyncMode

  var body: some View {
    Toggle(
      CloudSyncMode.localizedSettingsToggle,
      isOn: Binding(get: { mode == .live }, set: { mode = $0 ? .live : .off })
    )
    .accessibilityIdentifier("settings.cloudSync.modePanel")
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

/// One Status row: its glyph and title with the sentence that explains it
/// underneath, and its value at the trailing edge. As in the Diagnostics
/// rows, the status color marks the glyph, and the value too when it needs
/// attention, so a row's title never reads as a link.
private struct SettingsCloudSyncOverviewItem: View {
  let row: SettingsCloudSyncOverviewRow

  var body: some View {
    LabeledContent {
      Text(row.value)
        .foregroundStyle(valueColor)
        .monospacedDigit()
    } label: {
      Label {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(row.title)
          Text(row.detail)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } icon: {
        Image(systemName: row.systemImage)
          .foregroundStyle(row.level == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(row.level.color))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.cloudSync.overview.\(row.id)")
  }

  private var valueColor: Color {
    switch row.level {
    case .warning, .error: row.level.color
    case .neutral, .success: .primary
    }
  }
}
