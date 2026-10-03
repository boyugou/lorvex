import CoreFoundation
import Foundation
import Testing

@testable import LorvexCore

/// How the app picks its language from the system's and from its own
/// preference. Bundles resolve the language at launch, which a test cannot
/// repeat, so these tests check the matching rules and the preference storage
/// the pickers and the relaunch notes rely on.
struct AppLanguageTests {

  /// System language lists as the OS writes them, and the language each must
  /// select. An entry whose language is not shipped must select the
  /// development language instead, so the table can also pin the identifier a
  /// later language ships under before that language lands.
  private static let systemLanguageExpectations: [(system: [String], selects: String)] = [
    (["en-US"], "en"),
    (["en-GB"], "en"),
    (["en-IN"], "en"),
    (["en"], "en"),
    (["zh"], "zh-Hans"),
    (["zh-Hans"], "zh-Hans"),
    (["zh-Hans-CN"], "zh-Hans"),
    (["zh-Hans-US"], "zh-Hans"),
    (["zh-Hans-HK"], "zh-Hans"),
    (["zh-CN"], "zh-Hans"),
    (["zh-SG"], "zh-Hans"),
    (["zh-Hans-SG"], "zh-Hans"),
    (["zh-Hant"], "zh-Hant"),
    (["zh-Hant-TW"], "zh-Hant"),
    (["zh-Hant-HK"], "zh-Hant"),
    (["zh-Hant-MO"], "zh-Hant"),
    (["zh-Hant-CN"], "zh-Hant"),
    (["zh-TW"], "zh-Hant"),
    (["zh-HK"], "zh-Hant"),
    (["zh-MO"], "zh-Hant"),
    (["yue-Hant-HK"], "zh-Hant"),
    (["yue-HK"], "zh-Hant"),
    (["yue"], "zh-Hant"),
    (["yue-Hans-CN"], "zh-Hans"),
    (["de-DE", "fr-FR"], "fr"),
    (["ja"], "ja"),
    (["ja-JP"], "ja"),
    (["ko"], "ko"),
    (["ko-KR"], "ko"),
    (["es-ES"], "es"),
    (["es-MX"], "es"),
    (["es-419"], "es"),
    (["es-US"], "es"),
    (["fr-FR"], "fr"),
    (["fr-CA"], "fr"),
    (["fr-CH"], "fr"),
    (["it-IT"], "it"),
    (["it-CH"], "it"),
    (["pt-BR"], "pt-BR"),
    (["pt-PT"], "pt-BR"),
    (["hi-IN"], "hi"),
    (["ar-SA"], "ar"),
    (["ru-RU"], "ru"),
    (["ru-KZ"], "ru"),
    (["uk-UA"], "uk"),
    (["pl-PL"], "pl"),
    // The first shipped language in the list wins.
    (["de-DE", "zh-Hans-CN"], "zh-Hans"),
    (["de-DE", "ja-JP"], "ja"),
    (["de-DE", "es-MX", "en-US"], "es"),
    // A list naming no shipped language selects the development language.
    (["de-DE"], "en"),
    ([], "en"),
  ]

  @Test("The picker lists endonyms with the Latin-script names first, then each script together")
  func selectableOrderGroupsScripts() {
    #expect(
      AppLanguage.selectable == [
        .en, .es, .fr, .it, .pl, .ptBR, .ru, .uk, .ar, .hi, .ko, .ja, .zhHans, .zhHant,
      ])
  }

  @Test("A system language selects its shipped language, whatever its region")
  func systemLanguageSelectsItsShippedLanguage() {
    let shipped = Set(AppLanguage.selectable.map(\.rawValue))
    let development = AppLanguage.developmentLanguage.rawValue
    for (system, selects) in Self.systemLanguageExpectations {
      let expected = shipped.contains(selects) ? selects : development
      #expect(
        AppLanguage.shippedLanguage(forPreferredLanguages: system).rawValue == expected,
        "\(system) should select \(expected)")
    }
  }

  @Test("Chinese is matched by script: Traditional and Simplified codes never swap")
  func chineseMatchesByScript() {
    let traditional = [
      ["zh-Hant"], ["zh-Hant-CN"], ["zh-Hant-MO"], ["zh-TW"], ["zh-HK"], ["zh-MO"],
    ]
    for system in traditional {
      #expect(
        AppLanguage.shippedLanguage(forPreferredLanguages: system) == .zhHant, "\(system)")
    }
    let simplified = [["zh"], ["zh-Hans"], ["zh-Hans-HK"], ["zh-Hans-US"], ["zh-CN"], ["zh-SG"]]
    for system in simplified {
      #expect(
        AppLanguage.shippedLanguage(forPreferredLanguages: system) == .zhHans, "\(system)")
    }
  }

  @Test("The app's language is its own preference, never the system-wide list")
  func appLanguageIsTheAppsOwnPreference() {
    let domain = "com.lorvex.tests.app-language" as CFString
    let key = "AppleLanguages" as CFString
    defer { AppLanguage.system.apply(applicationID: domain) }
    AppLanguage.system.apply(applicationID: domain)

    // The system-wide list always holds a language; it is not a choice made
    // in the app.
    #expect(AppLanguage.current(applicationID: domain) == .system)

    AppLanguage.zhHans.apply(applicationID: domain)
    #expect(
      CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        as? [String] == ["zh-Hans"])
    #expect(AppLanguage.current(applicationID: domain) == .zhHans)

    // The system's per-app setting may store a regional code.
    CFPreferencesSetValue(
      key, ["zh-Hans-CN"] as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    #expect(AppLanguage.current(applicationID: domain) == .zhHans)
    CFPreferencesSetValue(
      key, ["zh-TW"] as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    #expect(AppLanguage.current(applicationID: domain) == .zhHant)
    CFPreferencesSetValue(
      key, ["ko-KR"] as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    #expect(AppLanguage.current(applicationID: domain) == .ko)

    AppLanguage.system.apply(applicationID: domain)
    #expect(
      CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) == nil)
    #expect(AppLanguage.current(applicationID: domain) == .system)
  }

  @Test("Following the system shows the system's language; a forced one shows itself")
  func choiceResolvesToTheLanguageItShows() {
    #expect(AppLanguage.system.resolved == AppLanguage.systemLanguage)
    for language in AppLanguage.selectable {
      #expect(language.resolved == language)
    }
    #expect(AppLanguage.systemLanguage != .system)
    #expect(AppLanguage.running != .system)
  }

  @Test("Arabic reads right to left; following the system reads like the system's language")
  func readingDirection() {
    for language in AppLanguage.selectable {
      #expect(language.readsRightToLeft == (language == .ar), "\(language.rawValue)")
    }
    #expect(AppLanguage.system.readsRightToLeft == AppLanguage.systemLanguage.readsRightToLeft)
  }
}
