import LorvexCore
import SwiftUI

/// Language picker for the mobile Settings screen. Writes the standard
/// `AppleLanguages` override (via `AppLanguage`), which the bundle reads when it
/// loads its localizations — so the change applies the next time the app is
/// reopened (iOS apps can't relaunch themselves). "System Default" clears the
/// override and follows the OS language.
struct MobileSettingsLanguageSection: View {
  @State private var selection = AppLanguage.current
  @State private var changed = false

  var body: some View {
    Section {
      Picker(
        String(
          localized: "settings.language", defaultValue: "Language", table: "Localizable",
          bundle: MobileL10n.bundle), selection: $selection
      ) {
        Text(
          String(
            localized: "settings.language.system", defaultValue: "System Default",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .tag(AppLanguage.system)
        ForEach(AppLanguage.selectable) { language in
          Text(language.endonym).tag(language)
        }
      }
      // Push a dedicated selection screen (the native Settings idiom for a long
      // option list). The style is iOS/visionOS-only; the module also compiles
      // for the macOS host, which falls back to the default picker.
      #if os(iOS) || os(visionOS)
        .pickerStyle(.navigationLink)
      #endif
      .accessibilityIdentifier("mobileSettings.language")
      .onChange(of: selection) { _, newValue in
        newValue.apply()
        changed = true
      }

      if changed {
        Text(
          String(
            localized: "settings.language.reopen_note",
            defaultValue: "Reopen Lorvex to apply the new language.", table: "Localizable",
            bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("mobileSettings.language.reopenNote")
      }
    } header: {
      Text(
        String(
          localized: "settings.section.language", defaultValue: "Language", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
  }
}
