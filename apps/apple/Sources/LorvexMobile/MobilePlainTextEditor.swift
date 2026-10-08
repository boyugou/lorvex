import LorvexCore
import SwiftUI

/// Mobile multi-line plain-text editor for human-authored notes. Its text
/// starts on the row's own leading edge, in line with a neighboring
/// `TextField`'s, and the placeholder stands where the first typed character
/// will.
///
/// VoiceOver reaches the editor alone, named by `accessibilityLabel` (the
/// placeholder when none is given); the placeholder is a picture of that name
/// and is not a second element.
public struct MobilePlainTextEditor: View {
  @Binding private var text: String
  private let placeholder: String
  private let accessibilityLabel: String?
  private let minHeight: CGFloat

  /// How far the editor's text container sits in from the view's edge on each
  /// side (UIKit's default line-fragment padding). The editor reaches this far
  /// past the row so the text itself lands on the row's content edges.
  private static let textInset: CGFloat = 5
  /// The text container's inset from the view's top edge.
  private static let textTopInset: CGFloat = 8

  public init(
    text: Binding<String>,
    placeholder: String = "",
    accessibilityLabel: String? = nil,
    minHeight: CGFloat = 80
  ) {
    self._text = text
    self.placeholder = placeholder
    self.accessibilityLabel = accessibilityLabel
    self.minHeight = minHeight
  }

  public var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text)
        .font(LorvexDesign.Typography.primaryText)
        .frame(minHeight: minHeight)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, -Self.textInset)
        .accessibilityLabel(accessibilityLabel ?? placeholder)
      if text.isEmpty && !placeholder.isEmpty {
        Text(placeholder)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(LorvexDesign.Palette.placeholderText)
          .padding(.top, Self.textTopInset)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
  }
}
