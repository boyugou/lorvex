import Foundation
import LorvexCore
import UserNotifications

/// Observable view model for the Permissions panel.
///
/// Reports current authorization status for permissions that the mobile app
/// actually requests today.
/// Exposes `needsSettingsRecovery` per permission so the UI can
/// show an "Open Settings" link instead of a "Request" button.
@MainActor
@Observable
public final class PermissionsStatusViewModel {
  public enum PermissionStatus: String, Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case provisional
  }

  public private(set) var notificationsStatus: PermissionStatus = .unknown

  public var notificationsNeedsSettings: Bool {
    notificationsStatus == .denied
  }

  public init() {}

  /// Refreshes all permission statuses from the system.
  public func refresh() async {
    await refreshNotifications()
  }

  private func refreshNotifications() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined: notificationsStatus = .notDetermined
    case .denied: notificationsStatus = .denied
    case .authorized: notificationsStatus = .authorized
    case .provisional: notificationsStatus = .provisional
    case .ephemeral: notificationsStatus = .authorized
    @unknown default: notificationsStatus = .unknown
    }
  }
}
