import LorvexCore
import SwiftUI
import UserNotifications

/// The notification permission as one Settings row: its current status at the
/// trailing edge, with the action that status calls for beside it. While iOS
/// has not asked yet the row offers Allow, which presents the system prompt;
/// once the user has declined, iOS never prompts again, so the row links to
/// Lorvex's page in the Settings app instead. The status is re-read whenever
/// the app returns to the foreground, since it changes outside the app.
struct MobileNotificationPermissionRow: View {
  /// Invoked after authorization is newly granted from this row. Granting
  /// writes nothing to the database and keeps the user in the app, so the
  /// caller re-plans existing reminders here rather than waiting for the next
  /// foreground or write.
  let onAuthorized: () async -> Void
  @State private var viewModel = PermissionsStatusViewModel()
  @State private var isRequesting = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    HStack {
      Text(
        String(
          localized: "permissions.notifications", defaultValue: "Notifications",
          table: "Localizable", bundle: MobileL10n.bundle))
      Spacer()
      trailing
    }
    .task { await viewModel.refresh() }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task { await viewModel.refresh() }
    }
    .accessibilityIdentifier("mobileSettings.notificationPermission")
  }

  @ViewBuilder
  private var trailing: some View {
    switch viewModel.notificationsStatus {
    case .notDetermined:
      Button {
        isRequesting = true
        Task {
          _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
          await viewModel.refresh()
          isRequesting = false
          if viewModel.notificationsStatus == .authorized
            || viewModel.notificationsStatus == .provisional
          {
            await onAuthorized()
          }
        }
      } label: {
        Text(
          String(
            localized: "settings.notifications.allow", defaultValue: "Allow",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(isRequesting)
      .accessibilityIdentifier("mobileSettings.notificationPermission.allow")
    case .denied:
      Link(
        String(
          localized: "permissions.open_settings", defaultValue: "Open Settings",
          table: "Localizable", bundle: MobileL10n.bundle),
        destination: LorvexNotificationSettingsURL.settingsURL)
      .accessibilityIdentifier("mobileSettings.notificationPermission.openSettings")
    case .authorized, .provisional:
      Text(
        String(
          localized: "permissions.status.allowed", defaultValue: "Allowed",
          table: "Localizable", bundle: MobileL10n.bundle))
      .foregroundStyle(.secondary)
    case .unknown:
      EmptyView()
    }
  }
}
