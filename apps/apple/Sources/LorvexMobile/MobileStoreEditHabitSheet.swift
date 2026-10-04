import LorvexCore
import SwiftUI

struct MobileStoreEditHabitSheet: View {
  let habit: LorvexHabit
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          MobileHabitSheetHeader(store: store, idPrefix: "mobileEditHabit")
        }

        MobileHabitCadenceSection(draft: $store.habitDraft, idPrefix: "mobileEditHabit")

        MobileHabitGoalSection(draft: $store.habitDraft, idPrefix: "mobileEditHabit")

        MobileHabitMilestoneGoalField(
          text: $store.habitDraft.milestoneTargetText,
          frequencyType: store.habitDraft.frequencyType,
          idPrefix: "mobileEditHabit")
      }
      .mobileSheetTitle(String(localized: "sheet.edit_habit", defaultValue: "Edit Habit", table: "Localizable", bundle: MobileL10n.bundle))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle)) {
            isPresented = false
          }
          .accessibilityIdentifier("mobileEditHabit.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            submit()
          } label: {
            if store.isUpdatingHabit {
              ProgressView().tint(.white)
            } else {
              Text(String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.canUpdateHabitDraft)
          .accessibilityIdentifier("mobileEditHabit.confirm")
        }
      }
    }
    // The habit form is a dense form, so it opens at full height.
    .mobileFullEditorSheetPresentation()
  }

  private func submit() {
    Task {
      let updated = await store.updateHabit(habit)
      if updated {
        isPresented = false
      }
    }
  }
}
