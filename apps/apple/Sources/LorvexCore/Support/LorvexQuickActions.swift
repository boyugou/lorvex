import Foundation

/// Catalog of platform-level quick action identifiers shared between the macOS
/// Dock right-click menu and the iOS Home Screen long-press shortcut items.
///
/// Each case carries the stable string type used in `UIApplicationShortcutItem`
/// declarations and the display metadata (localized title, SF Symbol name) used
/// when building the corresponding menu or shortcut item on each platform.
public enum LorvexQuickAction: String, CaseIterable, Sendable {
  /// Presents quick task capture immediately: the capture sheet on iOS/iPadOS,
  /// the focused inline quick-add field on macOS.
  case quickCapture = "com.lorvex.apple.quickCapture"
  /// Navigates to the Today view showing the current focus plan and task list.
  case openToday = "com.lorvex.apple.openToday"

  /// The type string used in `UIApplicationShortcutItem` declarations. Matches
  /// the case's raw value.
  public var typeIdentifier: String { rawValue }

  /// Short user-visible label shown in the Dock menu and the Home Screen
  /// long-press shortcut list.
  public var localizedTitle: String {
    switch self {
    case .quickCapture: "Quick Capture"
    case .openToday: "Open Today"
    }
  }

  /// SF Symbol name rendered next to the action title on both platforms.
  public var systemImageName: String {
    switch self {
    case .quickCapture: "square.and.pencil"
    case .openToday: "sun.max"
    }
  }

  /// The deep-link URL that, when opened by the app, routes to the action's
  /// corresponding destination or triggers the action directly.
  public var deepLinkURL: URL {
    switch self {
    case .quickCapture:
      // Cold-launch fallback destination (e.g. a macOS Dock activation that
      // cannot run the in-app capture command). A running app presents the
      // capture affordance directly and does not open this URL.
      LorvexDeepLinkContract.destinationURL(.tasks)
    case .openToday:
      LorvexDeepLinkContract.destinationURL(.today)
    }
  }

  /// Constructs a `LorvexQuickAction` from a `UIApplicationShortcutItem` type
  /// string, or returns `nil` when the identifier is unrecognised.
  public init?(typeIdentifier: String) {
    self.init(rawValue: typeIdentifier)
  }
}
