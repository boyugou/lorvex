import Foundation

/// The platform-specific URL to open the app's notification settings page.
///
/// On iOS, opens UIApplication.openSettingsURLString. On macOS, opens the
/// Notification preferences pane in System Settings.
public enum LorvexNotificationSettingsURL {
  #if os(iOS) || os(visionOS)
    public static let settingsURL = URL(string: "app-settings:") ?? URL(fileURLWithPath: "/")
  #elseif os(macOS)
    public static let settingsURL = URL(
      string: "x-apple.systempreferences:com.apple.preference.notifications"
    ) ?? URL(fileURLWithPath: "/")
  #else
    public static let settingsURL: URL? = nil
  #endif
}
