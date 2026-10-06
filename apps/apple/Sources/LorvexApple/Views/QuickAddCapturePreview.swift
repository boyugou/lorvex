import LorvexCore
import SwiftUI

extension AppStore {
  /// The preview `QuickAddRow` shows under its field while the user types.
  /// Empty when the line carries no details, so a plain title shows nothing.
  func quickAddPreview(_ text: String) -> LorvexCapturePreview {
    LorvexCapturePreview(parse: captureParse(text), logicalDay: logicalTodayDateString)
  }
}

/// The line under the quick-add field: "Adds “Call the caterer”" followed by the
/// recognized details as tinted words, so the user sees what Return will create
/// before pressing it. `showsTitle` is false where the title is already on
/// screen, as in a command-palette row, leaving the words alone.
struct QuickAddPreviewLine: View {
  let preview: LorvexCapturePreview
  var showsTitle = true

  var body: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xxs, fillsWidth: true) {
      if showsTitle {
        Text(preview.addsLine)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      ForEach(preview.words) { word in
        Text(word.label)
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .foregroundStyle(word.tint)
          .fixedSize()
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(
            RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
              .fill(word.tint.opacity(0.1)))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("workspace.quickAdd.preview")
  }
}
