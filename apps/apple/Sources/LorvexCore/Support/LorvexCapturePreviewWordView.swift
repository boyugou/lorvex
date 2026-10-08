import SwiftUI

/// One recognized detail of a capture preview, drawn as a tinted word: its
/// label over a rounded wash of its tint. The Mac's quick-add surfaces and the
/// iPhone's capture sheet draw every word through it, each with its own
/// padding.
///
/// Placed in a ``LorvexFlowLayout``, a word wider than the line (a long list
/// name in the menu bar panel or on a phone) is offered the line's width and
/// shortens with an ellipsis instead of running past the edge. At the
/// accessibility text sizes it wraps instead, so none of it is lost.
public struct LorvexCapturePreviewWordView: View {
  public let word: LorvexCapturePreview.Word
  /// The space between the label and the left and right edges of its wash.
  public let horizontalPadding: CGFloat
  /// The space between the label and the top and bottom edges of its wash.
  public let verticalPadding: CGFloat
  /// How strongly the word's tint shows in its wash, from 0 to 1.
  public let washOpacity: Double

  public init(
    word: LorvexCapturePreview.Word, horizontalPadding: CGFloat, verticalPadding: CGFloat,
    washOpacity: Double
  ) {
    self.word = word
    self.horizontalPadding = horizontalPadding
    self.verticalPadding = verticalPadding
    self.washOpacity = washOpacity
  }

  public var body: some View {
    Text(word.label)
      .font(LorvexDesign.Typography.secondaryText.weight(.medium))
      .foregroundStyle(word.tint)
      .lineLimitUnlessAccessibilitySize(1)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(word.tint.opacity(washOpacity)))
  }
}
