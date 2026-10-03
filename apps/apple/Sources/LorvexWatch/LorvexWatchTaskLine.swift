import Foundation
import LorvexCore
import SwiftUI

/// The one line under a task on the wrist, and how it reads.
struct LorvexWatchTaskLine: Equatable {
  enum Tone: Equatable {
    case plain
    /// The task's saved time contains the clock.
    case running
    case started
    case overdue

    var color: Color {
      switch self {
      case .plain: .secondary
      case .running, .started: LorvexDesign.Palette.accent
      case .overdue: LorvexDesign.Palette.overdue
      }
    }
  }

  let text: String
  let tone: Tone

  /// Today's row rules, the same the widgets follow: "Until" and the end while
  /// the task's saved time runs, else the time's start; else "Overdue" for a
  /// due date before `logicalDay`; else "Blocked" when the task waits on an
  /// unfinished task (`isBlocked`); else "Started"; else the estimate. Nil
  /// when none applies. A time that has passed keeps reading as its start:
  /// the task stays on Today and nothing asks about it.
  static func make(
    task: LorvexTask, time: Range<Int>?, nowMinutes: Int, logicalDay: String?,
    isBlocked: Bool = false
  ) -> LorvexWatchTaskLine? {
    if let time {
      return time.contains(nowMinutes)
        ? LorvexWatchTaskLine(text: LorvexWatchCalmCopy.until(time.upperBound), tone: .running)
        : LorvexWatchTaskLine(text: lorvexClockTimeLabel(minutes: time.lowerBound), tone: .plain)
    }
    if let due = task.dueDate, let logicalDay,
      LorvexDateFormatters.ymdUTC.string(from: due) < logicalDay
    {
      return LorvexWatchTaskLine(text: LorvexWatchCalmCopy.overdue, tone: .overdue)
    }
    if isBlocked {
      return LorvexWatchTaskLine(text: LorvexWatchCalmCopy.blocked, tone: .plain)
    }
    if task.status == .inProgress {
      return LorvexWatchTaskLine(text: LorvexWatchCalmCopy.started, tone: .started)
    }
    if let minutes = task.estimatedMinutes, minutes > 0 {
      return LorvexWatchTaskLine(text: LorvexDurationFormat.minutes(minutes), tone: .plain)
    }
    return nil
  }
}
