import LorvexCore
import SwiftUI

/// Language, clock, and time zone rows for the mobile Settings screen. The language
/// picker writes the standard `AppleLanguages` override (via `AppLanguage`),
/// which the bundle reads when it loads its localizations — so the change
/// applies the next time the app is reopened (iOS apps can't relaunch
/// themselves). "System Default" clears the override and follows the OS
/// language. The clock picker (``MobileSettingsClockFormatRow``) and the
/// time zone rows (``MobileSettingsTimeZoneRow``) apply at once.
struct MobileSettingsLanguageSection: View {
  @Bindable var store: MobileStore
  @State private var selection = AppLanguage.current
  @State private var changed = false

  var body: some View {
    // No header: each row already names what it sets, and a header would
    // repeat it.
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
      // option list). The style is iOS-only; the module also compiles
      // for the macOS host, which falls back to the default picker.
      #if os(iOS)
        .pickerStyle(.navigationLink)
      #endif
      .accessibilityIdentifier("mobileSettings.language")
      .onChange(of: selection) { _, newValue in
        newValue.apply()
        changed = true
      }
      MobileSettingsClockFormatRow()
      MobileSettingsTimeZoneRow(store: store)
    } footer: {
      // The time zone caption always; the reopen note above it after a
      // language change.
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        if changed {
          Text(
            String(
              localized: "settings.language.reopen_note",
              defaultValue: "Reopen Lorvex to apply the new language.", table: "Localizable",
              bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileSettings.language.reopenNote")
        }
        Text(MobileSettingsTimeZoneRow.Copy.caption)
      }
    }
  }
}
