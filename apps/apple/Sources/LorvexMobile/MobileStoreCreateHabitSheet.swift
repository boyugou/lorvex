import SwiftUI

struct MobileStoreCreateHabitSheet: View {
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          MobileHabitSheetHeader(store: store, idPrefix: "mobileCreateHabit", focusesNameOnAppear: true)
        }

        MobileHabitCadenceSection(draft: $store.habitDraft, idPrefix: "mobileCreateHabit")

        MobileHabitGoalSection(draft: $store.habitDraft, idPrefix: "mobileCreateHabit")

        MobileHabitMilestoneGoalField(
          text: $store.habitDraft.milestoneTargetText,
          frequencyType: store.habitDraft.frequencyType,
          idPrefix: "mobileCreateHabit")
      }
      .navigationTitle(String(localized: "sheet.new_habit", defaultValue: "New Habit", table: "Localizable", bundle: MobileL10n.bundle))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle)) {
            isPresented = false
          }
          .accessibilityIdentifier("mobileCreateHabit.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            submit()
          } label: {
            if store.isCreatingHabit {
              ProgressView().tint(.white)
            } else {
              Text(String(localized: "common.create", defaultValue: "Create", table: "Localizable", bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.canCreateHabitDraft)
          .accessibilityIdentifier("mobileCreateHabit.confirm")
        }
      }
    }
    // The habit form is a dense form, so it opens at full height.
    .mobileFullEditorSheetPresentation()
    .onAppear { store.beginCreateHabitDraft() }
  }

  private func submit() {
    Task {
      let created = await store.createDraftHabit()
      if created {
        isPresented = false
      }
    }
  }
}
