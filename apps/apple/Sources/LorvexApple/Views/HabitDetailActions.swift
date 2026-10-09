import LorvexCore
import SwiftUI

/// The row under the habit inspector's header, laid out like the task
/// inspector's action row: where the habit stands in its current period at
/// the leading edge, and the overflow menu at the trailing edge.
///
/// A habit checked in once per period states its standing in words ("Done
/// today", "1 of 3 this week", "Not done yet today"); the header's ring is the
/// control that changes it. A habit counted several times a day shows the
/// day's count between a remove-one and an add-one button instead, since the
/// ring only adds.
///
/// The overflow menu holds the rest: the check-in commands the ring and the
/// buttons also offer (so the keyboard and VoiceOver reach them), Reset Today,
/// Icon and Color…, Archive Habit, and Delete Habit…, which asks first. A
/// reset that would clear more than one check-in asks first too. The menu wears
/// the task inspector's quiet chip (``InspectorActionChip``), as tall as the
/// row's other control.
struct HabitDetailActions: View {
  let store: AppStore
  let habit: LorvexHabit
  let progress: HabitPeriodProgress.Value
  @Binding var isChoosingAppearance: Bool

  @State private var isConfirmingDelete = false
  @State private var isConfirmingReset = false

  private var isMultiCount: Bool { habit.targetCount > 1 }
  private var ringAction: HabitRingAction { HabitRingAction.action(habit: habit, progress: progress) }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if isMultiCount {
        dayCountStepper
      } else {
        standing
      }
      Spacer(minLength: 0)
      overflowMenu
    }
    // The overflow chip fills the row's height, which is the tallest control's.
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("habit.detail.actions")
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
        habit.name),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(String(localized: "habits.row.delete_confirm.delete", defaultValue: "Delete Habit", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive) {
        Task { await store.deleteHabit(habit) }
      }
      Button(String(localized: "common.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: {
      Text(LocalizedStringResource("habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .confirmationDialog(
      String(localized: "habits.row.reset_confirm.title", defaultValue: "Reset today’s progress?", table: "Localizable", bundle: LorvexL10n.bundle),
      isPresented: $isConfirmingReset,
      titleVisibility: .visible
    ) {
      Button(String(localized: "habits.row.reset_today", defaultValue: "Reset today", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive) {
        Task { await store.uncompleteHabit(habit) }
      }
      Button(String(localized: "common.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: {
      Text(LocalizedStringResource("habits.row.reset_confirm.message", defaultValue: "This clears today’s check-ins for this habit.", table: "Localizable", bundle: LorvexL10n.bundle))
    }
  }

  // MARK: - Standing

  /// The period's standing in words, green with a check once the period's
  /// plan is met.
  private var standing: some View {
    Label {
      Text(standingText)
        .fixedSize()
    } icon: {
      Image(systemName: progress.isComplete ? "checkmark.circle.fill" : "circle.dashed")
    }
    .font(LorvexDesign.Typography.secondaryText.weight(.medium))
    .foregroundStyle(
      progress.isComplete ? AnyShapeStyle(LorvexDesign.Palette.done) : AnyShapeStyle(.secondary))
    .accessibilityIdentifier("habit.detail.standing")
  }

  private var standingText: String {
    let period = HabitPeriodProgress.period(for: habit)
    if progress.isComplete { return HabitDisplayText.periodDoneLabel(period) }
    if progress.required > 1 {
      return HabitDisplayText.periodCountLabel(
        completed: progress.completed, required: progress.required, period: period)
    }
    return HabitDisplayText.periodNotYetLabel(period)
  }

  /// The day's count between a remove-one and an add-one button, on the same
  /// faint surface as the task inspector's action chips.
  private var dayCountStepper: some View {
    HStack(spacing: 0) {
      stepButton(
        systemImage: "minus",
        label: String(localized: "habits.row.decrement", defaultValue: "Remove one", table: "Localizable", bundle: LorvexL10n.bundle),
        identifier: "habit.detail.decrement",
        isDisabled: habit.completionsToday <= 0
      ) { Task { await store.adjustHabitCompletion(habit, delta: -1) } }
      Text(
        HabitDisplayText.periodCountLabel(
          completed: habit.completionsToday, required: habit.targetCount, period: .day)
      )
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium).monospacedDigit())
      .foregroundStyle(progress.isComplete ? AnyShapeStyle(LorvexDesign.Palette.done) : AnyShapeStyle(.primary))
      .fixedSize()
      .padding(.horizontal, LorvexDesign.Spacing.xxs)
      .accessibilityIdentifier("habit.detail.dayCount")
      stepButton(
        systemImage: "plus",
        label: String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle),
        identifier: "habit.detail.increment",
        isDisabled: progress.isComplete
      ) { Task { await store.adjustHabitCompletion(habit, delta: 1) } }
    }
    .background {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous).fill(.quaternary.opacity(0.5))
    }
  }

  private func stepButton(
    systemImage: String, label: String, identifier: String, isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .frame(width: 26, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }

  // MARK: - Overflow menu

  private var overflowMenu: some View {
    Menu {
      checkInItems
      Divider()
      Button {
        // The menu finishes closing before the popover opens on the ring.
        Task { @MainActor in isChoosingAppearance = true }
      } label: {
        Label(
          String(localized: "habit_detail.menu.appearance", defaultValue: "Icon and Color…", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "paintpalette")
      }
      .accessibilityIdentifier("habit.detail.appearance")
      Divider()
      Button {
        Task { await store.setHabitArchived(habit, archived: true) }
      } label: {
        Label(
          String(localized: "habit_detail.menu.archive", defaultValue: "Archive Habit", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "archivebox")
      }
      .accessibilityIdentifier("habit.detail.archive")
      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(
          String(localized: "habit_detail.menu.delete", defaultValue: "Delete Habit…", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "trash")
      }
      .accessibilityIdentifier("habit.detail.delete")
    } label: {
      InspectorActionChip(systemImage: "ellipsis", title: nil)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: true, vertical: false)
    .help(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("habit.detail.more")
  }

  /// The check-in commands: Complete Today or Reset Today for a habit checked
  /// in once a day, Add One, Remove One, and Reset Today for one counted
  /// several times a day.
  @ViewBuilder
  private var checkInItems: some View {
    if isMultiCount {
      Button {
        Task { await store.adjustHabitCompletion(habit, delta: 1) }
      } label: {
        Label(
          String(localized: "habit_detail.menu.add_one", defaultValue: "Add One", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus")
      }
      .disabled(progress.isComplete)
      Button {
        Task { await store.adjustHabitCompletion(habit, delta: -1) }
      } label: {
        Label(
          String(localized: "habit_detail.menu.remove_one", defaultValue: "Remove One", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "minus")
      }
      .disabled(habit.completionsToday <= 0)
      Button {
        if habit.completionsToday > 1 {
          isConfirmingReset = true
        } else {
          Task { await store.uncompleteHabit(habit) }
        }
      } label: {
        Label(
          String(localized: "habits.row.reset_today.title_case", defaultValue: "Reset Today", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.counterclockwise")
      }
      .disabled(habit.completionsToday <= 0)
    } else if ringAction == .undoToday {
      Button {
        Task { await store.uncompleteHabit(habit) }
      } label: {
        Label(
          String(localized: "habits.row.reset_today.title_case", defaultValue: "Reset Today", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.counterclockwise")
      }
    } else {
      Button {
        Task { await store.completeHabit(habit) }
      } label: {
        Label(
          String(localized: "habits.row.complete_today.title_case", defaultValue: "Complete Today", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "checkmark.circle")
      }
      .disabled(ringAction == .none)
    }
  }
}
