import LorvexCore
import SwiftUI

/// Phone/iPad recurrence builder for the selected task, at parity with the
/// macOS detail editor: an enable toggle, a frequency picker, an interval
/// stepper with the unit label, and weekday chips (shown only for weekly
/// frequency). Reads and writes the `MobileStore` recurrence draft state and
/// persists through `saveSelectedTaskRecurrence()`.
struct MobileStoreRecurrenceEditor: View {
  @Bindable var store: MobileStore
  let isSaving: Bool
  let dismiss: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(
            String(
              localized: "recurrence.repeat_task", defaultValue: "Repeat this task",
              table: "Localizable", bundle: MobileL10n.bundle), isOn: $store.taskDetailHasRecurrence
          )
        } footer: {
          if let recurrence = store.selectedTask?.recurrence {
            Text(
              String(
                format: String(
                  localized: "recurrence.currently", defaultValue: "Currently %@",
                  table: "Localizable", bundle: MobileL10n.bundle),
                recurrence.mobileLocalizedDisplaySummary(
                  exceptions: store.selectedTask?.recurrenceExceptions ?? [])))
          }
        }

        if store.taskDetailHasRecurrence {
          Section(
            String(
              localized: "recurrence.section.frequency", defaultValue: "Frequency",
              table: "Localizable", bundle: MobileL10n.bundle)
          ) {
            Picker(
              String(
                localized: "recurrence.repeats", defaultValue: "Repeats",
                table: "Localizable", bundle: MobileL10n.bundle),
              selection: $store.taskDetailRecurrenceAnchor
            ) {
              ForEach(TaskRecurrenceRule.Anchor.allCases, id: \.self) { anchor in
                Text(anchor.mobileLocalizedDisplayName).tag(anchor)
              }
            }
            Text(store.taskDetailRecurrenceAnchor.mobileLocalizedHint)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)

            Picker(
              String(
                localized: "recurrence.repeats", defaultValue: "Repeats", table: "Localizable",
                bundle: MobileL10n.bundle), selection: frequencyBinding
            ) {
              ForEach(TaskRecurrenceRule.Frequency.allCases, id: \.self) { frequency in
                Text(frequency.mobileLocalizedDisplayName).tag(frequency)
              }
            }
            .pickerStyle(.menu)

            Stepper(
              value: intervalBinding,
              in: 1...TaskRecurrenceEditorDraft.maximumInterval
            ) {
              Text(store.taskDetailRecurrenceFrequency.mobileLocalizedEveryInterval(intervalBinding.wrappedValue))
            }
          }

          if store.taskDetailRecurrenceAnchor == .schedule
            && store.taskDetailRecurrenceFrequency == .weekly
          {
            Section(
              String(
                localized: "recurrence.section.on_days", defaultValue: "On Days",
                table: "Localizable", bundle: MobileL10n.bundle)
            ) {
              MobileWeekdayPicker(
                selection: weekdaySelection,
                idPrefix: "task-recurrence",
                allowsEmpty: true)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
          }
        }
      }
      .disabled(isSaving)
      .navigationTitle(
        String(
          localized: "recurrence.title", defaultValue: "Recurrence", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle), action: dismiss)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(
            store.taskDetailHasRecurrence
              ? String(
                localized: "common.save", defaultValue: "Save", table: "Localizable",
                bundle: MobileL10n.bundle)
              : String(
                localized: "recurrence.remove", defaultValue: "Remove", table: "Localizable",
                bundle: MobileL10n.bundle)
          ) {
            Task {
              if await store.saveSelectedTaskRecurrence() {
                dismiss()
              }
            }
          }
          .disabled(isSaving || !store.taskDetailRecurrenceCanSave)
        }
      }
    }
  }

  private var frequencyBinding: Binding<TaskRecurrenceRule.Frequency> {
    Binding(
      get: { store.taskDetailRecurrenceFrequency },
      set: { store.setRecurrenceFrequency($0) }
    )
  }

  private var intervalBinding: Binding<Int> {
    Binding(
      get: { store.parsedTaskDetailRecurrenceInterval ?? 1 },
      set: { store.taskDetailRecurrenceIntervalText = String($0) }
    )
  }

  private var weekdaySelection: Binding<Set<Int>> {
    Binding(
      get: {
        Set(store.taskDetailRecurrenceDraft.weeklyDays.compactMap {
          TaskRecurrenceWeekday.allCases.firstIndex(of: $0)
        })
      },
      set: { indices in
        store.taskDetailRecurrenceDraft.weeklyDays = Set(indices.compactMap { index in
          TaskRecurrenceWeekday.allCases.indices.contains(index)
            ? TaskRecurrenceWeekday.allCases[index] : nil
        })
      })
  }
}
