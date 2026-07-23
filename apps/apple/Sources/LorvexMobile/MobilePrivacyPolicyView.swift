import LorvexCore
import SwiftUI

/// Scrollable, read-only privacy summary screen pushed from Settings ▸ About,
/// next to Acknowledgments. Renders the bundled `PrivacyPolicySummary.text`
/// verbatim (a hand-maintained, non-localized reference document, like the
/// acknowledgments notices) with a link to the full policy at its public
/// lorvex.app URL.
public struct MobilePrivacyPolicyView: View {
  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        fullPolicyLink
        Text(PrivacyPolicySummary.text)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(LorvexDesign.Spacing.m)
    }
    .navigationTitle(
      String(
        localized: "privacy.title", defaultValue: "Privacy Policy", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .accessibilityIdentifier("mobilePrivacyPolicy.screen")
  }

  @ViewBuilder
  private var fullPolicyLink: some View {
    if let fullPolicyURL {
      Link(destination: fullPolicyURL) {
        Label(
          String(
            localized: "privacy.view_full_policy", defaultValue: "View Full Privacy Policy",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "arrow.up.forward.square"
        )
      }
      .accessibilityIdentifier("mobilePrivacyPolicy.viewFullPolicy")
    }
  }

  private var fullPolicyURL: URL? {
    URL(string: PrivacyPolicySummary.fullPolicyURL)
  }
}
