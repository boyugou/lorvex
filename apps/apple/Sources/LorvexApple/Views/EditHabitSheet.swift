import LorvexCore
import SwiftUI

/// Edit Habit: the same header and rhythm sections as New Habit. Reminders of
/// a saved habit are edited in its inspector, so this sheet has none.
struct EditHabitSheet: View {
  let habit: LorvexHabit
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    CreationSheetLayout(
      title: String(localized: "habits.sheet.edit.title", defaultValue: "Edit Habit", table: "Localizable", bundle: LorvexL10n.bundle),
      height: 430) {
      HabitSheetHeader(store: store, idPrefix: "editHabit")
    } sections: {
      HabitFormSections(store: store, idPrefix: "editHabit")
    } footer: {
      DraftSheetFooter(
        idPrefix: "editHabit",
        confirmTitle: String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: LorvexL10n.bundle),
        confirmAccessibilityLabel: String(
          localized: "habits.sheet.edit.save_a11y", defaultValue: "Save habit",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        isConfirmDisabled: store.draftHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || store.draftHabitTargetCountBlocksConfirm || store.isCreating,
        cancel: { isPresented = false },
        confirm: {
          Task {
            await store.updateHabit(habit)
            if store.errorMessage == nil { isPresented = false }
          }
        }
      )
    }
  }
}
