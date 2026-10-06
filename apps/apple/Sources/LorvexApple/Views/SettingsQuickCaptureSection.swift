import LorvexCore
import SwiftUI

/// Settings control for the system-wide Quick Capture shortcut, in a group of
/// its own so its explanation is the footer directly under it. The picker
/// writes the choice straight to ``AppSettingsStore/quickCaptureShortcut``,
/// which registers or releases the chord.
struct SettingsQuickCaptureSection: View {
  @Bindable var settings: AppSettingsStore

  var body: some View {
    Section {
      Picker(AppCommand.quickCapture.title, selection: $settings.quickCaptureShortcut) {
        ForEach(QuickCaptureShortcut.allCases) { shortcut in
          Text(shortcut.localizedTitle).tag(shortcut)
        }
      }
      .accessibilityIdentifier("settings.quickCapture.shortcut")
    } footer: {
      SettingsQuickCaptureFooter(
        shortcut: settings.quickCaptureShortcut,
        isAvailable: settings.quickCaptureShortcutIsAvailable)
    }
  }
}

/// The caption under the shortcut picker: how to turn the shortcut on while it
/// is off, how to use it once a chord is chosen, and, when another app already
/// owns the chosen chord, a warning that says so instead of letting the
/// shortcut do nothing without a word.
struct SettingsQuickCaptureFooter: View {
  let shortcut: QuickCaptureShortcut
  /// Whether the system accepted the chosen chord.
  let isAvailable: Bool

  var body: some View {
    if isAvailable {
      Text(Self.caption(for: shortcut))
    } else {
      Label {
        Text(Self.unavailableCaption)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(LorvexDesign.Palette.warning)
      }
      .accessibilityIdentifier("settings.quickCapture.unavailable")
    }
  }

  /// The caption for an accepted choice: the invitation to choose a chord
  /// while the shortcut is off, the instruction once one is set.
  nonisolated static func caption(for shortcut: QuickCaptureShortcut) -> String {
    if shortcut == .off {
      return String(
        localized: "settings.quick_capture.detail.off",
        defaultValue: "Choose a shortcut to add a task from any app without switching to Lorvex.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "settings.quick_capture.detail.on",
      defaultValue: "Press the shortcut in any app to add a task without switching to Lorvex.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The warning for a chord the system refused because another app owns it.
  nonisolated static var unavailableCaption: String {
    String(
      localized: "settings.quick_capture.unavailable",
      defaultValue: "Another app is using this shortcut. Choose a different one.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
