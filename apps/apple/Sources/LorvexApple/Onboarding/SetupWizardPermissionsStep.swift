import AppKit
import LorvexCore
import SwiftUI

/// The permissions page: Calendar and Notifications in one group, each with
/// its own Allow button. Both are optional, so Continue moves on whatever was
/// chosen, and a permission left alone is simply not asked for.
struct PermissionsStep: View {
  @Bindable var store: AppStore
  @Bindable var settings: AppSettingsStore
  @Bindable var wizardState: SetupWizardState
  let onNext: () -> Void

  var body: some View {
    SetupWizardPage(
      systemImage: "lock.shield",
      title: LocalizedStringResource("setup.permissions.title", defaultValue: "Permissions", table: "Localizable", bundle: LorvexL10n.bundle),
      subtitle: LocalizedStringResource("setup.permissions.subtitle", defaultValue: "Calendar and Notifications are optional, and you can change them later in Settings.", table: "Localizable", bundle: LorvexL10n.bundle)
    ) {
      VStack(spacing: 0) {
        PermissionRequestRow(
          icon: "calendar",
          title: String(localized: "setup.permissions.calendar.title", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle),
          description: String(localized: "setup.permissions.calendar.description", defaultValue: "Import event titles, times, locations, notes, and recurrence details for planning. Calendar data may be available to connected assistants.", table: "Localizable", bundle: LorvexL10n.bundle),
          state: wizardState.calendarPermissionState,
          onRequest: { Task { await wizardState.requestCalendarPermission(store: store, settings: settings) } },
          onOpenSettings: openCalendarSettings
        )
        // Inset to the text column, past the row's icon.
        Divider().padding(.leading, PermissionRequestRow.textInset)
        PermissionRequestRow(
          icon: "bell",
          title: String(localized: "setup.permissions.notifications.title", defaultValue: "Notifications", table: "Localizable", bundle: LorvexL10n.bundle),
          description: String(localized: "setup.permissions.notifications.description", defaultValue: "Receive task reminders as system notifications.", table: "Localizable", bundle: LorvexL10n.bundle),
          state: wizardState.notificationsPermissionState,
          onRequest: { Task { await wizardState.requestNotificationsPermission() } },
          onOpenSettings: openNotificationSettings
        )
      }
      .lorvexInsetPanel(padding: 0)
    } actions: {
      SetupWizardPrimaryButton(String(localized: "setup.action.continue", defaultValue: "Continue", table: "Localizable", bundle: LorvexL10n.bundle), action: onNext)
    }
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

/// One permission in the group: its icon, name, and what it grants, with an
/// Allow button until it is asked for, then the answer (and, when denied, a
/// way to System Settings, since the app cannot ask twice).
private struct PermissionRequestRow: View {
  let icon: String
  let title: String
  let description: String
  let state: SetupPermissionState
  let onRequest: () -> Void
  let onOpenSettings: () -> Void

  private static let horizontalPadding: CGFloat = 14
  private static let iconWidth: CGFloat = 24
  private static let iconSpacing: CGFloat = 12
  /// Where the row's text starts, for a divider drawn under it.
  static let textInset = horizontalPadding + iconWidth + iconSpacing

  var body: some View {
    HStack(alignment: .top, spacing: Self.iconSpacing) {
      Image(systemName: icon)
        .frame(width: Self.iconWidth)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.medium)
        Text(description)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Self.iconSpacing)
      statusOrAction
    }
    .padding(.horizontal, Self.horizontalPadding)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var statusOrAction: some View {
    switch state {
    case .idle:
      Button(String(localized: "setup.permissions.allow", defaultValue: "Allow", table: "Localizable", bundle: LorvexL10n.bundle), action: onRequest)
        .buttonStyle(.bordered)
        .controlSize(.small)
    case .requesting:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(Text(String(localized: "setup.permissions.requesting", defaultValue: "Requesting", table: "Localizable", bundle: LorvexL10n.bundle)))
    case .granted:
      Label(String(localized: "setup.permissions.allowed", defaultValue: "Allowed", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "checkmark.circle.fill")
        .foregroundStyle(LorvexDesign.Palette.success)
        .font(LorvexDesign.Typography.tertiaryText)
    case .denied:
      VStack(alignment: .trailing, spacing: LorvexDesign.Spacing.xs) {
        Label(String(localized: "setup.permissions.denied", defaultValue: "Denied", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "xmark.circle.fill")
          .foregroundStyle(LorvexDesign.Palette.error)
          .font(LorvexDesign.Typography.tertiaryText)
        Button(String(localized: "setup.permissions.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: LorvexL10n.bundle), action: onOpenSettings)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
  }
}
