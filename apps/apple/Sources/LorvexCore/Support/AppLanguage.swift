import CoreFoundation
import Foundation

/// User-selectable in-app UI language, shared by every Apple surface.
///
/// `.system` follows the system language; every other case forces one shipped
/// localization, and there is one case per shipped localization (a test
/// compares the cases with the languages the string catalogs carry). The raw
/// values are the bundle's localization identifiers.
///
/// The choice is stored as the app's own `AppleLanguages` preference, the same
/// value the system's per-app language setting writes (on Lorvex's page in iOS
/// Settings, and under macOS System Settings > General > Language & Region >
/// Applications), so the in-app picker and the system setting always agree.
/// The bundle reads the preference once, at launch: a change takes effect
/// after the app is relaunched (macOS can relaunch itself; iOS asks the user
/// to reopen the app).
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case en
  case ar
  case es
  case fr
  case hi
  case it
  case ja
  case ko
  case pl
  case ptBR = "pt-BR"
  case ru
  case uk
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"

  public var id: String { rawValue }

  /// The selectable languages (everything except `.system`), in menu order.
  public static var selectable: [AppLanguage] { allCases.filter { $0 != .system } }

  /// The language the bundles fall back to when no preferred language is
  /// shipped: the catalogs' source language and every bundle's
  /// `CFBundleDevelopmentRegion`.
  static let developmentLanguage = AppLanguage.en

  /// Native display name (endonym). Endonyms are language-neutral, so each
  /// reads the same regardless of the current UI language; `.system` has no
  /// endonym and is labeled by the caller.
  public var endonym: String {
    switch self {
    case .system: ""
    case .en: "English"
    case .ar: "العربية"
    case .es: "Español"
    case .fr: "Français"
    case .hi: "हिन्दी"
    case .it: "Italiano"
    case .ja: "日本語"
    case .ko: "한국어"
    case .pl: "Polski"
    case .ptBR: "Português (Brasil)"
    case .ru: "Русский"
    case .uk: "Українська"
    case .zhHans: "简体中文"
    case .zhHant: "繁體中文"
    }
  }

  /// Whether the language's script reads right to left (Arabic). `.system`
  /// reads the way the language it resolves to does.
  public var readsRightToLeft: Bool {
    Locale.Language(identifier: resolved.rawValue).characterDirection == .rightToLeft
  }

  private static let appleLanguagesKey = "AppleLanguages"

  /// The language the app is set to: the shipped language its own
  /// `AppleLanguages` preference selects, or `.system` when it has none.
  ///
  /// Only the app's own preference domain is read. A `UserDefaults` lookup
  /// also falls through to launch arguments and to the system-wide language
  /// list, so it would report an `-AppleLanguages` argument, or a system
  /// language written as a bare code such as `en`, as a choice made in the app.
  public static var current: AppLanguage {
    current(applicationID: kCFPreferencesCurrentApplication)
  }

  /// ``current``, read from the preferences of `applicationID`.
  static func current(applicationID: CFString) -> AppLanguage {
    let codes =
      CFPreferencesCopyValue(
        appleLanguagesKey as CFString, applicationID, kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost)
      as? [String]
    guard let codes, !codes.isEmpty else { return .system }
    return shippedLanguage(forPreferredLanguages: codes)
  }

  /// Make this the app's language from the next launch on: store its code as
  /// the app's `AppleLanguages` preference, or remove the preference for
  /// `.system`.
  public func apply() {
    apply(applicationID: kCFPreferencesCurrentApplication)
  }

  /// ``apply()``, written to the preferences of `applicationID`.
  func apply(applicationID: CFString) {
    let value: CFPropertyList? = self == .system ? nil : [rawValue] as CFArray
    CFPreferencesSetValue(
      Self.appleLanguagesKey as CFString, value, applicationID, kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost)
    CFPreferencesAppSynchronize(applicationID)
  }

  /// The shipped language a preferred-language list selects, matched the way
  /// a bundle matches it. The first code whose language is shipped wins, and a
  /// regional code selects its language (`es-MX` selects `es`, `ja-JP` selects
  /// `ja`, `ko-KR` selects `ko`). A list naming no shipped language selects the
  /// development language.
  ///
  /// Chinese is matched by script, and a code without a script gets the script
  /// its region writes. Both scripts are shipped, so Foundation resolves
  /// `zh-Hant`, every `zh-Hant-*` code, and the Taiwan, Hong Kong, and Macau
  /// regions (`zh-TW`, `zh-HK`, `zh-MO`) to `zh-Hant`, and resolves `zh-Hans`,
  /// every `zh-Hans-*` code, the mainland and Singapore regions (`zh-CN`,
  /// `zh-SG`), and bare `zh` to `zh-Hans`. An explicit script wins over the
  /// region (`zh-Hans-HK` selects `zh-Hans`), so a code never crosses scripts.
  ///
  /// A language with no localization of its own selects the shipped language
  /// Foundation falls back to for it, as the bundle does: Cantonese
  /// (`yue-Hant-HK`, `yue-HK`, `yue`) selects `zh-Hant`, and `yue-Hans-CN`
  /// selects `zh-Hans`. A language Foundation has no fallback for is skipped.
  public static func shippedLanguage(forPreferredLanguages codes: [String]) -> AppLanguage {
    let shipped = selectable.map(\.rawValue)
    // What Foundation answers when nothing matches: its answer for a
    // private-use code that no localization serves.
    let noMatch = Bundle.preferredLocalizations(from: shipped, forPreferences: ["qaa"]).first
    for code in codes {
      // An answer other than the no-match one is a real match, including
      // Foundation's own fallbacks across languages (Cantonese to Traditional
      // Chinese). The no-match answer counts only in the code's own language.
      guard
        let match = Bundle.preferredLocalizations(from: shipped, forPreferences: [code]).first,
        match != noMatch
          || Locale.Language(identifier: match).languageCode
            == Locale.Language(identifier: code).languageCode,
        let language = AppLanguage(rawValue: match)
      else { continue }
      return language
    }
    return developmentLanguage
  }

  /// The shipped language the system language list selects: what the app
  /// shows while it follows the system. An `-AppleLanguages` launch argument,
  /// which Xcode's scheme language option and the capture scripts pass to
  /// stand in for a system language, takes the system-wide list's place.
  public static var systemLanguage: AppLanguage {
    let launchArgument =
      UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[
        appleLanguagesKey] as? [String]
    let systemWide =
      CFPreferencesCopyValue(
        appleLanguagesKey as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost) as? [String]
    return shippedLanguage(forPreferredLanguages: launchArgument ?? systemWide ?? [])
  }

  /// The language the running app shows. The bundle resolves it once, at
  /// launch, so it stays fixed for the process however the preference changes.
  public static var running: AppLanguage {
    Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(rawValue:))
      ?? shippedLanguage(forPreferredLanguages: Bundle.main.preferredLocalizations)
  }

  /// The shipped language the app shows once this choice takes effect.
  public var resolved: AppLanguage {
    self == .system ? Self.systemLanguage : self
  }

  /// Whether this choice shows a different language than the running app,
  /// so applying it needs a relaunch.
  public var needsRelaunch: Bool { resolved != Self.running }
}
