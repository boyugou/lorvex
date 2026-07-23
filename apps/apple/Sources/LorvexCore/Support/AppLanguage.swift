import Foundation

/// User-selectable in-app UI language, shared by every Apple surface.
///
/// `.system` follows the OS language; every other case forces one of the
/// shipped localizations. The choice is applied by writing the standard
/// `AppleLanguages` `UserDefaults` override, which the bundle reads when it
/// loads its localizations — so a change only takes effect after the app is
/// relaunched (macOS can relaunch itself; iOS asks the user to reopen). The raw
/// values are the bundle's localization identifiers.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case en
  case de
  case es
  case fr
  case it
  case ja
  case ko
  case pl
  case pt
  case ru
  case tr
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"

  public var id: String { rawValue }

  /// The `AppleLanguages` code to force, or `nil` for `.system`.
  public var localeCode: String? { self == .system ? nil : rawValue }

  /// The selectable languages (everything except `.system`), in menu order.
  public static var selectable: [AppLanguage] { allCases.filter { $0 != .system } }

  /// Native display name (endonym). Endonyms are language-neutral, so each
  /// reads the same regardless of the current UI language; `.system` has no
  /// endonym and is labeled by the caller.
  public var endonym: String {
    switch self {
    case .system: ""
    case .en: "English"
    case .de: "Deutsch"
    case .es: "Español"
    case .fr: "Français"
    case .it: "Italiano"
    case .ja: "日本語"
    case .ko: "한국어"
    case .pl: "Polski"
    case .pt: "Português"
    case .ru: "Русский"
    case .tr: "Türkçe"
    case .zhHans: "简体中文"
    case .zhHant: "繁體中文"
    }
  }

  private static let appleLanguagesKey = "AppleLanguages"

  /// The currently-applied language from the `AppleLanguages` override's first
  /// entry, or `.system` when no override is set.
  public static var current: AppLanguage {
    guard let first = UserDefaults.standard.stringArray(forKey: appleLanguagesKey)?.first
    else { return .system }
    return AppLanguage(rawValue: first) ?? .system
  }

  /// Write this choice to `AppleLanguages`. Takes effect on the next launch.
  public func apply() {
    let defaults = UserDefaults.standard
    if let code = localeCode {
      defaults.set([code], forKey: Self.appleLanguagesKey)
    } else {
      defaults.removeObject(forKey: Self.appleLanguagesKey)
    }
  }
}
