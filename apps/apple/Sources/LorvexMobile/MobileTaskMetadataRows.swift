import LorvexCore
import SwiftUI

struct MobileChecklistItemRow: View {
  let item: TaskChecklistItem
  let toggleChecklistItem: ((TaskChecklistItem) async -> Void)?
  let removeChecklistItem: ((TaskChecklistItem) async -> Void)?

  var body: some View {
    Group {
      if let toggleChecklistItem {
        Button {
          Task { await toggleChecklistItem(item) }
        } label: {
          rowLabel
        }
      } else {
        rowLabel
      }
    }
    // The icon (circle vs. filled check) carries completion state visually but
    // is decorative to VoiceOver, and strikethrough has no accessibility
    // semantics — so expose the state as an explicit value, matching the task
    // completion circle and habit ring. A success haptic confirms a completing
    // toggle (only when transitioning to done, like the circle).
    .accessibilityValue(
      item.completedAt == nil
        ? String(
          localized: "checklist.item.incomplete.a11y", defaultValue: "Not Completed",
          table: "Localizable", bundle: MobileL10n.bundle)
        : String(
          localized: "task.row.completed.a11y", defaultValue: "Completed", table: "Localizable",
          bundle: MobileL10n.bundle))
    .lorvexSensoryFeedback(.success, trigger: item.completedAt != nil) { _, isDone in isDone }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if let removeChecklistItem {
        Button(role: .destructive) {
          Task { await removeChecklistItem(item) }
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
      }
    }
  }

  private var rowLabel: some View {
    Label {
      Text(userContent: item.text)
        .font(LorvexDesign.Typography.primaryText)
        .strikethrough(item.completedAt != nil)
        .foregroundStyle(item.completedAt == nil ? Color.primary : Color.secondary)
    } icon: {
      Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(item.completedAt == nil ? Color.secondary : LorvexDesign.Palette.done)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }
}

/// One of the task's reminders in the task detail, named the way the task's
/// rows name a day ("Tomorrow, 9:30 AM", "Thursday, 8:00 AM"); swiping it
/// away removes it.
struct MobileReminderRow: View {
  let reminder: TaskReminder
  /// The product's logical today, `yyyy-MM-dd`, which the reminder's day is
  /// named relative to.
  let logicalDay: String
  let timeZone: TimeZone
  let removeReminder: ((TaskReminder) async -> Void)?

  var body: some View {
    Label {
      Text(Self.title(reminder, logicalDay: logicalDay, timeZone: timeZone))
        .font(LorvexDesign.Typography.primaryText)
    } icon: {
      Image(systemName: "bell")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(LorvexDesign.Palette.warning)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if let removeReminder {
        Button(role: .destructive) {
          Task { await removeReminder(reminder) }
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
      }
    }
  }

  /// The reminder's day and time in `timeZone`
  /// (``TaskReminder/dayAndTime(logicalDay:timeZone:)``), joined as the When
  /// row joins a day and a time ("Tomorrow, 9:30 AM"), or its full date and
  /// time when the stored time is unreadable.
  static func title(_ reminder: TaskReminder, logicalDay: String, timeZone: TimeZone) -> String {
    guard let when = reminder.dayAndTime(logicalDay: logicalDay, timeZone: timeZone) else {
      return reminder.displaySummary(timeZone: timeZone)
    }
    return String(
      localized: "task_detail.do_on.day_time", defaultValue: "\(when.day), \(when.time)",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}
