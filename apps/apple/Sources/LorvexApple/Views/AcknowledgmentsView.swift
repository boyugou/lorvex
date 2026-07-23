import LorvexCore
import SwiftUI

/// Scrollable, read-only third-party notices surface presented as a sheet
/// from Settings ▸ Diagnostics ▸ About. Renders the bundled
/// `ThirdPartyAcknowledgments.text` verbatim (license/copyright text is
/// legal content, never localized); content and drift are owned by
/// `script/generate_acknowledgments.py` / `script/verify_acknowledgments.py`.
struct AcknowledgmentsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(ThirdPartyAcknowledgments.text)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(LorvexDesign.Spacing.l)
      }
      .navigationTitle(String(localized: "acknowledgments.title", defaultValue: "Acknowledgments", table: "Localizable", bundle: LorvexL10n.bundle))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "common.done", defaultValue: "Done", table: "Localizable", bundle: LorvexL10n.bundle)) {
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 620)
    .accessibilityIdentifier("settings.acknowledgments.sheet")
  }
}
