import LorvexCore
import SwiftUI

struct MobileTaskEditSheet: View {
  @Binding var draft: MobileTaskEditDraft
  let isSaving: Bool
  let tagSuggestions: [String]
  let searchDependencyCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let resolveDependencyTasks: ([LorvexTask.ID]) async -> [LorvexTask]
  let save: () async -> Void
  let cancel: () -> Void
  @FocusState private var focusedField: Field?
  /// A tag typed into the tag field but not yet added with Return.
  @State private var pendingTag = ""

  private enum Field {
    case title
    case notes
    case estimate
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          String(
            localized: "task_edit.section.task", defaultValue: "Task", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "task_edit.title_placeholder", defaultValue: "Title", table: "Localizable",
              bundle: MobileL10n.bundle), text: $draft.title
          )
          .focused($focusedField, equals: .title)
          .submitLabel(.next)
          .onSubmit { focusedField = .notes }
          Picker(
            String(
              localized: "task_edit.priority", defaultValue: "Priority", table: "Localizable",
              bundle: MobileL10n.bundle), selection: $draft.priority
          ) {
            ForEach(LorvexTask.Priority.allCases, id: \.self) { priority in
              Text(priority.localizedName).tag(priority)
            }
          }
          MobilePlainTextEditor(
            text: $draft.notes,
            placeholder: String(
              localized: "task_edit.notes_placeholder", defaultValue: "Notes", table: "Localizable",
              bundle: MobileL10n.bundle),
            minHeight: 120
          )
          .focused($focusedField, equals: .notes)
          .submitLabel(.next)
          .onSubmit { focusedField = .estimate }
        }

        Section(
          String(
            localized: "task_edit.section.planning", defaultValue: "Planning", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "task_edit.estimate", defaultValue: "Estimate", table: "Localizable",
              bundle: MobileL10n.bundle), text: $draft.estimatedMinutesText
          )
          .focused($focusedField, equals: .estimate)
          .submitLabel(.done)
          .onSubmit { Task { await commitPendingTagAndSave() } }
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .mobileKeyboardDoneToolbar { Task { await commitPendingTagAndSave() } }
        }

        Section {
          dateField(
            title: String(
              localized: "task_edit.due_date", defaultValue: "Due Date", table: "Localizable",
              bundle: MobileL10n.bundle),
            systemImage: "flag",
            isOn: $draft.hasDueDate,
            date: $draft.dueDate,
            idElement: "dueDate")
        } footer: {
          Text(
            String(
              localized: "task_edit.due_date.hint", defaultValue: "The deadline to finish by.",
              table: "Localizable", bundle: MobileL10n.bundle))
        }

        Section {
          dateField(
            title: String(
              localized: "task_edit.planned_date", defaultValue: "Planned Date",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "calendar",
            isOn: $draft.hasPlannedDate,
            date: $draft.plannedDate,
            idElement: "plannedDate")
          if draft.hasPlannedDate {
            MobileTaskTimeRows(
              time: $draft.plannedTime, day: draft.plannedDate, length: draft.parsedEstimatedMinutes)
          }
        } footer: {
          Text(
            String(
              localized: "task_edit.planned_date.hint",
              defaultValue: "The day you plan to work on it.", table: "Localizable",
              bundle: MobileL10n.bundle))
        }

        Section {
          dateField(
            title: String(
              localized: "task_edit.available_from", defaultValue: "Available From",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "eye.slash",
            isOn: $draft.hasAvailableFrom,
            date: $draft.availableFrom,
            idElement: "availableFrom")
        } footer: {
          Text(
            String(
              localized: "task_edit.available_from.hint",
              defaultValue: "Hidden from your lists until this day.", table: "Localizable",
              bundle: MobileL10n.bundle))
        }

        Section(
          String(
            localized: "task_edit.section.tags", defaultValue: "Tags", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          MobileTagTokenField(tags: $draft.tags, suggestions: tagSuggestions, entry: $pendingTag)
        }

        Section(
          String(
            localized: "task_edit.section.dependencies", defaultValue: "Dependencies",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          MobileDependencyField(
            dependencyIDs: $draft.dependencyIDs,
            ownTaskID: draft.id,
            searchCandidates: searchDependencyCandidates,
            resolveTitles: resolveDependencyTasks
          )
        }
      }
      .navigationTitle(
        String(
          localized: "sheet.edit_task", defaultValue: "Edit Task", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle), action: cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await commitPendingTagAndSave() }
          } label: {
            if isSaving {
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!draft.canSave || isSaving)
        }
      }
    }
    // Task editor detents: large only because tags, dependencies, and notes need full-height editing.
    .mobileFullEditorSheetPresentation()
  }

  /// Saves with any tag typed but not yet added, so pressing Save before
  /// Return keeps it.
  private func commitPendingTagAndSave() async {
    if !pendingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft.tags = MobileTagTokenField.merging(pendingTag, into: draft.tags)
      pendingTag = ""
    }
    await save()
  }

  /// One schedulable-date row: a toggle that reveals a day `DatePicker` when on.
  /// The three task dates (due / planned / available-from) share this so they
  /// read and behave identically; each carries a distinct `surface.region.element`
  /// accessibility identifier off `idElement`.
  @ViewBuilder
  private func dateField(
    title: String,
    systemImage: String,
    isOn: Binding<Bool>,
    date: Binding<Date>,
    idElement: String
  ) -> some View {
    Toggle(isOn: isOn.animation(.snappy)) {
      Label(title, systemImage: systemImage)
    }
    .accessibilityIdentifier("task.edit.\(idElement).toggle")
    if isOn.wrappedValue {
      DatePicker(
        String(
          localized: "task_edit.date", defaultValue: "Date", table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: date,
        displayedComponents: .date
      )
      .accessibilityIdentifier("task.edit.\(idElement).picker")
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }
}
