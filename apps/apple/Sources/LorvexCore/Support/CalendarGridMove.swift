import CoreGraphics
import Foundation

/// The geometry a day-column calendar grid shares when a block is dragged to a
/// new time or day and when a task is dropped onto a column. Pure functions of
/// points and minutes, so a grid's gesture code stays a thin reader of them.
///
/// Minutes are minutes since midnight in the column's day, 0 to 1440. A column
/// is `24 * hourHeight` points tall with midnight at its top.
public enum CalendarGridMove {
  /// A move or a drop lands on a multiple of this many minutes from the point
  /// it is measured against.
  public static let snapMinutes = 15

  /// Where a dragged block lands.
  public struct Landing: Equatable, Sendable {
    /// The block's new start, in minutes.
    public var startMinute: Int
    /// Columns the block moved by: negative to the left, positive to the right.
    public var dayShift: Int
    /// True when the drag moved the block by less than one snap step and to no
    /// other column, so nothing changes and nothing should be written.
    public var isUnchanged: Bool
  }

  /// Where a block that starts at `startMinute` and lasts `duration` minutes
  /// lands after being dragged by `translation` points from the column
  /// `dayIndex` of `dayCount` columns that are each `columnWidth` points wide.
  ///
  /// The vertical travel becomes minutes, rounded to the nearest minute and
  /// then cut toward zero to a multiple of `snap`, so the block keeps its own
  /// offset from the quarter hour; the result is kept inside the day. The
  /// horizontal travel is the nearest whole number of columns, kept inside the
  /// visible columns.
  public static func landing(
    startMinute: Int, duration: Int, translation: CGSize, hourHeight: CGFloat,
    columnWidth: CGFloat, dayIndex: Int, dayCount: Int, snap: Int = snapMinutes
  ) -> Landing {
    let travelled = Int((translation.height / hourHeight * 60).rounded())
    let delta = (travelled / snap) * snap
    let latestStart = max(0, 24 * 60 - duration)
    let start = max(0, min(latestStart, startMinute + delta))
    let columnShift = columnWidth > 0 ? Int((translation.width / columnWidth).rounded()) : 0
    let target = max(0, min(dayCount - 1, dayIndex + columnShift))
    let dayShift = target - dayIndex
    return Landing(startMinute: start, dayShift: dayShift, isUnchanged: delta == 0 && dayShift == 0)
  }

  /// The minute `y` points below the top of a day column stands for, kept
  /// inside the day (a point past the bottom reads as 23:59).
  public static func minute(atY y: CGFloat, hourHeight: CGFloat) -> Int {
    let clamped = max(0, min(24 * hourHeight - 1, y))
    return Int(clamped / hourHeight * 60)
  }

  /// The start of a block of `duration` minutes dropped with the pointer `y`
  /// points below the top of a day column: the minute under the pointer, cut
  /// down to a multiple of `snap`, and early enough that the block ends by
  /// midnight.
  public static func dropStart(
    atY y: CGFloat, hourHeight: CGFloat, duration: Int, snap: Int = snapMinutes
  ) -> Int {
    let snapped = (minute(atY: y, hourHeight: hourHeight) / snap) * snap
    return max(0, min(snapped, 24 * 60 - duration))
  }
}

extension LorvexTask {
  /// The time this task takes when it starts at `startMinute`: its own length
  /// when it already has a time, else its estimate (half an hour when it has
  /// none), kept inside the day.
  public func time(startingAt startMinute: Int) -> Range<Int> {
    let current =
      plannedTime
      ?? LorvexTaskFieldChoices.newTime(length: estimatedMinutes, nowMinutes: nil, isToday: false)
    return LorvexTaskFieldChoices.time(current, movingStartTo: startMinute)
  }
}
