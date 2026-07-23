import LorvexCore
import SwiftUI

/// Scrollable, read-only third-party notices screen pushed from Settings ▸
/// About. Renders the bundled `ThirdPartyAcknowledgments.text` verbatim
/// (license/copyright text is legal content, never localized); content and
/// drift are owned by `script/generate_acknowledgments.py` /
/// `script/verify_acknowledgments.py`.
public struct MobileAcknowledgmentsView: View {
  public init() {}

  public var body: some View {
    ScrollView {
      Text(ThirdPartyAcknowledgments.text)
        .font(.system(.footnote, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LorvexDesign.Spacing.m)
    }
    .navigationTitle(
      String(
        localized: "acknowledgments.title", defaultValue: "Acknowledgments", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .accessibilityIdentifier("mobileAcknowledgments.screen")
  }
}
