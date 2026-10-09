import SwiftUI

/// One row of a review's look ahead (``LorvexReviewTomorrow`` and
/// ``LorvexReviewWeekAhead``): a mark, the item's title and its time.
///
/// The mark is an event's bar in the calendar's color or a task's dot. It sits
/// on the title's first line in a column as wide as the completion circle of
/// the review's task lists (the same symbol in the same font), so it stands on
/// the circles' axis and every title in a review starts at one edge. The
/// column, the mark and its place on the line follow the text size, as the
/// circle does.
///
/// The time follows the title and keeps its whole width while the title wraps.
/// From `.xxLarge` up (``SwiftUI/DynamicTypeSize/stacksTimeColumn``) it sits
/// under the title, where a phone-width row cannot hold both side by side.
struct LorvexReviewAheadRow: View {
  enum Mark {
    /// A bar in the calendar's color.
    case event(Color)
    /// A small ring.
    case task
  }

  let mark: Mark
  let title: String
  /// The item's time as words, or `nil` for an item without one.
  let time: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// 1 at the default text size; the mark grows with the title's text style.
  @ScaledMetric(relativeTo: .body) private var markScale: CGFloat = 1

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      markColumn
      if dynamicTypeSize.stacksTimeColumn {
        VStack(alignment: .leading, spacing: 0) {
          titleText
          timeText(stacked: true)
        }
        Spacer(minLength: 0)
      } else {
        titleText
        Spacer(minLength: LorvexDesign.Spacing.s)
        timeText(stacked: false)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
  }

  private var titleText: some View {
    Text(userContent: title)
      .font(LorvexDesign.Typography.primaryText)
      .foregroundStyle(.primary)
      .multilineTextAlignment(.leading)
      .lineLimitUnlessAccessibilitySize(2)
  }

  @ViewBuilder
  private func timeText(stacked: Bool) -> some View {
    if let time {
      Text(time)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(stacked ? nil : 1)
        .fixedSize(horizontal: !stacked, vertical: true)
    }
  }

  /// The completion circle's symbol, hidden and given no height. Its width
  /// makes the column, its center is where the circle's center would be on the
  /// title's first line, and the row keeps the title's height.
  private var markColumn: some View {
    Image(systemName: "circle")
      .font(LorvexDesign.Typography.primaryText)
      .hidden()
      .frame(height: 0)
      .overlay { markShape }
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var markShape: some View {
    switch mark {
    case .event(let color):
      Capsule()
        .fill(color)
        .frame(width: 3 * markScale, height: 14 * markScale)
    case .task:
      Circle()
        .strokeBorder(.secondary, lineWidth: 1.5 * markScale)
        .frame(width: 7 * markScale, height: 7 * markScale)
    }
  }
}
