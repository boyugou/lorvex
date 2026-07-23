import LorvexCore
import SwiftUI

/// Scrollable, read-only privacy summary presented as a sheet from Settings ▸
/// Diagnostics ▸ About, next to Acknowledgments. Renders the bundled
/// `PrivacyPolicySummary.text` verbatim (a hand-maintained, non-localized
/// reference document, like the acknowledgments notices) with a link to the
/// full policy at its public lorvex.app URL.
struct PrivacyPolicyView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
          fullPolicyLink
          Text(PrivacyPolicySummary.text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LorvexDesign.Spacing.l)
      }
      .navigationTitle(String(localized: "privacy.title", defaultValue: "Privacy Policy", table: "Localizable", bundle: LorvexL10n.bundle))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "common.done", defaultValue: "Done", table: "Localizable", bundle: LorvexL10n.bundle)) {
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 620)
    .accessibilityIdentifier("settings.privacy.sheet")
  }

  @ViewBuilder
  private var fullPolicyLink: some View {
    if let fullPolicyURL {
      Link(destination: fullPolicyURL) {
        Label(
          String(localized: "privacy.view_full_policy", defaultValue: "View Full Privacy Policy", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.forward.square"
        )
      }
      .accessibilityIdentifier("settings.privacy.viewFullPolicy")
    }
  }

  private var fullPolicyURL: URL? {
    URL(string: PrivacyPolicySummary.fullPolicyURL)
  }
}
