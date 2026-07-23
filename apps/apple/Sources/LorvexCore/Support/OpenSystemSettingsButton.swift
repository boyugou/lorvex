import SwiftUI

/// A button that opens the appropriate system settings page.
///
/// On macOS the button label and destination URL are customisable.
/// On iOS it always opens the app's settings page via
/// `UIApplication.openSettingsURLString`.
///
/// Use this in place of the three ad-hoc "Open Settings" button
/// implementations in SettingsCalendarSection, SettingsCloudSyncSection,
/// and NotificationAuthorization to keep platform branching in one place.
public struct OpenSystemSettingsButton: View {
  #if os(macOS)
    /// The button label. Defaults to "Open System Settings".
    public var label: String
    /// The macOS System Settings URL to open. Defaults to the top-level
    /// System Settings pane (`x-apple.systempreferences:`).
    public var settingsURL: URL

    public init(
      label: String = "Open System Settings",
      settingsURL: URL = Self.defaultSettingsURL
    ) {
      self.label = label
      self.settingsURL = settingsURL
    }

    public var body: some View {
      Button(label) {
        NSWorkspace.shared.open(settingsURL)
      }
      .buttonStyle(.bordered)
    }

    public static let defaultSettingsURL =
      URL(string: "x-apple.systempreferences:") ?? URL(fileURLWithPath: "/")
  #elseif os(iOS)
    public var label: String

    public init(label: String = "Open Settings") {
      self.label = label
    }

    public var body: some View {
      Button(label) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
    }
  #else
    public init(label: String = "Open Settings") {}
    public var body: some View { EmptyView() }
  #endif
}
