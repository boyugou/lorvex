import LorvexCore
import SwiftUI

/// The line that says an action on the wrist did not save, on the page where
/// the action was taken (``LorvexWatchStore/actionFailureText``): the failure
/// haptic alone is easy to miss.
struct LorvexWatchActionFailureLine: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(LorvexDesign.Palette.warning)
      .accessibilityIdentifier("watch.actionError")
  }
}
