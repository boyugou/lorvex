import LorvexCore
import SwiftUI

/// Mobile multi-line plain-text editor for human-authored notes.
public struct MobilePlainTextEditor: View {
  @Binding private var text: String
  private let placeholder: String
  private let minHeight: CGFloat

  public init(
    text: Binding<String>,
    placeholder: String = "",
    minHeight: CGFloat = 80
  ) {
    self._text = text
    self.placeholder = placeholder
    self.minHeight = minHeight
  }

  public var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text)
        .font(LorvexDesign.Typography.primaryText)
        .frame(minHeight: minHeight)
        .scrollContentBackground(.hidden)
      if text.isEmpty && !placeholder.isEmpty {
        Text(placeholder)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(.tertiary)
          .padding(.top, 8)
          .padding(.leading, 5)
          .allowsHitTesting(false)
      }
    }
  }
}
