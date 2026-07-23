import LorvexCore
import SwiftUI
import UserNotifications

/// Settings panel listing implemented app permissions with their current status
/// and a per-row action to request access or open System Settings when access
/// has been denied.
public struct PermissionsStatusView: View {
  @State private var viewModel = PermissionsStatusViewModel()

  public init() {}

  public var body: some View {
    List {
      Section(
        String(
          localized: "permissions.section.app", defaultValue: "App Permissions",
          table: "Localizable", bundle: MobileL10n.bundle)
      ) {
        PermissionRow(
          identifier: "notifications",
          label: String(
            localized: "permissions.notifications", defaultValue: "Notifications",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "bell.badge",
          status: viewModel.notificationsStatus,
          needsSettings: viewModel.notificationsNeedsSettings,
          requestAction: {
            _ = try? await UNUserNotificationCenter.current()
              .requestAuthorization(options: [.alert, .sound, .badge])
            await viewModel.refresh()
          }
        )

      }

      Section {
        Text(
          String(
            localized: "permissions.footer",
            defaultValue: "Lorvex requests permissions only at meaningful moments. Tap \"Open Settings\" to adjust access in System Settings.",
            table: "Localizable",
            bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(
      String(
        localized: "settings.section.permissions", defaultValue: "Permissions",
        table: "Localizable", bundle: MobileL10n.bundle)
    )
    .task { await viewModel.refresh() }
    .accessibilityIdentifier("mobilePermissions.status")
  }
}

private struct PermissionRow: View {
  /// Stable, English-derived row identity used for the test accessibility ID;
  /// kept separate from `label` so localizing the visible text never shifts the ID.
  let identifier: String
  let label: String
  let systemImage: String
  let status: PermissionsStatusViewModel.PermissionStatus
  let needsSettings: Bool
  let requestAction: (() async -> Void)?

  var body: some View {
    HStack {
      Label(label, systemImage: systemImage)
      Spacer()
      statusBadge
      if needsSettings {
        openSettingsLink
      } else if let request = requestAction, status == .notDetermined {
        requestButton(action: request)
      }
    }
    .accessibilityIdentifier("permissionRow.\(identifier)")
  }

  private var statusBadge: some View {
    Text(status.displayTitle)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(status.foregroundStyle)
  }

  private var openSettingsLink: some View {
    Link(
      String(
        localized: "permissions.open_settings", defaultValue: "Open Settings", table: "Localizable",
        bundle: MobileL10n.bundle), destination: LorvexNotificationSettingsURL.settingsURL
    )
    .font(LorvexDesign.Typography.tertiaryText)
  }

  private func requestButton(action: @escaping () async -> Void) -> some View {
    Button(
      String(
        localized: "permissions.request", defaultValue: "Request", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      Task { await action() }
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .buttonStyle(.borderless)
  }
}

extension PermissionsStatusViewModel.PermissionStatus {
  fileprivate var displayTitle: String {
    switch self {
    case .unknown:
      return String(
        localized: "permissions.status.unknown", defaultValue: "Unknown", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .notDetermined:
      return String(
        localized: "permissions.status.not_set", defaultValue: "Not Set", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .authorized, .provisional:
      return String(
        localized: "permissions.status.allowed", defaultValue: "Allowed", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .denied:
      return String(
        localized: "permissions.status.denied", defaultValue: "Denied", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  fileprivate var foregroundStyle: some ShapeStyle {
    switch self {
    case .authorized, .provisional: return AnyShapeStyle(Color.green)
    case .denied: return AnyShapeStyle(Color.red)
    default: return AnyShapeStyle(Color.secondary)
    }
  }
}
