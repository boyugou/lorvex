import LorvexCloudSync
import LorvexCore
import SwiftUI

// MARK: - Notifications

struct MobileStoreSettingsNotificationsSection: View {
  @Bindable var store: MobileStore
  @State private var showTaskNotesInNotifications = false

  // One group per toggle so each footer sits directly under the switch it
  // explains, the way the system Settings app lays out notification options.
  var body: some View {
    // The permission row names the group itself, so it carries no header
    // that would repeat "Notifications" over it.
    Section {
      MobileNotificationPermissionRow(onAuthorized: { await store.replenishReminderWindow() })
    }

    Section {
      Toggle(isOn: badgeBinding) {
        Text(
          String(
            localized: "settings.badge_with_due_tasks", defaultValue: "Badge with Due Tasks",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
      .accessibilityIdentifier("mobileSettings.badgeEnabled")
    } footer: {
      Text(
        String(
          localized: "settings.badge.footer",
          defaultValue: "Show the count of overdue and due-today tasks on the app icon.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }

    Section {
      Toggle(isOn: showTaskNotesBinding) {
        Text(
          String(
            localized: "settings.show_task_notes", defaultValue: "Show Task Notes in Notifications",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
      .accessibilityIdentifier("mobileSettings.showTaskNotesInNotifications")
    } footer: {
      Text(
        String(
          localized: "settings.show_task_notes.footer",
          defaultValue:
            "When off, reminders show only the task title — never your notes — on the lock screen and banners.",
          table: "Localizable", bundle: MobileL10n.bundle))
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
    modeSection
    // Off has nothing to report, and the mode footer already says so; the
    // backend itself is a Diagnostics row.
    if store.cloudSyncMode == .live {
      statusSection
    }
    deleteCloudDataSection
  }

  /// The iCloud switch with its transition spinner.
  private var modeSection: some View {
    Section {
      Toggle(
        String(
          localized: "settings.sync.toggle", defaultValue: "Sync with iCloud", table: "Localizable",
          bundle: MobileL10n.bundle),
        isOn: cloudSyncIsOnBinding
      )
      .accessibilityIdentifier("mobileSettings.cloudSync.mode")

      if let transitionDetail = modeTransitionDetail {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(transitionDetail)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("mobileSettings.cloudSync.inProgress")
      }
    } header: {
      Text(
        String(
          localized: "settings.section.cloud_sync", defaultValue: "Cloud Sync",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(modeDetail)
    }
  }

  private var modeDetail: String {
    switch store.cloudSyncMode {
    case .live:
      return String(
        localized: "settings.sync.detail.on",
        defaultValue:
          "Your tasks, lists, and habits stay the same on every device signed in to your iCloud account.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .off:
      return String(
        localized: "settings.sync.detail.off",
        defaultValue:
          "Your tasks stay on this device. Turn this on to see the same tasks, lists, and habits on your other devices.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// Account and activity rows plus the paused notice, shown while the mode is
  /// Live.
  private var statusSection: some View {
    Section {
      LabeledContent(
        String(
          localized: "settings.sync.account", defaultValue: "Account", table: "Localizable",
          bundle: MobileL10n.bundle), value: syncAccountValue
      )
      .accessibilityIdentifier("mobileSettings.syncAccount")
      if shouldShowICloudSettingsLink {
        MobileSettingsRecoveryLink(
          label: String(
            localized: "settings.sync.open_icloud_settings", defaultValue: "Open Settings",
            table: "Localizable", bundle: MobileL10n.bundle),
          accessibilityIdentifier: "mobileSettings.sync.openICloudSettings")
      }
      if let activityDescription = syncActivityValue {
        LabeledContent(
          String(
            localized: "settings.sync.status", defaultValue: "Status", table: "Localizable",
            bundle: MobileL10n.bundle), value: activityDescription
        )
        .accessibilityIdentifier("mobileSettings.syncStatus")
      }
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
        .foregroundStyle(LorvexDesign.Palette.error)
        .accessibilityIdentifier("mobileSettings.syncLastError")
      }

      if store.cloudSyncPauseReason != nil {
        pausedNotice
      }
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
      .foregroundStyle(LorvexDesign.Palette.warning)
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
    .mobileAccentRowStyle()
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
    case nil:
      return ""
    }
  }

  /// "Delete iCloud Data" is deliberately available regardless of the sync
  /// mode: the common case is a user who turned sync off and wants the cloud
  /// copy gone without re-enabling sync (which would move data) first.
  private var deleteCloudDataSection: some View {
    Section {
      // The in-flight spinner rides the trailing edge rather than replacing
      // the label, so the row keeps its title and its width while it works.
      Button(role: .destructive) {
        showDeleteCloudConfirmation = true
      } label: {
        Label(
          String(
            localized: "settings.sync.delete_cloud.title", defaultValue: "Delete iCloud Data…",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "icloud.slash")
      }
      .mobileDestructiveRowStyle()
      .disabled(
        deleteCloudInProgress || store.isSettingCloudSyncMode || store.isDataImportRunning)
      .overlay(alignment: .trailing) {
        if deleteCloudInProgress { ProgressView() }
      }
      .accessibilityIdentifier("mobileSettings.sync.deleteCloudData")
      .sheet(isPresented: $showDeleteCloudConfirmation) {
        MobileDestructiveConfirmationSheet(
          title: String(
            localized: "settings.sync.delete_cloud.confirm.action",
            defaultValue: "Delete iCloud Data", table: "Localizable", bundle: MobileL10n.bundle),
          message: String(
            localized: "settings.sync.delete_cloud.confirm.message",
            defaultValue:
              "This permanently removes all Lorvex data from your iCloud account, for every device that syncs with it. Data stored on this device stays intact. Sync stays off until you turn it back on.",
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

      if let deleteCloudErrorMessage {
        Label(deleteCloudErrorMessage, systemImage: "exclamationmark.triangle")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.error)
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
        .foregroundStyle(LorvexDesign.Palette.success)
        .accessibilityIdentifier("mobileSettings.sync.deleteCloudData.success")
      }
    } footer: {
      Text(
        String(
          localized: "settings.sync.delete_cloud.footer",
          defaultValue:
            "Delete every Lorvex record from your iCloud account — for all devices that sync with it. Data on this device is not touched. Sync turns off until you re-enable it, which re-uploads this device’s data.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var cloudSyncIsOnBinding: Binding<Bool> {
    Binding(
      get: { store.cloudSyncMode == .live },
      set: { isOn in
        let request = store.makeCloudSyncModeRequest(isOn ? .live : .off)
        Task { await store.setCloudSyncModeFromSettings(request) }
      }
    )
  }

  /// Copy for the spinner row while turning sync on checks the account;
  /// `nil` otherwise.
  private var modeTransitionDetail: String? {
    guard store.isSettingCloudSyncMode else { return nil }
    return String(
      localized: "settings.sync.enabling", defaultValue: "Updating Cloud Sync…",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// Cloud Sync state for the Status row, or `nil` while the user's chosen mode
  /// is Off — the mode footer already covers that case, and a state line for a
  /// sync that will not run would be noise.
  private var syncActivityValue: String? {
    switch store.cloudSyncActivityState {
    case .disabled:
      return nil
    case .checking:
      return String(
        localized: "settings.sync.status.checking", defaultValue: "Checking…", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .upToDate:
      return String(
        localized: "settings.sync.status.up_to_date", defaultValue: "Up to date",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .syncing:
      return String(
        localized: "settings.sync.status.syncing", defaultValue: "Syncing…", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .waiting:
      return String(
        localized: "settings.sync.status.waiting", defaultValue: "Waiting to sync",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
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
    store.lastCloudSyncRemoteChangeErrorMessage
  }

  private var syncLastSuccessValue: String? {
    guard let date = store.lastCloudSyncRemoteChangeSucceededAt else { return nil }
    return LorvexDateFormatters.relative(
      date, to: store.now(), unitsStyle: .abbreviated, dateTimeStyle: .numeric)
  }
}
