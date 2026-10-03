import LorvexCore
import SwiftUI

struct MobileStoreTaskDetailView: View {
  @State private var editDraft: MobileTaskEditDraft?
  @State private var isEditingRecurrence = false
  /// The field being edited from its property row or the Add menu, with a
  /// draft opened from the task for that one field.
  @State private var editingField: MobileTaskField?
  @State private var fieldDraft: MobileTaskEditDraft?
  @Environment(\.mobileDetailPresentation) private var presentation

  @Bindable var store: MobileStore
  let task: LorvexTask
  let isMutating: Bool
  let saveEditDraft: (MobileTaskEditDraft) async -> Bool
  let actions: MobileTaskRowActions
  let reopen: () async -> Void
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
      resolveDependencyTasks: resolveDependencyTasks,
      dependencyRefreshKey: store.taskWorkspaceRevision,
      completeDependency: { dependency in _ = await store.completeTask(dependency.id) },
      isDependencyMutating: { store.taskIsMutating($0) },
      properties: MobileTaskProperties(task: task, listName: listName, logicalDay: store.logicalTodayString),
      shareText: MobileShareText.task(task, listName: listName, logicalDay: store.logicalTodayString),
      editField: edit
    ) { isHeldUp in
      MobileTaskActionSection(
        task: task,
        isMutating: isMutating,
        isHeldUp: isHeldUp,
        actions: actions,
        markSomeday: markSomeday,
        cancel: cancel
      )
    } paneActions: {
      paneStatusButton
      editButton
        .buttonStyle(.bordered)
    }
    .toolbar {
      // A screen of its own carries the actions in its bar; a split's pane
      // shows them in its header row instead (`paneActions` above).
      if presentation == .screen {
        ToolbarItem(placement: .primaryAction) {
          editButton
        }
        // The status transition is the detail's one prominent control: a tinted
        // filled capsule at the trailing edge, split from the share/edit group
        // so it reads as the primary action rather than one more icon.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
          primaryStatusButton
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
      }
    }
    .sheet(item: $editingField, onDismiss: { fieldDraft = nil }) { field in
      if let draft = Binding($fieldDraft) {
        MobileTaskFieldEditor(
          field: field,
          draft: draft,
          lists: store.lists?.lists ?? [],
          currentListID: task.listID,
          tagSuggestions: tagSuggestions,
          searchDependencyCandidates: searchDependencyCandidates,
          resolveDependencyTasks: resolveDependencyTasks,
          isSaving: isMutating,
          save: {
            guard let fieldDraft else { return }
            if await saveEditDraft(fieldDraft) { editingField = nil }
          },
          moveToList: { listID in
            await store.moveTask(task.id, toListID: listID)
            editingField = nil
          },
          cancel: { editingField = nil }
        )
      }
    }
    #if DEBUG
      .onAppear {
        // Dev/QA only: the `lorvex://firsttask/field/…` screenshot hook raises
        // one word's editor so it can be captured without a tap.
        if let field = MobileTaskDetailDebugState.takeInitialField() { edit(field) }
      }
    #endif
    .sheet(isPresented: $isEditingRecurrence) {
      MobileStoreRecurrenceEditor(
        store: store,
        isSaving: isMutating,
        dismiss: { isEditingRecurrence = false }
      )
      // Recurrence editor detents: medium + large for rule tweaks without losing context.
      .mobileCompactEditorSheetPresentation()
    }
  }

  /// Opens the editor behind one field: the recurrence editor for Repeat,
  /// otherwise the single-field sheet over a draft of the task.
  private func edit(_ field: MobileTaskField) {
    if field == .recurrence {
      store.beginRecurrenceEditing()
      isEditingRecurrence = true
    } else {
      fieldDraft = MobileTaskEditDraft(task: task)
      editingField = field
    }
  }

  private var listName: String? {
    guard let listID = task.listID else { return nil }
    return store.lists?.lists.first { $0.id == listID }?.displayName
  }

  private var editButton: some View {
    Button {
      editDraft = MobileTaskEditDraft(task: task)
    } label: {
      Label(
        String(
          localized: "common.edit", defaultValue: "Edit", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "pencil")
    }
  }

  // Which transition the button performs follows the task's status
  // (`MobileTaskPrimaryStatusAction`): Complete for an active task, Reopen for
  // a resolved one, Move to Open for a parked one. Title only — the tinted fill
  // already marks it as the primary action, and the text stays short in both
  // shipped languages.
  private var primaryStatusButton: some View {
    let action = MobileTaskPrimaryStatusAction(status: task.status)
    return Button {
      perform(action)
    } label: {
      Text(action.title)
    }
    .mobileProminentToolbarButtonStyle()
    .tint(action.tint)
    .disabled(isMutating)
    .accessibilityIdentifier(action.accessibilityIdentifier)
  }

  /// The same transition as `primaryStatusButton`, as the prominent button of
  /// a split pane's header row, where an icon beside the title matches the
  /// Edit and Share buttons next to it.
  private var paneStatusButton: some View {
    let action = MobileTaskPrimaryStatusAction(status: task.status)
    return Button {
      perform(action)
    } label: {
      Label(action.title, systemImage: action.systemImage)
    }
    .buttonStyle(.borderedProminent)
    .tint(action.tint)
    .disabled(isMutating)
    .accessibilityIdentifier(action.accessibilityIdentifier)
  }

  private func perform(_ action: MobileTaskPrimaryStatusAction) {
    Task {
      if action.performsReopen {
        await reopen()
      } else {
        await actions.complete()
      }
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
