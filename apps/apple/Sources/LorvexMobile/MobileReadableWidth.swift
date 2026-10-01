import SwiftUI

extension EnvironmentValues {
  /// The readable-width margin the enclosing ``mobileReadableWidth`` screen
  /// computed, or nil where the system's own margins stand: at compact width,
  /// and inside a list+detail split's panes.
  @Entry var mobileReadableMargin: CGFloat? = nil
}

extension View {
  /// Caps every list inside to a readable column at regular width (iPad),
  /// centering it with equal side margins; compact width is left untouched.
  /// The margin is a content margin, so a list keeps its full-width scroll
  /// area and indicators while its rows stay a comfortable line length. A
  /// content margin set above a `ScrollView` does not reach it, so a screen
  /// rooted in one applies the same margin itself with
  /// ``mobileReadableScrollMargins()``.
  ///
  /// A tab's root screen passes `inlineTitleAtRegularWidth` so its large title
  /// does not sit at the window's edge beside the centered column; the
  /// floating tab bar already names the tab. Pushed screens leave it off, since
  /// switching the title mode rebuilds the screen when the window resizes.
  func mobileReadableWidth(_ maxWidth: CGFloat = 760, inlineTitleAtRegularWidth: Bool = false) -> some View {
    modifier(MobileReadableWidth(maxWidth: maxWidth, inlineTitle: inlineTitleAtRegularWidth))
  }

  /// Insets this scroll view's content by the enclosing screen's readable
  /// margin (``mobileReadableWidth``). For a screen whose root is a
  /// `ScrollView` rather than a list: the content margin the enclosing screen
  /// sets reaches a list through any number of intermediate views but not a
  /// `ScrollView`, which only honors one applied to itself.
  func mobileReadableScrollMargins() -> some View {
    modifier(MobileReadableScrollMargins())
  }
}

private struct MobileReadableScrollMargins: ViewModifier {
  @Environment(\.mobileReadableMargin) private var margin

  func body(content: Content) -> some View {
    content.contentMargins(.horizontal, margin, for: .scrollContent)
  }
}

private struct MobileReadableWidth: ViewModifier {
  let maxWidth: CGFloat
  let inlineTitle: Bool
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var isRegular: Bool { horizontalSizeClass == .regular }

  /// The inset an inset-grouped list keeps on its own. A centering margin
  /// smaller than this would only take inset away, so it is not applied.
  private static let systemInset: CGFloat = 20

  /// `nil` keeps the system's own margins: compact lists keep their inset,
  /// and so does a regular-width view too narrow for centering to add
  /// anything beyond it, such as the detail pane of a list+detail split.
  private func margin(for width: CGFloat) -> CGFloat? {
    guard isRegular else { return nil }
    let centering = (width - maxWidth) / 2
    return centering > Self.systemInset ? centering : nil
  }

  func body(content: Content) -> some View {
    // The width comes from a GeometryReader, which reports what the container
    // proposes and never the content's ideal width. Measuring the content
    // itself fed a scroll view's margin-widened ideal width back into the
    // margin; a navigation transition, which sizes the incoming screen by that
    // ideal, then grew the two against each other every frame and the push
    // never landed.
    let margined = GeometryReader { proxy in
      let margin = margin(for: proxy.size.width)
      content
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .environment(\.mobileReadableMargin, margin)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    #if os(iOS)
      if inlineTitle && isRegular {
        margined.toolbarTitleDisplayMode(.inline)
      } else {
        margined
      }
    #else
      margined
    #endif
  }
}
