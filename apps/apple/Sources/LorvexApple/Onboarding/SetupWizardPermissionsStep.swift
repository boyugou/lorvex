import AppKit
import LorvexCore
import SwiftUI

struct PermissionsStep: View {
  @Bindable var store: AppStore
  @Bindable var settings: AppSettingsStore
  @Bindable var wizardState: SetupWizardState
  let onNext: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      stepHeader(
        icon: "lock.shield",
        title: String(localized: "setup.permissions.title", defaultValue: "Permissions", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(localized: "setup.permissions.subtitle", defaultValue: "Lorvex can integrate with Calendar and Notifications. Each is optional.", table: "Localizable", bundle: LorvexL10n.bundle)
      )

      PermissionRequestRow(
        icon: "calendar",
        title: String(localized: "setup.permissions.calendar.title", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle),
        description: String(localized: "setup.permissions.calendar.description", defaultValue: "Import event titles, times, locations, notes, and recurrence details for planning. Calendar data may be available to connected assistants.", table: "Localizable", bundle: LorvexL10n.bundle),
        state: wizardState.calendarPermissionState,
        onRequest: { Task { await wizardState.requestCalendarPermission(store: store, settings: settings) } },
        onSkip: { wizardState.skipCalendar() },
        onOpenSettings: openCalendarSettings
      )

      PermissionRequestRow(
        icon: "bell",
        title: String(localized: "setup.permissions.notifications.title", defaultValue: "Notifications", table: "Localizable", bundle: LorvexL10n.bundle),
        description: String(localized: "setup.permissions.notifications.description", defaultValue: "Receive task reminders as system notifications.", table: "Localizable", bundle: LorvexL10n.bundle),
        state: wizardState.notificationsPermissionState,
        onRequest: { Task { await wizardState.requestNotificationsPermission() } },
        onSkip: { wizardState.skipNotifications() },
        onOpenSettings: openNotificationSettings
      )

      Spacer()
      nextButton(action: onNext, label: String(localized: "setup.action.continue", defaultValue: "Continue", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .padding(40)
  }

  private func openCalendarSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
      NSWorkspace.shared.open(url)
    }
  }

  private func openNotificationSettings() {
    NSWorkspace.shared.open(LorvexNotificationSettingsURL.settingsURL)
  }
}

private struct PermissionRequestRow: View {
  let icon: String
  let title: String
  let description: String
  let state: SetupPermissionState
  let onRequest: () -> Void
  let onSkip: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .frame(width: 24)
        .foregroundStyle(.tint)

      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.medium)
        Text(description)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }

      Spacer()
      statusOrActions
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var statusOrActions: some View {
    switch state {
    case .idle:
      HStack(spacing: 8) {
        Button(String(localized: "setup.permissions.allow", defaultValue: "Allow", table: "Localizable", bundle: LorvexL10n.bundle), action: onRequest)
          .buttonStyle(.bordered)
          .controlSize(.small)
        Button(String(localized: "setup.permissions.skip", defaultValue: "Skip", table: "Localizable", bundle: LorvexL10n.bundle), action: onSkip)
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .controlSize(.small)
      }
    case .requesting:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(Text(String(localized: "setup.permissions.requesting", defaultValue: "Requesting", table: "Localizable", bundle: LorvexL10n.bundle)))
    case .granted:
      Label(String(localized: "setup.permissions.granted", defaultValue: "Granted", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(LorvexDesign.Typography.tertiaryText)
    case .denied:
      HStack(spacing: 8) {
        Label(String(localized: "setup.permissions.denied", defaultValue: "Denied", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "xmark.circle.fill")
          .foregroundStyle(.orange)
          .font(LorvexDesign.Typography.tertiaryText)
        Button(String(localized: "setup.permissions.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: LorvexL10n.bundle), action: onOpenSettings)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    case .skipped:
      Label(String(localized: "setup.permissions.skipped", defaultValue: "Skipped", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "minus.circle")
        .foregroundStyle(.secondary)
        .font(LorvexDesign.Typography.tertiaryText)
    }
  }
}
