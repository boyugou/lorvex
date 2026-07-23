import LorvexCore
import SwiftUI

struct EditHabitSheet: View {
  let habit: LorvexHabit
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      header

      HabitFormFields(store: store, idPrefix: "editHabit")

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
    .padding(20)
    .frame(minWidth: 400, idealWidth: 440)
  }

  private var header: some View {
    DraftSheetHeader(
      title: String(localized: "habits.sheet.edit.title", defaultValue: "Edit Habit", table: "Localizable", bundle: LorvexL10n.bundle),
      subtitle: String(
        localized: "habits.sheet.edit.description",
        defaultValue: "Tune the routine cue and daily target.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "repeat"
    )
  }
}
