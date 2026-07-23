import SwiftUI

struct MobileStoreCreateHabitSheet: View {
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool
  @FocusState private var focusedField: Field?

  private enum Field {
    case name
    case cue
    case target
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(String(localized: "habits.section.habit", defaultValue: "Habit", table: "Localizable", bundle: MobileL10n.bundle)) {
          TextField(String(localized: "habits.field.name", defaultValue: "Name", table: "Localizable", bundle: MobileL10n.bundle), text: $store.habitDraft.name)
            .textContentType(.none)
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .cue }
            .accessibilityIdentifier("mobileCreateHabit.name")
        }
        Section {
          MobileIconColorPicker(
            icon: $store.habitDraft.icon,
            color: $store.habitDraft.color,
            fallbackIcon: "repeat",
            iconChoices: MobileIconChoices.habit
          )
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        }
        Section {
          TextField(
            String(localized: "habits.field.encouragement", defaultValue: "Encouragement", table: "Localizable", bundle: MobileL10n.bundle),
            text: $store.habitDraft.cue, axis: .vertical
          )
          .lineLimit(2...4)
          .focused($focusedField, equals: .cue)
          .submitLabel(.next)
          .onSubmit { focusedField = .target }
          .accessibilityIdentifier("mobileCreateHabit.cue")
        } footer: {
          Text(String(localized: "habits.field.encouragement.footer", defaultValue: "A motivating line you’ll see on the habit — e.g. \u{201C}Read 30 minutes and your mind grows richer.\u{201D}", table: "Localizable", bundle: MobileL10n.bundle))
        }

        MobileHabitCadenceSection(draft: $store.habitDraft, idPrefix: "mobileCreateHabit")

        if store.habitDraft.showsPerDayTarget {
          Section(String(localized: "habits.section.goal", defaultValue: "Goal", table: "Localizable", bundle: MobileL10n.bundle)) {
            TextField(String(localized: "habits.field.target_per_day", defaultValue: "Target per day", table: "Localizable", bundle: MobileL10n.bundle), text: $store.habitDraft.targetCountText)
              .focused($focusedField, equals: .target)
              .submitLabel(.done)
              .onSubmit { submit() }
              #if os(iOS) || os(visionOS)
                .keyboardType(.numberPad)
              #endif
              .mobileKeyboardDoneToolbar { submit() }
              .accessibilityIdentifier("mobileCreateHabit.targetCount")
          }
        }

        MobileHabitMilestoneGoalField(
          text: $store.habitDraft.milestoneTargetText,
          frequencyType: store.habitDraft.frequencyType,
          idPrefix: "mobileCreateHabit")
      }
      .navigationTitle(String(localized: "sheet.new_habit", defaultValue: "New Habit", table: "Localizable", bundle: MobileL10n.bundle))
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
              ProgressView()
            } else {
              Text(String(localized: "common.create", defaultValue: "Create", table: "Localizable", bundle: MobileL10n.bundle))
            }
          }
          .disabled(!store.canCreateHabitDraft)
          .accessibilityIdentifier("mobileCreateHabit.confirm")
        }
      }
    }
    // Habit editor detents: medium + large for cue/goal edits without a full screen jump.
    .mobileCompactEditorSheetPresentation()
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
