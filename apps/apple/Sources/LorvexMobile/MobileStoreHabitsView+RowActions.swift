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
      .tint(.orange)
      .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
    } else {
      Button {
        Task { await store.completeHabit(habit) }
      } label: {
        Label(
          String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "checkmark.circle")
      }
      .tint(.green)
      .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
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
  }

  func habitDeleteAction(_ habit: LorvexHabit) -> some View {
    Button(role: .destructive) {
      confirmingDeleteHabit = habit
    } label: {
      Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .disabled(store.isMutatingHabit || store.isDeletingHabit || isBatchSelecting)
  }
}
