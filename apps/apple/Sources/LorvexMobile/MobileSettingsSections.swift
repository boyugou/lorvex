import LorvexCloudSync
import LorvexCore
import SwiftUI

// MARK: - Notifications

struct MobileStoreSettingsNotificationsSection: View {
  @Bindable var store: MobileStore
  @State private var showTaskNotesInNotifications = false

  var body: some View {
    Section(
      String(
        localized: "settings.section.notifications", defaultValue: "Notifications",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      Toggle(isOn: badgeBinding) {
        Label(
          String(
            localized: "settings.badge_with_due_tasks", defaultValue: "Badge with Due Tasks",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "app.badge")
      }
      .accessibilityIdentifier("mobileSettings.badgeEnabled")
      Text(
        String(
          localized: "settings.badge.footer",
          defaultValue: "Show the count of overdue and due-today tasks on the app icon.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      Toggle(isOn: showTaskNotesBinding) {
        Label(
          String(
            localized: "settings.show_task_notes", defaultValue: "Show Task Notes in Notifications",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "note.text")
      }
      .accessibilityIdentifier("mobileSettings.showTaskNotesInNotifications")
      Text(
        String(
          localized: "settings.show_task_notes.footer",
          defaultValue:
            "When off, reminders show only the task title — never your notes — on the lock screen and banners.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      NavigationLink {
        PermissionsStatusView()
      } label: {
        Label(
          String(
            localized: "settings.permission_status", defaultValue: "Permission Status",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "checkmark.shield")
      }
      .accessibilityIdentifier("mobileSettings.permissionsStatus")
    }
    .task {
      showTaskNotesInNotifications = await store.loadShowTaskNotesInNotificationsPreference()
    }
  }

  private var badgeBinding: Binding<Bool> {
    Binding(
      get: { store.badgeEnabled },
      set: { store.setBadgeEnabled($0) }
    )
  }

  private var showTaskNotesBinding: Binding<Bool> {
    Binding(
      get: { showTaskNotesInNotifications },
      set: { newValue in
        showTaskNotesInNotifications = newValue
        Task { await store.saveShowTaskNotesInNotificationsPreference(newValue) }
      }
    )
  }
}

// MARK: - Cloud Sync

struct MobileStoreSettingsCloudSyncSection: View {
  @Bindable var store: MobileStore

  @State private var showResumeConfirmation = false
  @State private var resumeInProgress = false
  @State private var pendingResumeRequest: MobileCloudSyncResumeRequest?
  @State private var showDeleteCloudConfirmation = false
  @State private var deleteCloudInProgress = false
  @State private var deleteCloudErrorMessage: String?
  @State private var deleteCloudSucceeded = false

  var body: some View {
    Section(
      String(
        localized: "settings.section.cloud_sync", defaultValue: "Cloud Sync", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      // The picker stays enabled during a transition: a change requested
      // mid-transition or mid-cycle is queued (latest wins) and applied when
      // the active work completes, and the binding reads
      // `cloudSyncModeTarget` so the segment shows the queued target instead
      // of snapping back.
      Picker(
        String(
          localized: "settings.sync.mode", defaultValue: "Sync Mode", table: "Localizable",
          bundle: MobileL10n.bundle), selection: cloudSyncModeBinding
      ) {
        Text(
          String(
            localized: "settings.sync.mode.off", defaultValue: "Off", table: "Localizable",
            bundle: MobileL10n.bundle)
        ).tag(CloudSyncMode.off)
        Text(
          String(
            localized: "settings.sync.mode.live", defaultValue: "Live", table: "Localizable",
            bundle: MobileL10n.bundle)
        ).tag(CloudSyncMode.live)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("mobileSettings.cloudSync.mode")

      if store.isSettingCloudSyncMode || store.pendingCloudSyncMode != nil {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(
            String(
              localized: "settings.sync.enabling", defaultValue: "Updating Cloud Sync…",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("mobileSettings.cloudSync.inProgress")
      }

      // The footer follows the queued or effective picker target so it cannot
      // contradict a segment change while the transition is still pending.
      Group {
        switch store.cloudSyncModeTarget {
        case .live:
          Text(
            String(
              localized: "settings.sync.mode.detail.live",
              defaultValue:
                "Cloud Sync pushes local changes to iCloud and pulls remote changes when Lorvex refreshes.",
              table: "Localizable",
              bundle: MobileL10n.bundle
            ))
        case .off, .recordPlan:
          Text(
            String(
              localized: "settings.sync.mode.detail.off",
              defaultValue: "Cloud Sync is disabled. Local data stays on this device.",
              table: "Localizable",
              bundle: MobileL10n.bundle
            ))
        }
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

      LabeledContent(
        String(
          localized: "settings.sync.backend", defaultValue: "Backend", table: "Localizable",
          bundle: MobileL10n.bundle), value: store.cloudSyncBackendLabel
      )
      .accessibilityIdentifier("mobileSettings.syncBackend")
      if store.cloudSyncMode == .live {
        LabeledContent(
          String(
            localized: "settings.sync.account", defaultValue: "Account", table: "Localizable",
            bundle: MobileL10n.bundle), value: syncAccountValue
        )
        .accessibilityIdentifier("mobileSettings.syncAccount")
        if shouldShowICloudSettingsLink {
          MobileSettingsRecoveryLink(
            label: String(
              localized: "settings.sync.open_icloud_settings", defaultValue: "Open iCloud Settings",
              table: "Localizable", bundle: MobileL10n.bundle),
            accessibilityIdentifier: "mobileSettings.sync.openICloudSettings")
        }
      }
      LabeledContent(
        String(
          localized: "settings.sync.pending_changes", defaultValue: "Pending Changes",
          table: "Localizable", bundle: MobileL10n.bundle),
        value: "\(store.mobileCloudSyncStatusReport.pendingCount)"
      )
      .accessibilityIdentifier("mobileSettings.syncPending")
      if let lastSuccess = syncLastSuccessValue {
        LabeledContent(
          String(
            localized: "settings.sync.last_success", defaultValue: "Last Success",
            table: "Localizable", bundle: MobileL10n.bundle), value: lastSuccess
        )
        .accessibilityIdentifier("mobileSettings.syncLastSuccess")
      }
      if let lastError = syncLastError {
        LabeledContent(
          String(
            localized: "settings.sync.last_error", defaultValue: "Last Error", table: "Localizable",
            bundle: MobileL10n.bundle), value: lastError
        )
        .foregroundStyle(.red)
        .accessibilityIdentifier("mobileSettings.syncLastError")
      } else if store.runtimeDiagnostics == nil {
        Text(
          String(
            localized: "settings.sync.loading", defaultValue: "Sync status loading…",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      }

      if store.cloudSyncMode == .live, store.cloudSyncPauseReason != nil {
        pausedNotice
      }

      deleteCloudDataRows
    }
  }

  /// The engine paused itself while the mode is still Live (external zone
  /// deletion, account switch, or a failed re-upload preparation) — without a
  /// notice, sync would look like it silently does nothing. The resume action
  /// re-uploads this device's data into the current account after an explicit
  /// confirmation.
  @ViewBuilder
  private var pausedNotice: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(
        String(
          localized: "settings.sync.paused", defaultValue: "Sync Paused", table: "Localizable",
          bundle: MobileL10n.bundle),
        systemImage: "pause.circle.fill"
      )
      .foregroundStyle(.orange)
      Text(pausedDetail)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobileSettings.sync.paused")

    Button {
      resumeInProgress = true
      Task {
        let request = await store.makeCloudSyncResumeRequest()
        resumeInProgress = false
        guard let request else { return }
        pendingResumeRequest = request
        showResumeConfirmation = true
      }
    } label: {
      if resumeInProgress {
        ProgressView().frame(maxWidth: .infinity)
      } else {
        Label(
          String(
            localized: "settings.sync.resume.action", defaultValue: "Re-upload & Resume Sync…",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "arrow.clockwise.icloud")
      }
    }
    .disabled(resumeInProgress || store.isCloudDataDeletionRunning)
    .accessibilityIdentifier("mobileSettings.sync.resume")
    .confirmationDialog(
      String(
        localized: "settings.sync.resume.confirm.title",
        defaultValue: "Re-upload this device’s data and resume sync?", table: "Localizable",
        bundle: MobileL10n.bundle),
      isPresented: $showResumeConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "settings.sync.resume.confirm.action", defaultValue: "Re-upload & Resume",
          table: "Localizable", bundle: MobileL10n.bundle)
      ) {
        guard let request = pendingResumeRequest else { return }
        pendingResumeRequest = nil
        resumeInProgress = true
        Task {
          await store.adoptCurrentCloudAccountAndResumeSync(request: request)
          resumeInProgress = false
        }
      }
      Button(
        String(
          localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) {
        pendingResumeRequest = nil
      }
    } message: {
      Text(
        String(
          localized: "settings.sync.resume.confirm.message",
          defaultValue:
            "Lorvex will upload the data stored on this device to the currently signed-in iCloud account and resume syncing.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var pausedDetail: String {
    switch store.cloudSyncPauseReason {
    case .userDeletedZone:
      // The retry hint covers the crash window between the durable local pause
      // and the remote deletion barrier: in that state no resume affordance can
      // engage, and re-running the (idempotent) deletion is the recovery path.
      return String(
        localized: "settings.sync.paused.user_deleted_zone",
        defaultValue:
          "Lorvex data was deleted from iCloud. Sync stays paused so this device doesn’t re-upload it without your consent.",
        table: "Localizable", bundle: MobileL10n.bundle)
        + " "
        + String(
          localized: "settings.sync.paused.user_deleted_zone.retry_hint",
          defaultValue:
            "If the deletion was interrupted before it finished, run Delete iCloud Data again to complete it safely.",
          table: "Localizable", bundle: MobileL10n.bundle)
    case .accountChanged:
      return String(
        localized: "settings.sync.paused.account_changed",
        defaultValue:
          "The signed-in iCloud account changed. Sync is paused so this device’s data isn’t mixed into a different account.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .adoptionInProgress, .backfillFailed:
      return String(
        localized: "settings.sync.paused.backfill_failed",
        defaultValue: "Preparing the re-upload failed. Resuming will retry it.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case nil:
      return ""
    }
  }

  /// "Delete iCloud Data" is deliberately available regardless of the sync
  /// mode: the common case is a user who turned sync off and wants the cloud
  /// copy gone without re-enabling sync (which would move data) first.
  @ViewBuilder
  private var deleteCloudDataRows: some View {
    Button(role: .destructive) {
      showDeleteCloudConfirmation = true
    } label: {
      if deleteCloudInProgress {
        ProgressView().frame(maxWidth: .infinity)
      } else {
        Label(
          String(
            localized: "settings.sync.delete_cloud.title", defaultValue: "Delete iCloud Data…",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "icloud.slash")
      }
    }
    .disabled(
      deleteCloudInProgress || store.isSettingCloudSyncMode || store.isDataImportRunning)
    .accessibilityIdentifier("mobileSettings.sync.deleteCloudData")
    .sheet(isPresented: $showDeleteCloudConfirmation) {
      MobileTypedConfirmationSheet(
        title: String(
          localized: "settings.sync.delete_cloud.confirm.action",
          defaultValue: "Delete iCloud Data", table: "Localizable", bundle: MobileL10n.bundle),
        message: String(
          localized: "settings.sync.delete_cloud.confirm.message",
          defaultValue:
            "This permanently removes all Lorvex data from your iCloud account, for every device that syncs with it. Data stored on this device stays intact. Sync stays off until you turn it back on.",
          table: "Localizable", bundle: MobileL10n.bundle),
        confirmationWord: String(
          localized: "settings.sync.delete_cloud.confirm.word", defaultValue: "DELETE",
          table: "Localizable", bundle: MobileL10n.bundle),
        confirmTitle: String(
          localized: "settings.sync.delete_cloud.confirm.action",
          defaultValue: "Delete iCloud Data", table: "Localizable", bundle: MobileL10n.bundle),
        accessibilityIdentifierPrefix: "mobileSettings.sync.deleteCloudData.confirm"
      ) {
        deleteCloudInProgress = true
        deleteCloudErrorMessage = nil
        deleteCloudSucceeded = false
        Task {
          deleteCloudErrorMessage = await store.deleteCloudDataEverywhere()
          deleteCloudSucceeded = deleteCloudErrorMessage == nil
          deleteCloudInProgress = false
        }
      }
    }

    Text(
      String(
        localized: "settings.sync.delete_cloud.footer",
        defaultValue:
          "Delete every Lorvex record from your iCloud account — for all devices that sync with it. Data on this device is not touched. Sync turns off until you re-enable it, which re-uploads this device’s data.",
        table: "Localizable", bundle: MobileL10n.bundle)
    )
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)

    if let deleteCloudErrorMessage {
      Label(deleteCloudErrorMessage, systemImage: "exclamationmark.triangle")
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.orange)
        .accessibilityIdentifier("mobileSettings.sync.deleteCloudData.error")
    }

    if deleteCloudSucceeded {
      Label(
        String(
          localized: "settings.sync.delete_cloud.success",
          defaultValue: "Lorvex data was deleted from iCloud. Sync is now off.",
          table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "checkmark.circle"
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.green)
      .accessibilityIdentifier("mobileSettings.sync.deleteCloudData.success")
    }
  }

  private var cloudSyncModeBinding: Binding<CloudSyncMode> {
    Binding(
      get: { store.cloudSyncModeTarget == .live ? .live : .off },
      set: { mode in
        let request = store.makeCloudSyncModeRequest(mode)
        Task { await store.setCloudSyncModeFromSettings(request) }
      }
    )
  }

  private var syncAccountValue: String {
    switch store.cloudKitAccountAvailability {
    case .available:
      return String(
        localized: "settings.sync.account.available", defaultValue: "Available",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .noAccount:
      return String(
        localized: "settings.sync.account.no_account", defaultValue: "Not signed in",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .restricted:
      return String(
        localized: "settings.sync.account.restricted", defaultValue: "Restricted",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .couldNotDetermine:
      return String(
        localized: "settings.sync.account.unknown", defaultValue: "Unknown", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .temporarilyUnavailable:
      return String(
        localized: "settings.sync.account.temporarily_unavailable",
        defaultValue: "Temporarily unavailable", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  private var shouldShowICloudSettingsLink: Bool {
    store.cloudSyncMode == .live && store.cloudKitAccountAvailability != .available
  }

  private var syncLastError: String? {
    store.lastCloudSyncRemoteChangeErrorMessage ?? store.lastCloudSyncSubscriptionErrorMessage
  }

  private var syncLastSuccessValue: String? {
    guard let date = store.lastCloudSyncRemoteChangeSucceededAt else { return nil }
    return MobileDateFormatting.abbreviatedRelativeString(for: date, relativeTo: store.now())
  }
}
