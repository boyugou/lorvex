import LorvexCore
import SwiftUI

/// The picker behind a day field (Planned, Due, Hide until): the named days
/// that field usually wants as one-click rows (`presets`), a month calendar
/// for any other day, and a way to clear the field. Dates are local midnight,
/// the frame the detail draft stores before it re-anchors them for the
/// service layer.
///
/// The Planned field also carries the task's optional time on the chosen day
/// (``TimeField``), set under the calendar once a day is chosen.
struct TaskDetailDayPicker: View {
  /// A task's optional time on the chosen day, in minutes since midnight.
  struct TimeField {
    var value: Range<Int>?
    /// How long a new time runs: the task's estimate when it has one.
    var defaultLength: Int?
    /// The clock in the product day, which places a new time on today at the
    /// next half hour.
    var nowMinutes: Int?
    var isToday: Bool
    var onChange: (Range<Int>?) -> Void

    /// The time "Add Time" proposes (``LorvexTaskFieldChoices/newTime(length:nowMinutes:isToday:)``).
    var newTime: Range<Int> {
      LorvexTaskFieldChoices.newTime(length: defaultLength, nowMinutes: nowMinutes, isToday: isToday)
    }
  }

  let title: String
  let hint: String
  let presets: [LorvexTaskFieldChoices.DayPreset]
  let selection: Date?
  let onSet: (Date) -> Void
  let onClear: () -> Void
  var time: TimeField? = nil

  private var calendar: Calendar { .autoupdatingCurrent }

  /// The presets that apply today, each once: a preset landing on the same
  /// day as an earlier one (next Monday seen from a Sunday) is dropped.
  private var presetDays: [(preset: LorvexTaskFieldChoices.DayPreset, date: Date)] {
    var seen = Set<Date>()
    return presets.compactMap { preset in
      guard let date = LorvexTaskFieldChoices.date(for: preset, calendar: calendar),
        seen.insert(date).inserted
      else { return nil }
      return (preset, date)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      InspectorEditorHeader(title: title, hint: hint)
      VStack(spacing: 0) {
        ForEach(presetDays, id: \.date) { day in
          TaskDetailChoiceRow(
            title: Self.label(for: day.preset),
            detail: day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
            isOn: selection.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
          ) { onSet(day.date) }
        }
      }
      .padding(.horizontal, -LorvexDesign.Spacing.s)
      Divider()
      TaskDetailMonthCalendar(selection: selection) { onSet(calendar.startOfDay(for: $0)) }
      if selection != nil, let time {
        Divider()
        timeRow(time)
      }
      if selection != nil {
        Button(
          String(
            localized: "task_detail.picker.no_date", defaultValue: "No Date", table: "Localizable",
            bundle: LorvexL10n.bundle),
          role: .destructive, action: onClear
        )
        .buttonStyle(.borderless)
      }
    }
    .frame(width: 264)
  }

  private static func label(for preset: LorvexTaskFieldChoices.DayPreset) -> String {
    switch preset {
    case .today:
      String(
        localized: "task_detail.picker.today", defaultValue: "Today", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .tomorrow:
      String(
        localized: "task_detail.picker.tomorrow", defaultValue: "Tomorrow", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .thisWeekend:
      String(
        localized: "task_detail.picker.this_weekend", defaultValue: "This Weekend", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .nextMonday:
      String(
        localized: "task_detail.picker.next_monday", defaultValue: "Next Monday", table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .nextMonth:
      String(
        localized: "task_detail.picker.next_month", defaultValue: "Next Month", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }

  /// The time on the chosen day: its start and end, with a way to remove it,
  /// or one button that adds a time. Moving the start keeps the length, the
  /// way a calendar event moves; an end at or before the start is pushed to
  /// fifteen minutes after it.
  @ViewBuilder
  private func timeRow(_ field: TimeField) -> some View {
    if let value = field.value {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "clock")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        clockField(
          minutes: value.lowerBound,
          label: String(
            localized: "task_detail.picker.start_time", defaultValue: "Start Time",
            table: "Localizable", bundle: LorvexL10n.bundle)
        ) { start in
          field.onChange(LorvexTaskFieldChoices.time(value, movingStartTo: start))
        }
        Text(verbatim: "–").foregroundStyle(.secondary)
        clockField(
          minutes: value.upperBound,
          label: String(
            localized: "task_detail.picker.end_time", defaultValue: "End Time",
            table: "Localizable", bundle: LorvexL10n.bundle)
        ) { end in
          field.onChange(LorvexTaskFieldChoices.time(value, settingEndTo: end))
        }
        Spacer(minLength: 0)
        Button {
          field.onChange(nil)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(removeTimeTitle)
        .accessibilityLabel(removeTimeTitle)
        .accessibilityIdentifier("task.detail.time.remove")
      }
    } else {
      Button {
        field.onChange(field.newTime)
      } label: {
        Label(
          String(
            localized: "task_detail.picker.add_time", defaultValue: "Add Time", table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "clock")
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("task.detail.time.add")
    }
  }

  private var removeTimeTitle: String {
    String(
      localized: "task_detail.picker.remove_time", defaultValue: "Remove Time", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// An hour-and-minute field for `minutes` since midnight on the chosen day.
  private func clockField(
    minutes: Int, label: String, onSet: @escaping (Int) -> Void
  ) -> some View {
    let day = calendar.startOfDay(for: selection ?? .now)
    return DatePicker(
      label,
      selection: Binding(
        get: {
          calendar.date(
            bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: day) ?? day
        },
        set: { date in
          let parts = calendar.dateComponents([.hour, .minute], from: date)
          onSet((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }),
      displayedComponents: .hourAndMinute
    )
    .datePickerStyle(.field)
    .labelsHidden()
    .fixedSize()
    // Popover content does not inherit the scene root's clock locale.
    .lorvexClockLocale()
    .accessibilityLabel(label)
  }
}

/// The picker behind the length field: a ring that fills toward two hours
/// with the minutes in its center ("Not set" while there is no estimate),
/// steppers of fifteen minutes, and the common lengths as one-click choices
/// that wrap onto a second line when the language's labels run long.
struct TaskDetailLengthPicker: View {
  @Binding var minutesText: String
  @Environment(\.colorScheme) private var colorScheme

  private typealias Choices = LorvexTaskFieldChoices

  private var minutes: Int { Choices.minutes(fromText: minutesText) }

  private func set(_ value: Int) { minutesText = Choices.text(forMinutes: value) }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      InspectorEditorHeader(
        title: String(
          localized: "task_detail.picker.length", defaultValue: "How Long", table: "Localizable",
          bundle: LorvexL10n.bundle),
        hint: nil)
      HStack(spacing: LorvexDesign.Spacing.l) {
        stepButton(systemImage: "minus", delta: -Choices.lengthStep)
        ZStack {
          Circle()
            .stroke(
              LorvexDesign.Palette.accent.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)),
              lineWidth: 6)
          LorvexProgressArc(
            fraction: Choices.lengthFraction(minutes), style: LorvexDesign.Palette.accent, lineWidth: 6)
          if minutes > 0 {
            VStack(spacing: 0) {
              Text(minutes, format: .number)
                .font(LorvexDesign.Typography.screenTitle.monospacedDigit())
              Text(
                LocalizedStringResource(
                  "task_detail.metadata.minutes_unit", defaultValue: "min", table: "Localizable",
                  bundle: LorvexL10n.bundle)
              )
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
            }
          } else {
            Text(
              LocalizedStringResource(
                "task_detail.picker.length_unset", defaultValue: "Not set", table: "Localizable",
                bundle: LorvexL10n.bundle)
            )
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
          }
        }
        .frame(width: 96, height: 96)
        .reduceMotionAnimation(.snappy(duration: 0.2), value: minutes)
        stepButton(systemImage: "plus", delta: Choices.lengthStep)
      }
      .frame(maxWidth: .infinity)
      LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
        ForEach(Choices.lengthPresets, id: \.self) { preset in
          InspectorEditorPill(label: LorvexDurationFormat.minutes(preset), isOn: minutes == preset) {
            set(preset)
          }
        }
      }
      if minutes > 0 {
        Button(
          String(
            localized: "task_detail.picker.no_length", defaultValue: "No Estimate", table: "Localizable",
            bundle: LorvexL10n.bundle),
          role: .destructive
        ) { set(0) }
        .buttonStyle(.borderless)
      }
    }
    .frame(width: 280)
  }

  private func stepButton(systemImage: String, delta: Int) -> some View {
    Button {
      set(Choices.length(minutes, steppedBy: delta))
    } label: {
      Image(systemName: systemImage)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .disabled(delta < 0 ? minutes <= 0 : minutes >= Choices.lengthMax)
    .accessibilityLabel(Choices.lengthStepAccessibilityLabel(delta: delta))
  }
}
