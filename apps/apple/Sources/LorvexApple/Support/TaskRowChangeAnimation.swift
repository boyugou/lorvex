import LorvexCore
import SwiftUI

/// When a change to a task list's rows animates. A change of a few rows
/// animates, so a completed, deferred, or moved task settles out of its place
/// instead of vanishing. A change of many rows, such as a batch over a long
/// selection, applies at once: animating hundreds of rows in a scrolled lazy
/// stack churns the screen and can leave SwiftUI re-measuring the stack
/// without end.
enum TaskRowChangeAnimation {
  /// The most rows a change may add or remove and still animate. A task that
  /// moves from one section to another counts once for each.
  static let rowLimit = 20

  /// The animation a change of a few rows uses.
  static let animation = Animation.snappy(duration: 0.18)

  /// Whether going from `old` to `new`, two lists of sections in the same
  /// order, adds or removes few enough rows to animate. A row that only moves
  /// within its section counts as no change.
  static func animates(from old: [[LorvexTask]], to new: [[LorvexTask]]) -> Bool {
    var changedRows = 0
    for (before, after) in zip(old, new) {
      changedRows += Set(before.map(\.id)).symmetricDifference(after.map(\.id)).count
      if changedRows > rowLimit { return false }
    }
    return true
  }

  /// Whether a batch over `taskCount` tasks animates its rows. Each task
  /// leaves one place and lands in another, so it counts twice.
  static func animates(batchOf taskCount: Int) -> Bool {
    taskCount * 2 <= rowLimit
  }
}
