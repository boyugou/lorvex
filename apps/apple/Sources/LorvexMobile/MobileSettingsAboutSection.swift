import LorvexCore
import SwiftUI

/// "About" section for the iPhone/iPad/visionOS Settings screen: the app
/// version plus links to the bundled open-source acknowledgments and the
/// privacy policy summary.
struct MobileSettingsAboutSection: View {
  var body: some View {
    Section(
      String(
        localized: "settings.section.about", defaultValue: "About", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      LabeledContent(
        String(
          localized: "settings.runtime.version", defaultValue: "Version", table: "Localizable",
          bundle: MobileL10n.bundle), value: MobileAppMetadata.displayVersion
      )
      .accessibilityIdentifier("mobileSettings.about.version")
      NavigationLink {
        MobileAcknowledgmentsView()
      } label: {
        Label(
          String(
            localized: "settings.acknowledgments.open", defaultValue: "Acknowledgments",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "doc.text")
      }
      .accessibilityIdentifier("mobileSettings.about.acknowledgments")
      NavigationLink {
        MobilePrivacyPolicyView()
      } label: {
        Label(
          String(
            localized: "settings.privacy.open", defaultValue: "Privacy Policy",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "hand.raised")
      }
      .accessibilityIdentifier("mobileSettings.about.privacyPolicy")
    }
  }
}
