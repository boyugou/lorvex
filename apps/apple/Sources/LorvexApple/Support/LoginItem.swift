import ServiceManagement

/// Whether Lorvex opens when the user signs in.
enum LoginItemStatus: Equatable {
  /// Lorvex does not open at login.
  case off
  /// Lorvex opens at login.
  case on
  /// The user turned it on, but it stays inactive until they allow Lorvex in
  /// System Settings > General > Login Items & Extensions.
  case needsApproval
}

/// Reads and changes whether the app opens at login. The system owns the
/// state, and the user can change it in System Settings at any time, so every
/// read asks the system again.
@MainActor
protocol LoginItemControlling: AnyObject {
  var status: LoginItemStatus { get }
  func register() throws
  func unregister() throws
  /// Opens System Settings on the Login Items & Extensions pane.
  func openSystemSettings()
}

/// The app's own login item, kept by ServiceManagement (`SMAppService.mainApp`).
@MainActor
final class SystemLoginItem: LoginItemControlling {
  var status: LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: .on
    case .requiresApproval: .needsApproval
    case .notRegistered, .notFound: .off
    @unknown default: .off
    }
  }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
