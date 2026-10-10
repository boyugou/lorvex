import LorvexCore
import SwiftUI

extension MobileStoreHabitsView {
  /// The swipe/context-menu completion action: reset once today's target is met,
  /// otherwise log another completion. Disabled while a habit mutation is in
  /// flight or while batch selecting.
  @ViewBuilder
  func habitCompletionAction(_ habit: LorvexHabit) -> some View {
    if habit.isCompleteToday {
      Button {
        Task { await store.uncompleteHabit(habit) }
      } label: {
        Label(
          String(localized: "habits.detail.reset", defaultValue: "Reset Today", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "arrow.counterclockwise")
      }
      .tint(LorvexDesign.Palette.dueSoon)
      .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    } else {
      Button {
        Task { await store.completeHabit(habit) }
      } label: {
        Label(
          String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "checkmark.circle")
      }
      .tint(LorvexDesign.Palette.done)
      .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    }
  }

  /// The swipe/context-menu skip action: Skip Today, or Undo Skip once today is
  /// set aside. Absent while today holds a check-in, which a skip cannot share
  /// the day with. Its tint is cleared, so the swipe button takes the system's
  /// neutral gray: the day is set aside, not lost.
  @ViewBuilder
  func habitSkipAction(_ habit: LorvexHabit) -> some View {
    if let action = LorvexHabitSkip.action(for: habit) {
      Button {
        Task { await store.toggleHabitSkip(habit) }
      } label: {
        Label(
          MobileHabitSkipCopy.title(for: action),
          systemImage: MobileHabitSkipCopy.systemImage(for: action))
      }
      .tint(action == .unskip ? LorvexDesign.Palette.dueSoon : nil)
      .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
      .accessibilityIdentifier("mobileHabits.skip.\(habit.id)")
    }
  }

  func habitEditAction(_ habit: LorvexHabit) -> some View {
    Button {
      store.prepareHabitDraft(for: habit)
      editingHabit = habit
    } label: {
      Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
    }
    .tint(.accentColor)
    .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    .accessibilityIdentifier("mobileHabits.edit.\(habit.id)")
  }

  /// Archives the habit: it leaves the catalog, Today, and reminders but keeps
  /// its history, and the archived section below the catalog restores it. The
  /// swipe draws it in neutral gray (``SwiftUI/View/mobileNeutralSwipeStyle()``).
  func habitArchiveAction(_ habit: LorvexHabit) -> some View {
    Button {
      Task { await store.setHabitArchived(habit, archived: true) }
    } label: {
      Label(MobileHabitArchiveCopy.archive, systemImage: "archivebox")
    }
    .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    .accessibilityIdentifier("mobileHabits.archive.\(habit.id)")
  }

  /// The context-menu delete: it asks first, from the row, and the menu's
  /// `destructive` role draws it red.
  func habitDeleteAction(_ habit: LorvexHabit) -> some View {
    Button(role: .destructive) {
      confirmingDeleteHabit = habit
    } label: {
      Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    .accessibilityIdentifier("mobileHabits.delete.\(habit.id)")
  }

  /// The swipe delete: the same request as ``habitDeleteAction(_:)``, drawn red
  /// by a tint rather than by the `destructive` role, which would collapse the
  /// row and close the confirmation attached to it.
  func habitDeleteSwipeAction(_ habit: LorvexHabit) -> some View {
    Button {
      confirmingDeleteHabit = habit
    } label: {
      Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .mobileDestructiveSwipeStyle()
    .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    .accessibilityIdentifier("mobileHabits.delete.\(habit.id)")
  }
}
