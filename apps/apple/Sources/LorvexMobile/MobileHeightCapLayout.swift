import SwiftUI

/// Offers its one subview at most `maxHeight` of height and takes the height
/// the subview reports. A view that adapts to the room it is offered, such as
/// a `ViewThatFits` that falls back to a scroll view, then hugs its content up
/// to the limit and fills the limit beyond it.
///
/// `.frame(maxHeight:)` cannot express this: a flexible frame offered more
/// room than its limit takes the whole limit and centers a shorter child in
/// it, so the content's own height never shows.
struct MobileHeightCapLayout: Layout {
  /// The most height the subview is offered, and so the most it takes.
  var maxHeight: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    return content.sizeThatFits(capped(proposal))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let content = subviews.first else { return }
    content.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  /// The proposal with its height limited. An unspecified height, a request
  /// for the ideal size, is limited too, so the ideal size stays within the cap.
  private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
    ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
  }
}
