import SwiftUI

/// User-selectable app appearance. `system` follows the OS light/dark setting;
/// `light` and `dark` force a fixed scheme regardless of the OS. Shared by the
/// macOS settings store and the mobile/visionOS root so all surfaces expose the
/// same three choices and persist under the same key.
public enum AppAppearance: String, CaseIterable, Sendable, Identifiable {
  case system
  case light
  case dark

  public var id: String { rawValue }

  /// Picker label.
  public var label: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// SF Symbol for the choice.
  public var symbolName: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max"
    case .dark: "moon"
    }
  }

  /// The SwiftUI color scheme to force via `.preferredColorScheme`, or `nil` to
  /// follow the system. macOS maps this to an `NSAppearance` app-wide instead.
  public var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  /// Shared `UserDefaults` / `@AppStorage` key for the persisted choice.
  public static let preferenceKey = "appAppearance"
}
