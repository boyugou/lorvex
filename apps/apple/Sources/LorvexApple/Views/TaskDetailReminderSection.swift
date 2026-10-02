import LorvexCore
import SwiftUI

extension TaskDetailView {
  func remindersContent(task: LorvexTask) -> some View {
    TaskDetailRemindersPanel(
      reminderDate: $store.taskDetailReminderDate,
      reminders: task.reminders,
      presets: reminderPresets(now: LorvexPreviewClock.now(in: .current)),
      timeZone: store.logicalTimeZone,
      add: { date in
        store.taskDetailReminderDate = date
        Task { await store.addReminderToSelectedTask() }
      },
      removeReminder: { reminder in Task { await store.removeReminder(reminder) } }
    )
  }

  /// The one-click reminder times for the task in the detail draft, from its
  /// planned time and due day (``TaskDetailReminderPreset/presets(plannedDay:plannedTime:dueDay:now:timeZone:pickerTimeZone:)``).
  func reminderPresets(now: Date = Date()) -> [TaskDetailReminderPreset] {
    TaskDetailReminderPreset.presets(
      plannedDay: store.taskDetailHasPlannedDate ? store.taskDetailPlannedDatePickerDate : nil,
      plannedTime: store.taskDetailPlannedTime,
      dueDay: store.taskDetailHasDueDate ? store.taskDetailDueDatePickerDate : nil,
      now: now,
      timeZone: store.logicalTimeZone)
  }
}

/// A one-click reminder time offered in the reminders editor.
struct TaskDetailReminderPreset: Identifiable {
  let id: String
  let title: String
  let date: Date

  /// One-click reminder times, each only while it is still ahead: when the
  /// task's planned time starts, 9 AM on its due day, an hour from now, and
  /// 9 AM tomorrow. Times repeat across presets only once. A preset's name
  /// says the day ("Tomorrow morning") and its detail the time, written in the
  /// chosen clock.
  ///
  /// Clock times are wall-clock times in `timeZone`, the product zone
  /// reminders are composed in, and "tomorrow" is the day after `now` there.
  /// `plannedDay` and `dueDay` are day pickers' values: midnights in
  /// `pickerTimeZone`, this device's zone. Each is read as the day it names in
  /// that zone, and the time is set on the same day in `timeZone`; setting the
  /// hour on the picker's instant directly would land a day early whenever the
  /// product zone is west of the device's.
  static func presets(
    plannedDay: Date?,
    plannedTime: Range<Int>?,
    dueDay: Date?,
    now: Date,
    timeZone: TimeZone,
    pickerTimeZone: TimeZone = .current
  ) -> [TaskDetailReminderPreset] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    func at(_ day: Date, minutes: Int) -> Date? {
      calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }
    func at(pickerDay: Date, minutes: Int) -> Date? {
      let label = PlannedDayBridge.storageDate(forLocalInstant: pickerDay, timeZone: pickerTimeZone)
      return at(PlannedDayBridge.displayDate(forStorageDate: label, timeZone: timeZone), minutes: minutes)
    }
    var presets: [TaskDetailReminderPreset] = []
    func offer(_ id: String, _ title: String, _ date: Date?) {
      guard let date, date > now, !presets.contains(where: { $0.date == date }) else { return }
      presets.append(.init(id: id, title: title, date: date))
    }
    if let plannedDay, let plannedTime {
      offer(
        "start",
        String(localized: "task_detail.reminders.preset.start", defaultValue: "When it starts", table: "Localizable", bundle: LorvexL10n.bundle),
        at(pickerDay: plannedDay, minutes: plannedTime.lowerBound))
    }
    if let dueDay {
      offer(
        "due",
        String(localized: "task_detail.reminders.preset.due_morning", defaultValue: "Due day morning", table: "Localizable", bundle: LorvexL10n.bundle),
        at(pickerDay: dueDay, minutes: 9 * 60))
    }
    offer(
      "hour",
      String(localized: "task_detail.reminders.preset.in_an_hour", defaultValue: "In an hour", table: "Localizable", bundle: LorvexL10n.bundle),
      calendar.date(byAdding: .minute, value: 60, to: now).flatMap { calendar.date(bySetting: .second, value: 0, of: $0) })
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
      offer(
        "tomorrow",
        String(localized: "task_detail.reminders.preset.tomorrow_morning", defaultValue: "Tomorrow morning", table: "Localizable", bundle: LorvexL10n.bundle),
        at(tomorrow, minutes: 9 * 60))
    }
    return presets
  }
}

/// The reminders editor: the task's reminders, each with a remove button, then
/// the one-click times, then a custom date and time with Add. It never shows
/// an empty-state panel; with no reminders it opens straight on the choices.
private struct TaskDetailRemindersPanel: View {
  @Binding var reminderDate: Date
  let reminders: [TaskReminder]
  let presets: [TaskDetailReminderPreset]
  let timeZone: TimeZone
  let add: (Date) -> Void
  let removeReminder: (TaskReminder) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      if !reminders.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(reminders) { reminder in
            HStack(spacing: LorvexDesign.Spacing.s) {
              Image(systemName: "bell.fill")
                .foregroundStyle(LorvexDesign.Palette.accent)
                .frame(width: 18)
              Text(reminder.displaySummary(timeZone: timeZone))
                .frame(maxWidth: .infinity, alignment: .leading)
              LorvexIconButton(
                systemImage: "xmark",
                label: String(localized: "task_detail.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
                accessibilityIdentifier: "task.detail.reminders.remove"
              ) { removeReminder(reminder) }
            }
            .font(LorvexDesign.Typography.primaryText)
          }
        }
        Divider()
      }

      VStack(alignment: .leading, spacing: 0) {
        ForEach(presets) { preset in
          TaskDetailChoiceRow(
            title: preset.title,
            detail: preset.date.formatted(Self.presetFormat(timeZone: timeZone)),
            accessibilityIdentifier: "task.detail.reminders.preset.\(preset.id)"
          ) { add(preset.date) }
        }
      }

      HStack(spacing: LorvexDesign.Spacing.s) {
        DatePicker(
          String(localized: "task_detail.reminders.date", defaultValue: "Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
          selection: $reminderDate,
          in: Date()...,
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.field)
        .environment(\.timeZone, timeZone)
        // Popover content does not inherit the scene root's clock locale.
        .lorvexClockLocale()
        Spacer(minLength: 0)
        Button(String(localized: "task_detail.reminders.add_short", defaultValue: "Add", table: "Localizable", bundle: LorvexL10n.bundle)) {
          add(reminderDate)
        }
        .disabled(reminderDate <= Date())
        .accessibilityLabel(String(localized: "task_detail.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("task.detail.reminders.add")
      }
      .padding(.top, LorvexDesign.Spacing.xs)
    }
    .frame(width: 300, alignment: .leading)
    .accessibilityIdentifier("task.detail.reminders.panel")
  }

  /// A preset's time beside its name: the weekday and the clock ("Thu
  /// 9:00 AM"). Every preset falls within the coming week, so the weekday
  /// says which day without a full date.
  private static func presetFormat(timeZone: TimeZone) -> Date.FormatStyle {
    var style = Date.FormatStyle().weekday(.abbreviated).hour().minute()
    style.timeZone = timeZone
    style.locale = LorvexClockFormat.displayLocale
    return style
  }
}

/// One choice in a field editor's list: a title, an optional trailing detail
/// in the secondary style, and a faint fill under the pointer. Clicking it
/// applies the choice.
struct TaskDetailChoiceRow: View {
  let title: String
  var detail: String? = nil
  /// A glyph before the title, in the secondary style.
  var systemImage: String? = nil
  /// Marks the row as the field's current value: accent title and a checkmark.
  var isOn = false
  /// Fills the row as the pointer does, for a picker that moves a highlight
  /// with the arrow keys.
  var isHighlighted = false
  var accessibilityIdentifier: String? = nil
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        if let systemImage {
          Image(systemName: systemImage)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        Text(title)
          .foregroundStyle(isOn ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary))
        if isOn {
          Image(systemName: "checkmark")
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
            .foregroundStyle(LorvexDesign.Palette.accent)
            .accessibilityHidden(true)
        }
        Spacer(minLength: LorvexDesign.Spacing.s)
        if let detail {
          Text(detail)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .font(LorvexDesign.Typography.primaryText)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(.quaternary.opacity(isHovering || isHighlighted ? 1 : 0)))
      .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityAddTraits(isOn ? .isSelected : [])
    .accessibilityIdentifier(accessibilityIdentifier ?? "")
  }
}
