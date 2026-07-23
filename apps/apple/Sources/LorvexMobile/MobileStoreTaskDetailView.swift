import LorvexCore
import SwiftUI

struct MobileStoreTaskDetailView: View {
  @State private var editDraft: MobileTaskEditDraft?
  @State private var isEditingRecurrence = false

  @Bindable var store: MobileStore
  let task: LorvexTask
  let isFocused: Bool
  let isMutating: Bool
  let saveEditDraft: (MobileTaskEditDraft) async -> Bool
  let toggleFocus: () async -> Void
  let complete: () async -> Void
  let reopen: () async -> Void
  let deferTask: () async -> Void
  let markSomeday: () async -> Void
  let toggleChecklistItem: (TaskChecklistItem) async -> Void
  let addChecklistItem: (String) async -> Bool
  let removeChecklistItem: (TaskChecklistItem) async -> Bool
  let addReminder: (Date) async -> Bool
  let removeReminder: (TaskReminder) async -> Bool
  let cancel: () async -> Void
  let tagSuggestions: [String]
  let searchDependencyCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let resolveDependencyTasks: ([LorvexTask.ID]) async -> [LorvexTask]

  var body: some View {
    MobileTaskDetailContent(
      task: task,
      timeZone: store.logicalTimeZone,
      toggleChecklistItem: toggleChecklistItem,
      addChecklistItem: { text in _ = await addChecklistItem(text) },
      removeChecklistItem: { item in _ = await removeChecklistItem(item) },
      addReminder: { date in _ = await addReminder(date) },
      removeReminder: { reminder in _ = await removeReminder(reminder) },
      resolveDependencyTasks: resolveDependencyTasks
    ) {
      MobileTaskActionSection(
        task: task,
        isFocused: isFocused,
        isMutating: isMutating,
        toggleFocus: toggleFocus,
        complete: complete,
        reopen: reopen,
        deferTask: deferTask,
        markSomeday: markSomeday,
        editRecurrence: {
          store.beginRecurrenceEditing()
          isEditingRecurrence = true
        },
        cancel: cancel,
        start: { await store.startTask(task.id) },
        markNotStarted: { await store.markTaskNotStarted(task.id) }
      )
    }
    .lorvexSpatialContainerPadding()
    .lorvexSpatialBackground()
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          editDraft = MobileTaskEditDraft(task: task)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }
      }
    }
    .sheet(isPresented: editSheetIsPresented) {
      if let draft = Binding($editDraft) {
        MobileTaskEditSheet(
          draft: draft,
          isSaving: isMutating,
          tagSuggestions: tagSuggestions,
          searchDependencyCandidates: searchDependencyCandidates,
          resolveDependencyTasks: resolveDependencyTasks,
          save: {
            if let editDraft {
              let saved = await saveEditDraft(editDraft)
              if saved {
                self.editDraft = nil
              }
            }
          },
          cancel: { editDraft = nil }
        )
        .lorvexSpatialBackground()
      }
    }
    .sheet(isPresented: $isEditingRecurrence) {
      MobileStoreRecurrenceEditor(
        store: store,
        isSaving: isMutating,
        dismiss: { isEditingRecurrence = false }
      )
      .lorvexSpatialBackground()
      // Recurrence editor detents: medium + large for rule tweaks without losing context.
      .mobileCompactEditorSheetPresentation()
    }
  }

  private var editSheetIsPresented: Binding<Bool> {
    Binding(
      get: { editDraft != nil },
      set: { isPresented in
        if !isPresented {
          editDraft = nil
        }
      }
    )
  }
}
