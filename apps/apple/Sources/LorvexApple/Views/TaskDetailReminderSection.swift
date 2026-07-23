import LorvexCore
import SwiftUI

extension TaskDetailView {
  func remindersContent(task: LorvexTask) -> some View {
    TaskDetailRemindersPanel(
      reminderDate: $store.taskDetailReminderDate,
      reminders: task.reminders,
      timeZone: store.logicalTimeZone,
      addReminder: { Task { await store.addReminderToSelectedTask() } },
      removeReminder: { reminder in Task { await store.removeReminder(reminder) } }
    )
  }
}

private struct TaskDetailRemindersPanel: View {
  @Binding var reminderDate: Date
  let reminders: [TaskReminder]
  let timeZone: TimeZone
  let addReminder: () -> Void
  let removeReminder: (TaskReminder) -> Void

  var body: some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.reminders.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        // Existing reminders (or the empty hint) read first; the add controls
        // follow. The reverse order showed a date picker above "No reminders",
        // which read as a reminder that contradicted the line below it.
        if reminders.isEmpty {
          LorvexEmptyStatePanel(
            title: String(localized: "task_detail.reminders.empty", defaultValue: "No reminders", table: "Localizable", bundle: LorvexL10n.bundle),
            message: String(
              localized: "task_detail.reminders.empty.message",
              defaultValue: "Add a reminder to get a notification before this task is due.",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "bell.slash",
            tint: .secondary,
            style: .inline
          )
        } else {
          VStack(spacing: LorvexDesign.Spacing.xs) {
            ForEach(reminders) { reminder in
              TaskDetailReminderRow(
                reminder: reminder,
                timeZone: timeZone,
                remove: { removeReminder(reminder) }
              )
            }
          }
        }

        // The date+time chip and the Add button stack on separate rows: in the
        // narrow inspector an inline HStack starved the chip and truncated the
        // date ("2026年6月2…"). A full-width chip row keeps the time fully
        // readable; the Add button trails on its own row below it.
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          LorvexDateChip(
            date: reminderDate,
            placeholder: String(
              localized: "task_detail.reminders.date", defaultValue: "Reminder",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            includesTime: true,
            minDate: Date(),
            onSet: { reminderDate = $0 }
          )
          .environment(\.timeZone, timeZone)
          .frame(maxWidth: .infinity, alignment: .leading)

          HStack {
            Spacer(minLength: 0)
            Button(action: addReminder) {
              Label(
                String(localized: "task_detail.reminders.add_short", defaultValue: "Add", table: "Localizable", bundle: LorvexL10n.bundle),
                systemImage: "bell.badge"
              )
            }
            .buttonStyle(.lorvexSecondary)
            // A reminder in the past would never fire; the picker already blocks
            // past times, this stops adding the default before it's adjusted.
            .disabled(reminderDate <= Date())
            .help(String(localized: "task_detail.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityLabel(String(localized: "task_detail.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityIdentifier("task.detail.reminders.add")
          }
        }
      }
    }
  }
}

private struct TaskDetailReminderRow: View {
  let reminder: TaskReminder
  let timeZone: TimeZone
  let remove: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Label(formattedReminderAt, systemImage: "bell")
        .font(LorvexDesign.Typography.primaryText)
      Spacer()
      Button(role: .destructive, action: remove) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "task_detail.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "task_detail.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("task.detail.reminders.remove")
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
  }

  private var formattedReminderAt: String {
    reminder.displaySummary(timeZone: timeZone)
  }
}
