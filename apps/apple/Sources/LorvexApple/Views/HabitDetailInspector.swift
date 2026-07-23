import LorvexCore
import SwiftUI

/// The Habits trailing inspector — the habit counterpart to ``TaskDetailView``.
/// Selecting a habit in the catalog opens it here (instead of the old inline
/// row expansion) so habits share the same detail-panel rhythm as tasks: a
/// title header with the check-in action, today's progress, the frequency/total
/// pills, reminders, and the completion heatmap.
struct HabitDetailInspector: View {
  @Bindable var store: AppStore
  let habitID: LorvexHabit.ID

  @State private var isShowingDeleteConfirmation = false
  @State private var isEditing = false

  private var habit: LorvexHabit? {
    store.filteredHabits.first { $0.id == habitID }
      ?? store.habits?.habits.first { $0.id == habitID }
  }

  var body: some View {
    Group {
      if let habit {
        content(habit: habit)
      } else {
        DetachedWindowPlaceholder(
          systemImage: "repeat.circle",
          title: String(
            localized: "habit_detail.placeholder.title", defaultValue: "Habit Not Found",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
      }
    }
    .task(id: habitID) { await store.loadHabitDetail(id: habitID) }
    .sheet(isPresented: $isEditing) {
      if let habit {
        EditHabitSheet(habit: habit, store: store, isPresented: $isEditing)
      }
    }
  }

  @ViewBuilder
  private func content(habit: LorvexHabit) -> some View {
    let detail = store.habitDetail(for: habit.id)
    let recentCompletions = detail?.stats.recentCompletions ?? []
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
        header(habit: habit, recentCompletions: recentCompletions)

        HabitCatalogRowDetail(habit: habit, recentCompletions: recentCompletions)

        HabitReminderEditor(
          store: store, habit: habit, policies: detail?.reminderPolicies ?? [])

        HabitHeatmapView(habit: habit, detail: detail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(LorvexDesign.Spacing.l)
    }
    // Re-identify the whole content per habit so the reused inspector rebuilds
    // fresh on a habit switch — otherwise per-habit `@State` in subviews
    // (reminder-editor draft time / mode, heatmap grid cache) would leak across
    // selections, e.g. a confirmed window-time edit writing to the wrong habit.
    .id(habit.id)
    // No `navigationTitle` here: as the Habits workspace's trailing inspector it
    // would override the window's title bar with the selected habit's name
    // instead of the active workspace, mirroring the same omission in
    // ``TaskDetailView``.
  }

  @ViewBuilder
  private func header(habit: LorvexHabit, recentCompletions: [String]) -> some View {
    // Period progress (this week for weekly/custom, this month for monthly,
    // today for daily/accumulative) — consistent with the card ring and the
    // meter below, rather than a today-raw `completionsToday >= targetCount`.
    let progress = HabitPeriodProgress.current(habit: habit, recentCompletions: recentCompletions)
    let isComplete = progress.isComplete
    let isMultiTarget = habit.targetCount > 1
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
        Image(systemName: habit.icon ?? "repeat.circle")
          .font(LorvexDesign.Typography.sectionHeader)
          .foregroundStyle(isComplete ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
          .frame(width: 36, height: 36)
          .background(
            (isComplete ? Color.green : Color.accentColor).opacity(0.12),
            in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))

        VStack(alignment: .leading, spacing: 2) {
          Text(habit.name)
            .font(LorvexDesign.Typography.screenTitle)
            .lineLimit(2)
          if let encouragement = habit.cue, !encouragement.isEmpty {
            // The encouragement — an inspiring line (sparkle + italic), not a dry
            // context label; matches the iOS habit detail.
            HStack(alignment: .top, spacing: LorvexDesign.Spacing.xs) {
              Image(systemName: "sparkles")
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(Color(lorvexHex: habit.color) ?? .accentColor)
              Text(encouragement)
                .font(LorvexDesign.Typography.secondaryText)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
          }
        }
        Spacer(minLength: 0)
        // The shared inspector ✕ (matches task + calendar panels); re-clicking
        // the habit card collapses it the same way.
        InspectorCloseButton(accessibilityIdentifier: "habit.detail.inspector.close") {
          store.selectedHabitID = nil
        }
      }

      HStack(spacing: LorvexDesign.Spacing.s) {
        if isMultiTarget {
          accumulativeStepper(habit: habit, isComplete: isComplete)
        } else {
          completeControl(habit: habit, isComplete: isComplete)
        }

        Button {
          store.prepareHabitDraft(for: habit)
          isEditing = true
        } label: {
          Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "pencil")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.lorvexNeutral)
        .help(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle))

        Button(role: .destructive) {
          isShowingDeleteConfirmation = true
        } label: {
          Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.lorvexNeutral)
        .help(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    }
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
        habit.name),
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: "habits.row.delete_confirm.delete", defaultValue: "Delete Habit", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive) {
        Task { await store.deleteHabit(habit) }
        store.selectedHabitID = nil
      }
      Button(String(localized: "common.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: {
      Text(LocalizedStringResource("habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: LorvexL10n.bundle))
    }
  }

  /// Binary-habit check-in control. `isComplete` is period progress, so a
  /// weekly/monthly habit shows "done" once its week/month plan is met. The clear
  /// action ("Reset Today") only appears when there is an actual today check-in to
  /// remove; a period met by earlier days shows a non-actioning "Done" so a tap
  /// can't log or clear a phantom today completion.
  @ViewBuilder
  private func completeControl(habit: LorvexHabit, isComplete: Bool) -> some View {
    let hasTodayCheckIn = habit.completionsToday > 0
    if isComplete && !hasTodayCheckIn {
      // Period met by earlier days: a non-actioning "Done" — there is no today
      // check-in to reset, and adding one would over-log the period.
      Button {} label: {
        Label(
          String(localized: "common.done", defaultValue: "Done", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "checkmark.circle.fill"
        )
      }
      .buttonStyle(.lorvex(.secondary))
      .disabled(true)
    } else {
      Button {
        Task {
          if isComplete { await store.uncompleteHabit(habit) }
          else { await store.completeHabit(habit) }
        }
      } label: {
        Label(
          isComplete
            ? String(localized: "habits.row.reset_today.title_case", defaultValue: "Reset Today", table: "Localizable", bundle: LorvexL10n.bundle)
            : String(localized: "habits.row.complete_today.title_case", defaultValue: "Complete Today", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: isComplete ? "arrow.counterclockwise" : "checkmark.circle"
        )
      }
      .buttonStyle(isComplete ? .lorvex(.secondary) : .lorvex(.primary))
    }
  }

  /// `[−] n/target [+]` stepper for accumulative habits (per-day target above
  /// one), matching the card: the ring/button only adds, so this is the way to
  /// correct the count down. Decrement disabled at zero, increment once the
  /// target is met.
  private func accumulativeStepper(habit: LorvexHabit, isComplete: Bool) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        Task { await store.adjustHabitCompletion(habit, delta: -1) }
      } label: {
        Image(systemName: "minus").frame(width: 22, height: 22)
      }
      .buttonStyle(.lorvexNeutral)
      .disabled(habit.completionsToday <= 0)
      .help(String(localized: "habits.row.decrement", defaultValue: "Remove one", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "habits.row.decrement", defaultValue: "Remove one", table: "Localizable", bundle: LorvexL10n.bundle))

      Text("\(habit.completionsToday)/\(habit.targetCount)")
        .font(LorvexDesign.Typography.primaryEmphasis.monospacedDigit())
        .foregroundStyle(isComplete ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
        .frame(minWidth: 40)
        .accessibilityLabel(String(
          format: String(
            localized: "habits.row.today_progress_a11y", defaultValue: "%1$lld of %2$lld done today",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          habit.completionsToday, habit.targetCount))

      Button {
        Task { await store.adjustHabitCompletion(habit, delta: 1) }
      } label: {
        Image(systemName: "plus").frame(width: 22, height: 22)
      }
      .buttonStyle(.lorvexNeutral)
      .disabled(isComplete)
      .help(String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle))
    }
  }
}
