import LorvexCore
import SwiftUI

extension TaskDetailView {
  var recurrenceContent: some View {
    TaskDetailRecurrencePanel(store: store)
  }
}

/// The Repeat menu's Custom editor: the frequency, how many periods apart
/// ("Every 2 weeks"), the weekdays of a weekly schedule, and whether the next
/// one follows the schedule or the completion. Opening it turns repeating on;
/// the rule saves when the popover closes, so there is no Save button, and
/// Never in the menu stops it.
private struct TaskDetailRecurrencePanel: View {
  @Bindable var store: AppStore

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Picker(selection: $store.taskDetailRecurrenceFrequency) {
        ForEach(TaskRecurrenceRule.Frequency.allCases, id: \.self) { frequency in
          Text(frequency.localizedDisplayName).tag(frequency)
        }
      } label: {
        Text(String(localized: "task_detail.recurrence.frequency", defaultValue: "Frequency", table: "Localizable", bundle: LorvexL10n.bundle))
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("task.detail.recurrence.frequency")

      // The interval is one localized phrase in the frequency's unit, so the
      // number and its unit agree in every language ("Every week", "Every 2
      // weeks", "每 2 周").
      Stepper(value: interval, in: 1...TaskRecurrenceEditorDraft.maximumInterval) {
        Text(store.taskDetailRecurrenceFrequency.localizedEveryInterval(interval.wrappedValue))
          .font(LorvexDesign.Typography.primaryText)
          .monospacedDigit()
      }
      .accessibilityIdentifier("task.detail.recurrence.interval")

      // Weekdays only shape a fixed weekly schedule; a completion-anchored
      // repeat counts from the day the task was finished.
      if store.taskDetailRecurrenceAnchor == .schedule && store.taskDetailRecurrenceFrequency == .weekly {
        HabitWeekdayPicker(
          selection: recurrenceWeekdays,
          idPrefix: "task-detail-recurrence",
          allowsEmpty: true)
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Picker(selection: $store.taskDetailRecurrenceAnchor) {
          ForEach(TaskRecurrenceRule.Anchor.allCases, id: \.self) { anchor in
            Text(anchor.localizedDisplayName).tag(anchor)
          }
        } label: {
          Text(String(localized: "task_detail.recurrence.mode", defaultValue: "Repeats", table: "Localizable", bundle: LorvexL10n.bundle))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("task.detail.recurrence.anchor")

        Text(store.taskDetailRecurrenceAnchor.localizedHint)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(width: 300, alignment: .leading)
    .disabled(store.isSavingTaskRecurrence)
    .accessibilityIdentifier("task.detail.recurrence.panel")
    .onAppear { store.taskDetailHasRecurrence = true }
    .onDisappear {
      guard store.taskDetailRecurrenceCanSave else { return }
      Task { await store.saveSelectedTaskRecurrence() }
    }
  }

  /// The interval as a number for the stepper, stored as the draft's text so
  /// the draft keeps owning validation; unparsable text reads as 1.
  private var interval: Binding<Int> {
    Binding(
      get: { LorvexNumberInput.integer(from: store.taskDetailRecurrenceIntervalText) ?? 1 },
      set: { store.taskDetailRecurrenceIntervalText = String($0) })
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

private extension TaskDetailView {
  static let weekdayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
}
