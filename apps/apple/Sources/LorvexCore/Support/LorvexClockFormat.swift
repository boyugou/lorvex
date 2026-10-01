import Foundation
import SwiftUI

/// The user's choice of clock: follow the system's 12/24-hour setting, or
/// always show a 12-hour ("9:45 AM") or 24-hour ("09:45") clock.
///
/// The choice is stored under ``preferenceKey`` in ``defaults``: the App Group
/// suite for a packaged Lorvex process (bundle identifiers under
/// `com.lorvex`), so the app and its widgets read one value, and the process's
/// own domain otherwise, so a debug binary or a test never touches the shipped
/// app's shared settings.
///
/// Every clock label goes through ``LorvexDateFormatters/clockTime(_:timeZone:locale:)``
/// or ``lorvexClockRangeLabel(startMinutes:endMinutes:)``, whose default locale
/// is ``displayLocale``: the current locale with the chosen hour cycle. Views
/// apply ``SwiftUI/View/lorvexClockLocale()`` at their scene root, so a change
/// redraws every label and makes system time pickers follow the same clock.
public enum LorvexClockFormat: String, CaseIterable, Sendable, Identifiable {
  case system
  case twelveHour
  case twentyFourHour

  public var id: String { rawValue }

  /// `UserDefaults` / `@AppStorage` key for the stored choice.
  public static let preferenceKey = "clockFormat"

  /// Where the choice is stored; see the type's documentation.
  /// `UserDefaults` is thread-safe; it is only read and written through its
  /// own API.
  public nonisolated(unsafe) static let defaults: UserDefaults = {
    if Bundle.main.bundleIdentifier?.hasPrefix("com.lorvex") == true,
      let shared = UserDefaults(suiteName: LorvexProductMetadata.appGroupIdentifier)
    {
      return shared
    }
    return .standard
  }()

  /// The stored choice, read on every call; `.system` when none is stored.
  public static var current: LorvexClockFormat {
    defaults.string(forKey: preferenceKey).flatMap(LorvexClockFormat.init(rawValue:)) ?? .system
  }

  /// The current locale with the stored choice's hour cycle.
  public static var displayLocale: Locale {
    current.applied(to: .current)
  }

  /// `locale` with this choice's hour cycle; `locale` unchanged for `.system`.
  public func applied(to locale: Locale) -> Locale {
    let hourCycle: Locale.HourCycle
    switch self {
    case .system: return locale
    case .twelveHour: hourCycle = .oneToTwelve
    case .twentyFourHour: hourCycle = .zeroToTwentyThree
    }
    var components = Locale.Components(locale: locale)
    components.hourCycle = hourCycle
    return Locale(components: components)
  }
}

private struct LorvexClockLocaleModifier: ViewModifier {
  @AppStorage(LorvexClockFormat.preferenceKey, store: LorvexClockFormat.defaults)
  private var format: LorvexClockFormat = .system
  @Environment(\.locale) private var locale

  func body(content: Content) -> some View {
    content.environment(\.locale, format.applied(to: locale))
  }
}

extension View {
  /// Applies the stored ``LorvexClockFormat`` to this view's locale and
  /// redraws it when the choice changes, so clock labels and system time
  /// pickers below follow the chosen clock. Apply it once at each scene root.
  public func lorvexClockLocale() -> some View {
    modifier(LorvexClockLocaleModifier())
  }
}
