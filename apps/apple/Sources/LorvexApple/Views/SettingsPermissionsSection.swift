import AppKit
import LorvexCore
import SwiftUI
import UserNotifications

#if canImport(EventKit)
  import EventKit
#endif

/// macOS Settings tab listing Calendar and Notifications permission statuses
/// with recovery links to System Preferences.
struct SettingsPermissionsSection: View {
  @Bindable var store: AppStore
  @Bindable var settings: AppSettingsStore
  @State private var notificationsStatus: PermissionRowStatus = .unknown
  @State private var calendarStatus: PermissionRowStatus = .unknown
  @State private var showTaskNotesInNotifications = false

  var body: some View {
    Section(String(
      localized: "settings.permissions.status_section",
      defaultValue: "Permission Status",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )) {
      PermissionStatusRow(
        id: "notifications",
        label: String(
          localized: "settings.permissions.notifications",
          defaultValue: "Notifications",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "bell.badge",
        status: notificationsStatus,
        settingsURL: LorvexNotificationSettingsURL.settingsURL,
        requestAction: { await requestNotificationsAccess() }
      )
      PermissionStatusRow(
        id: "calendar",
        label: String(
          localized: "settings.permissions.calendar",
          defaultValue: "Calendar",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "calendar",
        status: calendarStatus,
        settingsURL: Self.calendarPrivacySettingsURL,
        requestAction: { await requestCalendarAccess() }
      )
    }
    // Read the live authorization states whenever the tab appears (and again
    // when re-selected) — without this every row stays on its `.unknown`
    // initial value.
    .task { await refresh() }
    // Notifications (and Calendar once denied) can only be re-granted
    // in System Settings, which leaves this window untouched. Re-poll whenever
    // the app regains focus so returning from System Settings reflects the new
    // status instead of showing a stale "Denied".
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await refresh() }
    }

    Section(String(localized: "settings.permissions.badge_section", defaultValue: "Badge", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Toggle(isOn: badgeBinding) {
        Text(LocalizedStringResource(
          "settings.permissions.badge_due_tasks",
          defaultValue: "Badge app icon with due-task count",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
      }
      .accessibilityIdentifier("macSettings.badgeEnabled")
      Text(LocalizedStringResource(
        "settings.permissions.badge_footer",
        defaultValue: "Shows the number of overdue and due-today open tasks on the Dock icon.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    }

    Section(String(
      localized: "settings.permissions.notification_content_section", defaultValue: "Notification Content",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )) {
      Toggle(isOn: showTaskNotesBinding) {
        Text(LocalizedStringResource(
          "settings.permissions.show_task_notes",
          defaultValue: "Show task notes in notifications",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
      }
      .accessibilityIdentifier("macSettings.showTaskNotesInNotifications")
      Text(LocalizedStringResource(
        "settings.permissions.show_task_notes_footer",
        defaultValue: "When off, reminders show only the task title — never your notes — on the lock screen and banners.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    }
    .task { showTaskNotesInNotifications = await store.loadShowTaskNotesInNotificationsPreference() }
  }

  /// Trigger the native permission prompt and reflect the result immediately.
  ///
  /// `EKEventStore.authorizationStatus(for:)` and the notification settings read
  /// can return a process-cached `notDetermined`/`denied` for the rest of the
  /// session right after a grant (it only refreshes on the next launch), so the
  /// row would stay "Not Set" until an app restart. The request's own `granted`
  /// result is authoritative for the decision just made, so apply it directly
  /// after `refresh()` rather than trusting the stale status read.
  private func requestNotificationsAccess() async {
    let granted = (try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    await refresh()
    if granted { notificationsStatus = .authorized }
  }

  /// Drive the calendar grant through the app's own EventKit store so it latches,
  /// resets, and re-ingests — the calendar populates immediately and the status
  /// sticks (no relaunch). The latch is set by the access layer; refresh() reads
  /// it back.
  private func requestCalendarAccess() async {
    let granted = await store.requestCalendarAccessFromSettings()
    await refresh()
    if granted {
      calendarStatus = .authorized
    } else if calendarStatus == .notDetermined {
      calendarStatus = .denied
    }
  }

  private var badgeBinding: Binding<Bool> {
    Binding(
      get: { settings.badgeEnabled },
      set: {
        settings.badgeEnabled = $0
        store.badgeEnabled = $0
        Task { await store.updateBadge() }
      }
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

extension SettingsPermissionsSection {
  private static let calendarPrivacySettingsURL =
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")

  func refresh() async {
    let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
    let notif: PermissionRowStatus
    switch notifSettings.authorizationStatus {
    case .notDetermined: notif = .notDetermined
    case .denied: notif = .denied
    case .authorized, .provisional, .ephemeral: notif = .authorized
    @unknown default: notif = .unknown
    }
    notificationsStatus = Self.resolve(read: notif, current: notificationsStatus)

    #if canImport(EventKit)
      calendarStatus = Self.resolve(
        read: latched(Self.map(EKEventStore.authorizationStatus(for: .event)),
          key: EventKitAccessLatch.calendarKey),
        current: calendarStatus)
    #endif
  }

  /// Treat a stale in-process `notDetermined` as authorized when the persisted
  /// grant latch is set — EventKit's static status lags an in-app grant for the
  /// rest of the session, which would otherwise show "Not Set" until restart.
  /// A real `denied`/`restricted` read is never overridden (it isn't
  /// `notDetermined`).
  func latched(_ read: PermissionRowStatus, key: String) -> PermissionRowStatus {
    if read == .notDetermined, settings.defaults.bool(forKey: key) { return .authorized }
    return read
  }

  #if canImport(EventKit)
    private static func map(_ status: EKAuthorizationStatus) -> PermissionRowStatus {
      switch status {
      case .notDetermined: .notDetermined
      case .denied, .restricted: .denied
      case .writeOnly: .writeOnly
      case .fullAccess: .authorized
      @unknown default: .unknown
      }
    }
  #endif

  /// Merge a freshly-read authorization status with what we already show.
  ///
  /// `notDetermined` is a one-way door: once macOS records a decision a
  /// permission never returns to "not set". But `EKEventStore`'s static
  /// `authorizationStatus` (and the notification settings read) can keep
  /// returning a process-cached `notDetermined` for the rest of the session
  /// right after the app requests *any* permission — which would wrongly reset
  /// a sibling row (grant Calendar and Notifications flips back to "Not Set",
  /// or vice versa) until an app restart. So a `notDetermined` read over an
  /// already-determined value is treated as stale and discarded.
  static func resolve(read: PermissionRowStatus, current: PermissionRowStatus) -> PermissionRowStatus {
    if read == .notDetermined, current != .notDetermined, current != .unknown {
      return current
    }
    return read
  }
}

enum PermissionRowStatus: Equatable {
  case unknown
  case notDetermined
  case authorized
  /// macOS granted "Add Only": Lorvex can write calendar events but reads
  /// are blocked, so imports fail while a plain "Allowed" would claim
  /// everything works. Recoverable only via System Settings.
  case writeOnly
  case denied
}

private struct PermissionStatusRow: View {
  let id: String
  let label: String
  let systemImage: String
  let status: PermissionRowStatus
  let settingsURL: URL?
  /// Presents the native permission prompt. Only invoked while the status is
  /// `.notDetermined`; for denied/write-only the row shows an Open Settings
  /// link instead, since macOS no longer re-prompts after the first decision.
  var requestAction: (() async -> Void)? = nil
  @State private var isRequesting = false

  var body: some View {
    HStack {
      Label(label, systemImage: systemImage)
      Spacer()
      Text(status.displayTitle)
        .foregroundStyle(status.color)
        .font(LorvexDesign.Typography.secondaryText)
      recoveryControl
    }
    .accessibilityIdentifier("permissionRow.\(id)")
  }

  @ViewBuilder
  private var recoveryControl: some View {
    if status == .notDetermined, let requestAction {
      Button {
        isRequesting = true
        Task {
          await requestAction()
          isRequesting = false
        }
      } label: {
        if isRequesting {
          ProgressView().controlSize(.small)
        } else {
          Text(LocalizedStringResource("setup.permissions.allow", defaultValue: "Allow", table: "Localizable", bundle: LorvexL10n.bundle))
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(isRequesting)
      .accessibilityIdentifier("permissionRow.\(id).allow")
    } else if status == .denied || status == .writeOnly {
      if let settingsURL {
        Link(
          String(localized: "settings.permissions.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: LorvexL10n.bundle),
          destination: settingsURL
        )
          .font(LorvexDesign.Typography.secondaryText)
      }
    }
  }
}

extension PermissionRowStatus {
  fileprivate var displayTitle: String {
    switch self {
    case .unknown:
      return String(localized: "settings.permissions.status.unknown", defaultValue: "Unknown", table: "Localizable", bundle: LorvexL10n.bundle)
    case .notDetermined:
      return String(localized: "settings.permissions.status.not_set", defaultValue: "Not Set", table: "Localizable", bundle: LorvexL10n.bundle)
    case .authorized:
      return String(localized: "settings.permissions.status.allowed", defaultValue: "Allowed", table: "Localizable", bundle: LorvexL10n.bundle)
    case .writeOnly:
      return String(
        localized: "settings.permissions.status.write_only", defaultValue: "Add Only — reads blocked",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .denied:
      return String(localized: "settings.permissions.status.denied", defaultValue: "Denied", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  fileprivate var color: Color {
    switch self {
    case .authorized: return .green
    case .writeOnly: return .orange
    case .denied: return .red
    default: return .secondary
    }
  }
}
