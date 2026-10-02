import LorvexCore
import SwiftUI

/// Language, clock, and time zone rows for the mobile Settings screen. The language
/// picker sets the app's own language preference (``AppLanguage``), the same
/// one iOS Settings offers on Lorvex's page, which the bundle reads at launch,
/// so a change applies the next time the app is opened (iOS apps can't
/// relaunch themselves) and the footer says so until then. "System Default"
/// removes the preference and follows the iPhone's language. The clock picker
/// (``MobileSettingsClockFormatRow``) and the time zone rows
/// (``MobileSettingsTimeZoneRow``) apply at once.
struct MobileSettingsLanguageSection: View {
  @Bindable var store: MobileStore
  @State private var selection = AppLanguage.current

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
      }
      MobileSettingsClockFormatRow()
      MobileSettingsTimeZoneRow(store: store)
    } footer: {
      // The time zone caption always; the reopen note above it while the
      // chosen language differs from the one the app is showing.
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        if selection.needsRelaunch {
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
