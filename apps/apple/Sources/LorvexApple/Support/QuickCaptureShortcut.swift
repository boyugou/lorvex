import Carbon.HIToolbox
import Foundation

/// The system-wide shortcut that opens Quick Capture from any app.
///
/// A short list of presets rather than a recorder. Each is a modifier chord
/// with Space, the key launchers use. A Mac that has its input-source shortcuts
/// turned on keeps ⌃Space and ⌃⌥Space for them: the system shortcut wins and
/// the chord never reaches Lorvex, so the list also offers chords no system
/// shortcut owns. `off` is the default: Lorvex claims no key chord until the
/// user chooses one.
enum QuickCaptureShortcut: String, CaseIterable, Identifiable, Sendable {
  case off
  case controlOptionSpace
  case controlSpace
  case optionSpace
  case controlShiftSpace

  var id: String { rawValue }

  static let `default`: QuickCaptureShortcut = .off

  /// The Carbon virtual key code and modifier mask `RegisterEventHotKey` takes;
  /// `nil` when the shortcut is off.
  var chord: (keyCode: UInt32, modifiers: UInt32)? {
    let space = UInt32(kVK_Space)
    switch self {
    case .off: return nil
    case .controlOptionSpace: return (space, UInt32(controlKey | optionKey))
    case .controlSpace: return (space, UInt32(controlKey))
    case .optionSpace: return (space, UInt32(optionKey))
    case .controlShiftSpace: return (space, UInt32(controlKey | shiftKey))
    }
  }

  /// The modifier glyphs in the order macOS writes them, such as "⌃⌥"; empty
  /// when the shortcut is off.
  var modifierGlyphs: String {
    switch self {
    case .off: ""
    case .controlOptionSpace: "⌃⌥"
    case .controlSpace: "⌃"
    case .optionSpace: "⌥"
    case .controlShiftSpace: "⌃⇧"
    }
  }

  /// The label a picker shows: the chord as the system writes it ("⌃⌥Space",
  /// with the key's name in the app's language), or "Off".
  var localizedTitle: String {
    guard chord != nil else {
      return String(
        localized: "settings.quick_capture.off", defaultValue: "Off", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    let space = String(
      localized: "settings.quick_capture.key.space", defaultValue: "Space", table: "Localizable",
      bundle: LorvexL10n.bundle)
    return modifierGlyphs + space
  }
}
