import LorvexCore
import SwiftUI

/// Appearance picker (System/Light/Dark) for the mobile Settings screen. Writes
/// the same `@AppStorage` key the root view reads to drive `preferredColorScheme`,
/// so a change takes effect immediately across the app.
struct MobileSettingsAppearanceSection: View {
  @AppStorage(AppAppearance.preferenceKey) private var appearanceRaw = AppAppearance.system.rawValue

  private var appearance: Binding<AppAppearance> {
    Binding(
      get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
      set: { appearanceRaw = $0.rawValue }
    )
  }

  var body: some View {
    Section {
      Picker(
        String(
          localized: "settings.appearance", defaultValue: "Appearance", table: "Localizable",
          bundle: MobileL10n.bundle), selection: appearance
      ) {
        ForEach(AppAppearance.allCases) { option in
          Label(option.mobileSettingsLabel, systemImage: option.symbolName).tag(option)
        }
      }
      .pickerStyle(.segmented)
    } header: {
      Text(
        String(
          localized: "settings.section.appearance", defaultValue: "Appearance",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "settings.appearance.footer",
          defaultValue:
            "System follows your device Light/Dark setting; Light and Dark force that appearance everywhere in Lorvex.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }
}

extension AppAppearance {
  fileprivate var mobileSettingsLabel: String {
    switch self {
    case .system:
      String(
        localized: "settings.appearance.system", defaultValue: "System", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .light:
      String(
        localized: "settings.appearance.light", defaultValue: "Light", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .dark:
      String(
        localized: "settings.appearance.dark", defaultValue: "Dark", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}
