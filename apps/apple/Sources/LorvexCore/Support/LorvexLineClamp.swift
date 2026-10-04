import SwiftUI

extension View {
  /// Limits a text view to `lines` lines while `isClamped`, and reports through
  /// `hidesText` whether that limit cuts any of the text.
  ///
  /// A paragraph that folds behind a "Show more" control needs to know whether
  /// the control has anything to reveal. A character count cannot say: how many
  /// lines a text takes depends on the width its layout gives it (a Mac column,
  /// an iPad pane, a phone) and on the text size. This modifier measures
  /// instead. It lays out two hidden copies of the view at the width the view
  /// receives, one limited to `lines` and one unlimited, and sets `hidesText`
  /// while the unlimited copy is taller. The answer does not depend on
  /// `isClamped`, so a control that shows only while `hidesText` is set stays
  /// reachable after the text is opened. Until the first measurement `hidesText`
  /// is false.
  ///
  /// The view takes its full height at the width it is offered
  /// (`fixedSize(horizontal: false, vertical: true)`), so a limit never leaves a
  /// line half drawn. Apply the modifier to the text itself, after its font and
  /// color and without a `lineLimit` of its own: the copies carry the same
  /// styling, and a limit set earlier in the chain would override theirs.
  public func lorvexLineClamp(_ lines: Int, isClamped: Bool, hidesText: Binding<Bool>) -> some View {
    modifier(LorvexLineClamp(lines: lines, isClamped: isClamped, hidesText: hidesText))
  }
}

private struct LorvexLineClamp: ViewModifier {
  let lines: Int
  let isClamped: Bool
  @Binding var hidesText: Bool
  @State private var clampedHeight: CGFloat = 0
  @State private var fullHeight: CGFloat = 0

  /// Points by which the unlimited copy must exceed the limited one: far less
  /// than a line, so rounding in the text layout is not read as a hidden line.
  private static let heightTolerance: CGFloat = 0.5

  func body(content: Content) -> some View {
    content
      .lineLimit(isClamped ? lines : nil)
      .fixedSize(horizontal: false, vertical: true)
      .background(alignment: .topLeading) {
        ZStack(alignment: .topLeading) {
          content
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clampedHeight = $0 }
          content
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
      }
      .onChange(of: fullHeight > clampedHeight + Self.heightTolerance, initial: true) { _, hides in
        hidesText = hides
      }
  }
}
