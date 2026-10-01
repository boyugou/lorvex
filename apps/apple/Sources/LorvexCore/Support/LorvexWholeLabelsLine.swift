import SwiftUI

/// Up to four short labels on one line, separated by dots ("45 min · work ·
/// home"), that drop from the end when the line runs out of room instead of
/// cutting a label to "w…".
///
/// The caller orders the labels by importance, so the least important fall
/// away first; labels past the fourth are not shown, and with too little room
/// for the first the line is empty. Only the labels shown are drawn, so
/// nothing hidden sits in the row to throw off a list's separator alignment.
/// The font comes from the environment; labels read `.secondary` and dots
/// `.tertiary`.
///
/// Every candidate line is built up front from plain text, with no `ForEach`:
/// SwiftUI builds a `ViewThatFits` candidate it has not needed before during
/// layout, which an animation frame may run off the main thread, and a
/// main-actor `ForEach` closure run there traps.
public struct LorvexWholeLabelsLine: View {
  public let labels: [String]
  /// Starts the line with a dot, for a line that continues other metadata.
  public let leadingSeparator: Bool
  public let spacing: CGFloat

  public init(_ labels: [String], leadingSeparator: Bool, spacing: CGFloat) {
    self.labels = Array(labels.prefix(4))
    self.leadingSeparator = leadingSeparator
    self.spacing = spacing
  }

  public var body: some View {
    // Longest first; the first that fits whole wins, the empty line last.
    ViewThatFits(in: .horizontal) {
      if labels.count >= 4 { line(4) }
      if labels.count >= 3 { line(3) }
      if labels.count >= 2 { line(2) }
      if labels.count >= 1 { line(1) }
      Color.clear.frame(width: 0, height: 0)
    }
  }

  private func line(_ count: Int) -> some View {
    HStack(spacing: spacing) {
      if count > 0 { label(0) }
      if count > 1 { label(1) }
      if count > 2 { label(2) }
      if count > 3 { label(3) }
    }
    .lineLimit(1)
  }

  @ViewBuilder
  private func label(_ index: Int) -> some View {
    if index > 0 || leadingSeparator {
      Text(verbatim: "·").foregroundStyle(.tertiary)
    }
    Text(verbatim: labels[index]).foregroundStyle(.secondary)
  }
}
