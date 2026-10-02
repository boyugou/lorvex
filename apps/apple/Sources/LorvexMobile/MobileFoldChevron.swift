import LorvexCore
import SwiftUI

/// A fold header's disclosure mark at the header's trailing edge, the way an
/// iOS sidebar section folds: it points along the reading direction while the
/// section is folded and down while it is open (``LorvexDisclosureChevron``).
/// The chevron beside a title ("Habits ›") is the one that opens another page.
/// Decorative; the header button carries the meaning.
///
/// It takes the header's own color. A List section header already draws in
/// the secondary style, and a hierarchical `.tertiary` inside it compounds to
/// about 1.3:1, too faint to show that the section folds.
struct MobileFoldChevron: View {
  let isExpanded: Bool

  var body: some View {
    LorvexDisclosureChevron(isExpanded: isExpanded)
      .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
  }
}
