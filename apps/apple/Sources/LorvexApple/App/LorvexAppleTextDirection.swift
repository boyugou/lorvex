import Foundation
import LorvexCore

/// Lays the Mac app out in the direction of the language it shows.
///
/// AppKit mirrors the interface for a right-to-left localization only while
/// the `AppleTextDirection` default is on, and the value AppKit registers for
/// that default follows the system's language list, not the app's. An app
/// running in Arabic on a system set to a left-to-right language (chosen in
/// the language picker in Settings, under System Settings > General >
/// Language & Region > Applications, or with an `-AppleLanguages` launch
/// argument) would otherwise show Arabic text laid out left to right.
enum LorvexAppleTextDirection {
  static let defaultsKey = "AppleTextDirection"

  /// Turns `AppleTextDirection` on for this process when the language the app
  /// runs in reads right to left. The value goes into the launch-argument
  /// domain, so nothing is stored and every launch decides afresh. AppKit
  /// reads the default once, the first time it lays anything out, so this
  /// runs before the first window or menu exists.
  static func alignWithRunningLanguage() {
    let defaults = UserDefaults.standard
    let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    guard let aligned = alignedArguments(arguments, showing: .running) else { return }
    // Setting a volatile domain replaces its whole dictionary, so `aligned`
    // carries every other launch argument along.
    defaults.setVolatileDomain(aligned, forName: UserDefaults.argumentDomain)
  }

  /// The launch arguments with the text direction turned on, or nil when they
  /// need no change: the language reads left to right (AppKit lays a
  /// left-to-right localization out left to right even on a right-to-left
  /// system), or an explicit `-AppleTextDirection` argument already decides.
  static func alignedArguments(_ arguments: [String: Any], showing language: AppLanguage)
    -> [String: Any]?
  {
    guard language.readsRightToLeft, arguments[defaultsKey] == nil else { return nil }
    var aligned = arguments
    aligned[defaultsKey] = true
    return aligned
  }
}
