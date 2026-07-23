import LorvexCore
import SwiftUI

struct CreateHabitSheet: View {
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HabitFormFields(
        store: store,
        idPrefix: "createHabit",
        nameTitle: String(
          localized: "habits.sheet.create.title", defaultValue: "New habit name",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      )

      HabitDraftReminderField(store: store)

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
    .padding(20)
    .frame(minWidth: 400, idealWidth: 440)
    .onAppear { store.beginCreateHabitDraft() }
  }
}
