import LorvexCore
import SwiftUI

/// A habit's detail: who it is, what to do about it today, where it stands,
/// and its reminders.
///
/// The header and the day's actions come first so completing the habit never
/// needs a scroll. Every number then appears once: the cadence and lifetime
/// count as a line under the name, the period's progress, streaks, and 30-day
/// rate in the momentum card, and the next milestone in its own card. Archiving
/// and deleting the habit are the last things on the page, away from the
/// everyday actions: Archive takes it off the active list with its history
/// kept, Delete asks first because it erases that history.
/// The panel fills the width it is given: a split's detail pane as it is, and
/// a pushed screen inset to the enclosing screen's readable margin, which a
/// scroll view only honors when it applies the margin itself.
struct MobileHabitDetailPanel: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail?
  let isMutating: Bool
  let editHabit: () -> Void
  let deleteHabit: () async -> Bool
  let archiveHabit: () async -> Bool
  let complete: () async -> Bool
  let reset: () async -> Bool
  // Reminder-editing closures. When supplied the reminders block is interactive
  // (add / retime / enable-disable / remove); when nil it renders read-only.
  var addReminder: ((String) async -> Void)? = nil
  var setReminderTime: ((HabitReminderPolicy, String) async -> Void)? = nil
  var toggleReminder: ((HabitReminderPolicy) async -> Void)? = nil
  var removeReminder: ((HabitReminderPolicy) async -> Void)? = nil

  @State private var isConfirmingDelete = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        primaryActions
        if let milestone = habit.milestone {
          milestoneCard(milestone)
        }
        MobileHabitVisualizationSection(habit: habit, detail: detail)
        MobileHabitReminderList(
          policies: detail?.reminderPolicies ?? [],
          isMutating: isMutating,
          addReminder: addReminder,
          setReminderTime: setReminderTime,
          toggleReminder: toggleReminder,
          removeReminder: removeReminder)
        lifecycleActions
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(LorvexDesign.Spacing.xl)
    }
    // Offset and growth only, not alignment: a page shorter than the screen
    // still starts at the top.
    .defaultScrollAnchor(Self.initialScrollAnchor, for: .initialOffset)
    .defaultScrollAnchor(Self.initialScrollAnchor, for: .sizeChanges)
    .mobileReadableScrollMargins()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LorvexDesign.Palette.groupedBackground)
    .accessibilityIdentifier("mobileHabits.detail.panel")
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: MobileL10n.bundle),
        habit.name),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), role: .destructive) {
        Task { _ = await deleteHabit() }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(localized: "habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  /// Where the page first rests: its top, except in DEBUG builds launched with
  /// `-lorvexScrollHabitDetailToEnd`, which open it at its end for a
  /// screenshot of the reminders and the Archive and Delete buttons, or with
  /// `-lorvexScrollHabitDetailToMiddle`, which open it on the middle of its
  /// content for a screenshot of the Progress panels on a tall page.
  private static var initialScrollAnchor: UnitPoint? {
    #if DEBUG
      if MobileStore.debugScrollHabitDetailToEnd { return .bottom }
      if MobileStore.debugScrollHabitDetailToMiddle { return .center }
      return nil
    #else
      nil
    #endif
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: habit.tileSymbol, tint: habit.tileTint, size: 56)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        Text(userContent: habit.name)
          .font(LorvexDesign.Typography.detailTitle)
        if let encouragement = habit.cue, !encouragement.isEmpty {
          // The encouragement — a motivating line, set as an inspiring callout
          // (a sparkle + italic), not a dry context label.
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
            Image(systemName: "sparkles")
              .font(.footnote)
              .foregroundStyle(habit.tileTint)
            Text(userContent: encouragement)
              .font(LorvexDesign.Typography.primaryText)
              .italic()
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Text(factsLine)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .accessibilityIdentifier("mobileHabits.detail.facts")
      }
    }
  }

  /// "Daily · 12 completions": the habit's cadence and its lifetime count, the
  /// two facts about it that are not progress.
  private var factsLine: String {
    let cadence = MobileHabitDisplayText.frequencyName(habit.frequencyType)
    let count = habit.totalCompletions
    let completions =
      count == 0
      ? String(localized: "habits.detail.completions_none", defaultValue: "No completions yet", table: "Localizable", bundle: MobileL10n.bundle)
      : String(localized: "habits.detail.completions_count", defaultValue: "\(count) completions", table: "Localizable", bundle: MobileL10n.bundle)
    return String(
      format: String(localized: "habits.detail.facts", defaultValue: "%1$@ · %2$@", table: "Localizable", bundle: MobileL10n.bundle),
      cadence, completions)
  }

  /// Complete (or Reset) and Edit side by side, stacked when a large text size
  /// leaves no room for both on one line.
  private var primaryActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        completeAction
        editAction
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        completeAction
        editAction
      }
    }
  }

  /// Complete Today is the page's prominent button while the day is open. Once
  /// the habit is done, Reset Today is an undo, so it steps back to the
  /// bordered style beside Edit rather than leading the page.
  @ViewBuilder
  private var completeAction: some View {
    let button = Button {
      Task {
        if habit.isCompleteToday {
          _ = await reset()
        } else {
          _ = await complete()
        }
      }
    } label: {
      Label(
        habit.isCompleteToday
        ? String(localized: "habits.detail.reset", defaultValue: "Reset Today", table: "Localizable", bundle: MobileL10n.bundle)
        : String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: habit.isCompleteToday ? "arrow.counterclockwise" : "checkmark")
    }
    .disabled(isMutating)
    .accessibilityIdentifier("mobileHabits.detail.complete")
    if habit.isCompleteToday {
      button.buttonStyle(.bordered)
    } else {
      button.buttonStyle(.borderedProminent)
    }
  }

  private var editAction: some View {
    Button {
      editHabit()
    } label: {
      Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
    }
    .buttonStyle(.bordered)
    .disabled(isMutating)
    .accessibilityIdentifier("mobileHabits.detail.edit")
  }

  private func milestoneCard(_ milestone: HabitMilestoneInfo) -> some View {
    MobileHabitMilestoneProgressView(
      milestone: milestone,
      frequencyType: habit.frequencyType,
      tint: habit.tileTint,
      style: .detail
    )
    .padding(LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LorvexDesign.Palette.card,
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
  }

  /// Archive and Delete side by side, stacked when a large text size leaves
  /// no room for both on one line.
  private var lifecycleActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        archiveAction
        deleteAction
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        archiveAction
        deleteAction
      }
    }
  }

  private var archiveAction: some View {
    Button {
      Task { _ = await archiveHabit() }
    } label: {
      Label(MobileHabitArchiveCopy.archiveHabit, systemImage: "archivebox")
    }
    .buttonStyle(.bordered)
    .disabled(isMutating)
    .accessibilityIdentifier("mobileHabits.detail.archive")
  }

  private var deleteAction: some View {
    Button(role: .destructive) {
      isConfirmingDelete = true
    } label: {
      Label(String(localized: "habits.detail.delete_habit", defaultValue: "Delete Habit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .buttonStyle(.bordered)
    .mobileDestructiveBorderedStyle()
    .disabled(isMutating)
    .accessibilityIdentifier("mobileHabits.detail.delete")
  }
}
