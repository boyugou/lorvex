import LorvexCore
import SwiftUI

/// What a row for a task that another task waits on says under its title:
/// that the task has been started, and when it is due, in the overdue tint
/// once that day has passed, the way a task row shows both. A completed or
/// cancelled task shows neither, since its circle already says it is done.
/// `init(task:timeZone:)` returns nil when neither fact applies, so such a row
/// stays a single title line. The task's priority and plain status are left to
/// its status circle, whose glyph and tint carry them. The due day is counted
/// from today in the product time zone the hosting row passes.
struct MobileDependencyFacts: View {
  let isStarted: Bool
  let due: String?
  let isOverdue: Bool

  init?(task: LorvexTask, timeZone: TimeZone) {
    isStarted = task.status == .inProgress
    due = task.status.isResolved ? nil : task.cachedDueRelativeLabel(timeZone: timeZone)
    isOverdue = due != nil && task.isOverdue(timeZone: timeZone)
    guard isStarted || due != nil else { return nil }
  }

  var body: some View {
    HStack(spacing: 5) {
      if isStarted {
        HStack(spacing: 3) {
          Image(systemName: "play.fill").imageScale(.small)
          Text(
            String(
              localized: "task.row.started", defaultValue: "Started", table: "Localizable",
              bundle: MobileL10n.bundle))
        }
        .foregroundStyle(.tint)
      }
      if let due {
        if isStarted { Text(verbatim: "·").foregroundStyle(.tertiary) }
        HStack(spacing: 3) {
          Image(systemName: isOverdue ? "clock.badge.exclamationmark" : "calendar")
          Text(due).monospacedDigit()
        }
        .foregroundStyle(isOverdue ? AnyShapeStyle(LorvexDesign.Palette.overdue) : AnyShapeStyle(.secondary))
      }
    }
    .font(.footnote)
    .lineLimit(1)
    .accessibilityHidden(true)
  }
}
