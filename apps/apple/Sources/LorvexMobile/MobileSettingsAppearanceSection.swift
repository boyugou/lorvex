import LorvexCore
import SwiftUI

/// Appearance picker (System/Light/Dark) for the mobile Settings screen. Writes
/// the same `@AppStorage` key the root view reads to drive `preferredColorScheme`,
/// so a change takes effect immediately across the app. It is a segmented
/// control, or one row per choice at accessibility text sizes, where a
/// segmented control's labels stop growing with the text.
struct MobileSettingsAppearanceSection: View {
  @AppStorage(AppAppearance.preferenceKey) private var appearanceRaw = AppAppearance.system.rawValue
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var appearance: Binding<AppAppearance> {
    Binding(
      get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
      set: { appearanceRaw = $0.rawValue }
    )
  }

  var body: some View {
    Section {
      if dynamicTypeSize.isAccessibilitySize {
        picker
          .pickerStyle(.inline)
          .labelsHidden()
      } else {
        picker
          .pickerStyle(.segmented)
      }
    } header: {
      Text(
        String(
          localized: "settings.section.appearance", defaultValue: "Appearance",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var picker: some View {
    Picker(
      String(
        localized: "settings.appearance", defaultValue: "Appearance", table: "Localizable",
        bundle: MobileL10n.bundle), selection: appearance
    ) {
      ForEach(AppAppearance.allCases) { option in
        Label(option.mobileSettingsLabel, systemImage: option.symbolName).tag(option)
      }
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
