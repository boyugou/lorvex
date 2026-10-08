import LorvexCore
import SwiftUI

/// A task in the menu bar panel, on Today and on Next 7 Days: the circle that
/// completes it, the title that opens it in the main window, and its time on
/// the day it is listed under, when it has one.
///
/// The circle is the circle symbol every task row in the main window and the
/// widgets draws, in the same priority tint, so urgent work reads red or
/// orange here too. Drawn in the title's font, it sits on the title's first
/// line, and its column is as wide as a habit ring, so task and habit titles
/// start at one edge. A title too long for the line beside its time wraps to a
/// second line rather than losing its end.
struct MenuBarTaskRow: View {
  let task: LorvexTask
  /// The task's time on the day the row is listed under, in minutes from
  /// midnight.
  let time: Range<Int>?
  /// Names the row's two controls for UI tests: `<identifier>.complete` for
  /// the circle and `<identifier>.open` for the title.
  let identifier: String
  let complete: () -> Void
  let open: () -> Void

  /// The height of a one-line row, shared with the panel's habit and event
  /// rows.
  static let minHeight: CGFloat = 30

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Button(action: complete) {
        LorvexTaskStatusCircle(task: task)
          .font(LorvexDesign.Typography.primaryText.weight(.semibold))
          .imageScale(.large)
          .frame(width: 18)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(TodayCalmCopy.complete)
      .accessibilityLabel(MenuBarCopy.complete(task.title))
      .accessibilityIdentifier("\(identifier).complete")

      Button(action: open) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Text(userContent: task.title)
            .font(LorvexDesign.Typography.primaryText)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if let time {
            Text(TodayCalmCopy.timeRange(start: time.lowerBound, end: time.upperBound))
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
              .fixedSize()
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.sm)
        .frame(minHeight: Self.minHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(TodayCalmCopy.openDetails)
      .accessibilityIdentifier("\(identifier).open")
    }
  }
}
