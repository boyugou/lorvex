import LorvexCore
import SwiftUI

extension TaskDetailView {
  var schedulingContent: some View {
    TaskDetailSchedulingPanel(store: store)
  }

  var recurrenceContent: some View {
    TaskDetailRecurrencePanel(store: store)
  }
}

private struct TaskDetailRecurrencePanel: View {
  @Bindable var store: AppStore

  var body: some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.recurrence.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        if let recurrence = store.selectedTask?.recurrence {
          HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
            Label(
              String(localized: "task_detail.recurrence.currently", defaultValue: "Currently", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "calendar.badge.clock"
            )
            .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
            .foregroundStyle(.secondary)

            Text(
              recurrence.localizedDisplaySummary(exceptions: store.selectedTask?.recurrenceExceptions ?? [])
            )
            .font(LorvexDesign.Typography.secondaryText)
            .lineLimit(3)
          }
          .padding(LorvexDesign.Spacing.s)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        }

        Toggle(
          String(localized: "task_detail.recurrence.enable", defaultValue: "Enable repeating task", table: "Localizable", bundle: LorvexL10n.bundle),
          isOn: $store.taskDetailHasRecurrence
        )
          .toggleStyle(.checkbox)
          .font(LorvexDesign.Typography.primaryText)

        if store.taskDetailHasRecurrence {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            LorvexSegmentedControl(
              options: TaskRecurrenceRule.Anchor.allCases,
              selection: $store.taskDetailRecurrenceAnchor,
              title: { $0.localizedDisplayName },
              accessibilityIdentifier: "task.detail.recurrence.anchor",
              accessibilityLabel: String(
                localized: "task_detail.recurrence.mode", defaultValue: "Repeats",
                table: "Localizable",
                bundle: LorvexL10n.bundle)
            )

            Text(store.taskDetailRecurrenceAnchor.localizedHint)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            recurrenceField(
              title: String(localized: "task_detail.recurrence.frequency", defaultValue: "Frequency", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "calendar"
            ) {
              LorvexSegmentedControl(
                options: TaskRecurrenceRule.Frequency.allCases,
                selection: $store.taskDetailRecurrenceFrequency,
                title: { $0.localizedDisplayName },
                accessibilityIdentifier: "task.detail.recurrence.frequency",
                accessibilityLabel: String(
                  localized: "task_detail.recurrence.frequency", defaultValue: "Frequency",
                  table: "Localizable",
                  bundle: LorvexL10n.bundle)
              )
            }

            recurrenceField(
              title: String(localized: "task_detail.recurrence.interval", defaultValue: "Interval", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "number"
            ) {
              HStack(spacing: LorvexDesign.Spacing.s) {
                TextField(
                  String(localized: "task_detail.recurrence.interval", defaultValue: "Interval", table: "Localizable", bundle: LorvexL10n.bundle),
                  text: $store.taskDetailRecurrenceIntervalText
                )
                .font(LorvexDesign.Typography.primaryText)
                // Signal an unparseable interval (e.g. "0", "x"): Save is disabled
                // by taskDetailRecurrenceCanSave, so tint the text red to explain why.
                .foregroundStyle(store.taskDetailRecurrenceIntervalIsValid ? Color.primary : Color.red)
                .frame(width: 72)
                .textFieldStyle(.plain)
                .accessibilityValue(
                  store.taskDetailRecurrenceIntervalIsValid
                    ? ""
                    : String(
                      localized: "task_detail.metadata.estimate_invalid.a11y",
                      defaultValue: "Invalid — enter a whole number of minutes",
                      table: "Localizable",
                      bundle: LorvexL10n.bundle))

                Text(store.taskDetailRecurrenceFrequency.localizedIntervalUnitPlural)
                  .font(LorvexDesign.Typography.secondaryText)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }

            // Weekday selection only applies to a fixed weekly cadence; hide it
            // for daily/monthly/yearly and for the completion anchor (which
            // repeats relative to the completion date, not specific weekdays).
            if store.taskDetailRecurrenceAnchor == .schedule
              && store.taskDetailRecurrenceFrequency == .weekly {
              // Same localized weekday pills as the habit cadence editor.
              HabitWeekdayPicker(
                selection: recurrenceWeekdays,
                idPrefix: "task-detail-recurrence",
                allowsEmpty: true)
            }
          }
        }

        // With repeat OFF and no recurrence on the task there is nothing to
        // save or remove, so the action hides entirely rather than presenting a
        // permanently-disabled "Remove Recurrence" control with nothing to act
        // on. Repeat ON saves; repeat OFF over an existing recurrence removes it.
        if store.taskDetailHasRecurrence || store.selectedTask?.recurrence != nil {
          Button {
            Task { await store.saveSelectedTaskRecurrence() }
          } label: {
            Label(
              store.taskDetailHasRecurrence
                ? String(localized: "task_detail.recurrence.save", defaultValue: "Save Recurrence", table: "Localizable", bundle: LorvexL10n.bundle)
                : String(localized: "task_detail.recurrence.remove", defaultValue: "Remove Recurrence", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: store.taskDetailHasRecurrence ? "repeat" : "xmark.circle"
            )
          }
          .buttonStyle(store.taskDetailHasRecurrence ? .lorvex(.primary) : .lorvex(.neutral))
          .disabled(!store.taskDetailRecurrenceCanSave)
          .accessibilityIdentifier("task.detail.recurrence.save")
        }
      }
      .disabled(store.isSavingTaskRecurrence)
    }
  }

  private func recurrenceField<Content: View>(
    title: String,
    systemImage: String,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    TaskDetailInlineField(title: title, systemImage: systemImage) {
      content()
    }
  }

  /// Bridges the recurrence's RRULE BYDAY codes ("MO"…"SU") to the shared
  /// ``HabitWeekdayPicker``'s `Set<Int>` (0 = Mon … 6 = Sun) via `weekdayCodes`,
  /// so task recurrence and habit cadence use the same localized weekday control.
  private var recurrenceWeekdays: Binding<Set<Int>> {
    Binding(
      get: {
        Set(store.taskDetailRecurrenceByDay.compactMap { TaskDetailView.weekdayCodes.firstIndex(of: $0) })
      },
      set: { indices in
        store.taskDetailRecurrenceByDay = Set(indices.compactMap { index in
          TaskDetailView.weekdayCodes.indices.contains(index) ? TaskDetailView.weekdayCodes[index] : nil
        })
      }
    )
  }
}

private struct TaskDetailSchedulingPanel: View {
  @Bindable var store: AppStore

  var body: some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.scheduling.panel") {
      // Stacked full-width rows: a two-column layout starved the date field, so
      // its chip wrapped its date text into an oval blob in the narrow detail
      // pane. Full width keeps each control on one clean line.
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        schedulingField(
          title: String(localized: "task_detail.metadata.estimate", defaultValue: "Estimate", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "timer"
        ) {
          HStack(spacing: LorvexDesign.Spacing.xs) {
            // Placeholder is a numeral, not the word "minutes" — the trailing
            // unit already says "min", so a worded placeholder read as "min min".
            // The value is right-aligned in a compact bordered box so it sits
            // tight against the trailing "min" unit instead of stranding dead
            // space across a wide left-aligned field.
            TextField(
              "0",
              text: $store.taskDetailEstimatedMinutesText
            )
            .font(LorvexDesign.Typography.primaryText)
            // Signal an unparseable estimate (e.g. "30m"): Save is disabled and the
            // value is ignored on save, so tint the text red to explain why.
            .foregroundStyle(store.taskDetailEstimateIsValid ? Color.primary : Color.red)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .textFieldStyle(.plain)
            .padding(.horizontal, LorvexDesign.Spacing.s)
            .padding(.vertical, 5)
            .background(
              .quaternary.opacity(store.taskDetailEstimateIsValid ? 0.10 : 0.06),
              in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
            )
            .overlay {
              RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
                .stroke(
                  store.taskDetailEstimateIsValid
                    ? AnyShapeStyle(.separator.opacity(0.30))
                    : AnyShapeStyle(.red.opacity(0.40)),
                  lineWidth: 0.5
                )
            }
            .accessibilityValue(
              store.taskDetailEstimateIsValid
                ? ""
                : String(
                  localized: "task_detail.metadata.estimate_invalid.a11y",
                  defaultValue: "Invalid — enter a whole number of minutes",
                  table: "Localizable",
                  bundle: LorvexL10n.bundle))

            Text(LocalizedStringResource("task_detail.metadata.minutes_unit", defaultValue: "min", table: "Localizable", bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .fixedSize()
          }
        }

        // Planned (the day you'll work on it) and Due (the deadline) sit together
        // with distinct icons and one-line hints, so the two are never confused.
        schedulingField(
          title: String(localized: "task_detail.metadata.planned", defaultValue: "Planned", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar"
        ) {
          VStack(alignment: .leading, spacing: 2) {
            LorvexDateChip(
              date: store.taskDetailHasPlannedDate
                ? store.taskDetailPlannedDatePickerDate : nil,
              placeholder: String(
                localized: "task_detail.metadata.set_date", defaultValue: "Set Date",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              onClear: { store.setTaskDetailHasPlannedDate(false) },
              onSet: { selected in
                store.setTaskDetailHasPlannedDate(true)
                store.taskDetailPlannedDatePickerDate = selected
              }
            )
            Text(LocalizedStringResource(
              "task_detail.metadata.planned_hint",
              defaultValue: "The day you plan to work on it.",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.tertiary)
          }
        }

        schedulingField(
          title: String(localized: "task_detail.metadata.due", defaultValue: "Due", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "flag"
        ) {
          VStack(alignment: .leading, spacing: 2) {
            LorvexDateChip(
              date: store.taskDetailHasDueDate
                ? store.taskDetailDueDatePickerDate : nil,
              placeholder: String(
                localized: "task_detail.metadata.set_date", defaultValue: "Set Date",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              onClear: { store.setTaskDetailHasDueDate(false) },
              onSet: { selected in
                store.setTaskDetailHasDueDate(true)
                store.taskDetailDueDatePickerDate = selected
              }
            )
            Text(LocalizedStringResource(
              "task_detail.metadata.due_hint",
              defaultValue: "The deadline to finish by.",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.tertiary)
          }
        }

        // Available from (defer-until): the day the task returns to your lists.
        // Until then it stays hidden everywhere except the Scheduled section and
        // search — a quiet way to park not-yet-actionable work without losing it.
        schedulingField(
          title: String(
            localized: "task_detail.metadata.available_from", defaultValue: "Available from",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "eye.slash"
        ) {
          VStack(alignment: .leading, spacing: 2) {
            LorvexDateChip(
              date: store.taskDetailHasAvailableFrom
                ? store.taskDetailAvailableFromPickerDate : nil,
              placeholder: String(
                localized: "task_detail.metadata.set_date", defaultValue: "Set Date",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              onClear: { store.setTaskDetailHasAvailableFrom(false) },
              onSet: { selected in
                store.setTaskDetailHasAvailableFrom(true)
                store.taskDetailAvailableFromPickerDate = selected
              }
            )
            .accessibilityIdentifier("task.detail.availableFrom")
            Text(LocalizedStringResource(
              "task_detail.metadata.available_from_hint",
              defaultValue: "Hidden from your lists until this day.",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
  }

  private func schedulingField<Content: View>(
    title: String,
    systemImage: String,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    TaskDetailInlineField(title: title, systemImage: systemImage) {
      content()
    }
  }
}

private extension TaskDetailView {
  static let weekdayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
}
