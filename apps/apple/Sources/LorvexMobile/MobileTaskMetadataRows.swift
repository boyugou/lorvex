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
        .mobileDestructiveSwipeStyle()
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
        .foregroundStyle(item.completedAt == nil ? Color.secondary : LorvexDesign.Palette.done)
    }
    .labelStyle(MobileDetailGlyphLabelStyle())
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }
}

/// The label of a task-detail row that leads with a glyph, such as a checklist
/// item or a reminder. The glyph is set in the title's face and sits on the
/// title's first baseline, which centers it on the first line's capitals. It
/// stands in the column a task row gives its circle, so the title starts where
/// task rows and Waits On rows start theirs. A title that wraps therefore
/// hangs under its own first line instead of the glyph centering against all
/// of it. VoiceOver reads the title alone; the glyph is decoration.
private struct MobileDetailGlyphLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.m) {
      configuration.icon
        .font(LorvexDesign.Typography.primaryText)
        .mobileTaskCircleFrame(isSquare: false)
        .accessibilityHidden(true)
      configuration.title
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
        .foregroundStyle(LorvexDesign.Palette.warning)
    }
    .labelStyle(MobileDetailGlyphLabelStyle())
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
        .mobileDestructiveSwipeStyle()
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
