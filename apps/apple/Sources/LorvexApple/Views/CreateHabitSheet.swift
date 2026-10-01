import LorvexCore
import SwiftUI

/// New Habit: the habit's icon, name, and encouragement on top, then its
/// rhythm and reminders as form sections (``CreationSheetLayout``).
struct CreateHabitSheet: View {
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    CreationSheetLayout(
      title: String(localized: "habits.sheet.create.title", defaultValue: "New Habit", table: "Localizable", bundle: LorvexL10n.bundle),
      height: 540) {
      HabitSheetHeader(store: store, idPrefix: "createHabit")
    } sections: {
      HabitFormSections(store: store, idPrefix: "createHabit")
      HabitDraftReminderField(store: store)
    } footer: {
      DraftSheetFooter(
        idPrefix: "createHabit",
        confirmTitle: String(localized: "common.create", defaultValue: "Create", table: "Localizable", bundle: LorvexL10n.bundle),
        confirmAccessibilityLabel: String(
          localized: "habits.sheet.create.a11y", defaultValue: "Create habit",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        isConfirmDisabled: store.draftHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || store.draftHabitTargetCountBlocksConfirm || store.isCreating,
        cancel: { isPresented = false },
        confirm: {
          Task {
            await store.createDraftHabit()
            if store.errorMessage == nil { isPresented = false }
          }
        }
      )
    }
    .onAppear { store.beginCreateHabitDraft() }
  }
}
