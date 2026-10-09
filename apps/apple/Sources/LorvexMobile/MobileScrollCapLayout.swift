import SwiftUI

/// Sizes its one subview, a vertical scroll view, to the height of its content
/// up to `maxHeight`. A short content shows whole with nothing to scroll; a
/// taller one fills the limit and scrolls within it.
///
/// A scroll view offered room takes all of it, so left alone it would stand at
/// the limit however little it holds. The layout asks for the content's own
/// height instead, by offering the scroll view no height, and caps that. The
/// subview is then placed in the height the layout takes.
struct MobileScrollCapLayout: Layout {
  /// The most height the layout takes, and the most the subview is offered.
  var maxHeight: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
    let limit = min(proposal.height ?? maxHeight, maxHeight)
    return CGSize(width: ideal.width, height: min(ideal.height, limit))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let content = subviews.first else { return }
    content.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }
}
