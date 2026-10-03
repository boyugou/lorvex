import LorvexCore
import SwiftUI

struct TaskDetailView: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) var undoManager
  @Environment(\.openWindow) var openWindow

  @FocusState var titleFieldFocused: Bool

  var body: some View {
    Group {
      if let task = store.selectedTask {
        ScrollView {
          InspectorColumn {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
              headerSection(task: task)
              headerActions(task: task)
              properties(task: task)
              checklistSection(task: task)
              notesSection(task: task)
              assistantContextSection(task: task)
            }
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(.quaternary.opacity(0.035))
      } else {
        InspectorColumn {
          noTaskSelectedEmptyState
        }
        .background(.quaternary.opacity(0.035))
      }
    }
    // No `navigationTitle` here: as the main window's inspector, its title would
    // override the window's title bar with "Detail" instead of the active
    // workspace (Today / Calendar / …). The standalone task-detail window (the
    // `.taskDetail` `Window` scene in `lorvexWorkspaceScenes`) supplies its own
    // static "Task Detail" title from the scene initializer, so this view adds none.
    .onAppear {
      store.syncSelectedTaskDraft()
      Task { await store.loadSelectedTaskDetail() }
    }
    .onChange(of: titleFieldFocused) { _, isFocused in
      guard !isFocused else { return }
      Task { await store.saveSelectedTaskDraftIfNeeded() }
    }
    // Autosave ~1.2s after the user stops editing any draft field. Blur and
    // navigation saves still run; this covers the paths they miss — closing
    // the window or quitting with focus still in a field. Each keystroke
    // changes the fingerprint, cancelling the pending sleep (debounce).
    .task(id: store.taskDetailDraftFingerprint) {
      guard let id = store.selectedTaskID, store.taskDetailDraftHasChanges(for: id) else { return }
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      await store.saveSelectedTaskDraftIfNeeded()
    }
    .onChange(of: store.selectedTaskID) { oldValue, newValue in
      Task {
        if let oldValue,
          oldValue != newValue,
          store.taskDetailDraftHasChanges(for: oldValue)
        {
          // Save on navigation even when the estimate field is malformed —
          // `saveTaskDetailDraft` keeps the task's existing estimate in that
          // case so the user's title / notes / priority edits aren't dropped.
          await store.saveTaskDetailDraft(id: oldValue, preserveSelection: newValue)
        } else {
          store.syncSelectedTaskDraft()
        }
        await store.loadSelectedTaskDetail()
      }
    }
    // Re-read the tasks the selected task waits on when it, its dependencies,
    // or its status change, and whenever the store re-reads task data, which
    // is how a dependency finished here, on another device, or by the
    // assistant reaches the detail.
    .task(id: StartGateKey(task: store.selectedTask, taskDataGeneration: store.taskDataGeneration)) {
      await store.refreshSelectedTaskStartGate()
    }
    // The Waits on row names the task the draft waits on, which no loaded
    // list may hold; re-read its title as the draft or task data change.
    .task(
      id: DependencyTitleKey(
        dependencies: store.taskDetailDependencies, taskDataGeneration: store.taskDataGeneration)
    ) {
      await store.refreshTaskDetailDependencyTitles()
    }
    .onDisappear {
      // Closing a detail/workspace window cancels the view-owned debounce.
      // Capture the current target and hand the write to the store, which
      // outlives this view. Normal application Quit has an AppKit barrier too.
      guard let id = store.selectedTaskID, store.taskDetailDraftHasChanges(for: id) else { return }
      Task { await store.saveTaskDetailDraft(id: id, preserveSelection: id) }
    }
    .userActivity(LorvexActivityType.openTask, isActive: store.selectedTaskID != nil) { activity in
      guard let taskID = store.selectedTaskID else { return }
      configureOpenTaskActivity(activity, taskID: taskID, title: store.selectedTask?.title)
    }
  }

  /// What the Waits on row's title depends on: the draft's dependencies and
  /// the store's latest re-read of task data.
  private struct DependencyTitleKey: Hashable {
    var dependencies: [LorvexTask.ID]
    var taskDataGeneration: UInt64
  }

  /// What the Start gate depends on: the selected task's identity, status, and
  /// dependencies, and the store's latest re-read of task data.
  private struct StartGateKey: Hashable {
    var taskID: LorvexTask.ID?
    var status: LorvexTask.Status?
    var dependsOn: [LorvexTask.ID]
    var taskDataGeneration: UInt64

    init(task: LorvexTask?, taskDataGeneration: UInt64) {
      taskID = task?.id
      status = task?.status
      dependsOn = task?.dependsOn ?? []
      self.taskDataGeneration = taskDataGeneration
    }
  }

  private var noTaskSelectedEmptyState: some View {
    LorvexEmptyStatePanel(
      title: String(localized: "task_detail.empty.no_selection", defaultValue: "No Task Selected", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "task_detail.empty.no_selection_description",
        defaultValue: "Select a task from Today, Tasks, Lists, or Calendar to review its details here.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "checklist",
      tint: .accentColor,
      style: .inline,
      chips: [
        LorvexEmptyStateChip(
          title: String(localized: "task_detail.empty.inspector_chip", defaultValue: "Inspector", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sidebar.right",
          tint: .accentColor
        )
      ]
    )
  }

  /// The assistant's own note about why this task exists. Read-only by contract:
  /// `ai_notes` is written through MCP, and an editable field here would let a
  /// human silently overwrite the assistant's reasoning.
  @ViewBuilder
  func assistantContextSection(task: LorvexTask) -> some View {
    if let notes = task.aiNotes, !notes.isEmpty {
      aiNotesContent(task: task)
    }
  }

  // MARK: - Properties

  /// The task's set fields as rows, with the fields it does not carry yet as
  /// dashed additions beneath. List, priority, and repeat open native menus;
  /// every other field opens its editor in a popover.
  func properties(task: LorvexTask) -> some View {
    let content = propertyContent(task: task)
    return InspectorProperties(
      rows: content.rows, additions: content.additions, idPrefix: "task.detail",
      menuFieldIDs: ["list", "priority", "repeat"]
    ) { id in
      wordEditor(id, task: task)
    } menuItems: { id, openEditor in
      switch id {
      case "list": listMenuItems(task: task)
      case "priority": priorityMenuItems(task: task)
      default: repeatMenuItems(openEditor: openEditor)
      }
    }
  }

  /// One row per set field, in the order a person plans a task: when and for
  /// how long, the deadline, where it belongs and how urgent it is, then how
  /// it repeats, reminds, is tagged, waits, and hides. An unset field becomes
  /// an addition instead, in the same order.
  func propertyContent(task: LorvexTask) -> (rows: [InspectorPropertyRow], additions: [InspectorPropertyAddition]) {
    typealias Copy = TaskDetailSentenceCopy
    var rows: [InspectorPropertyRow] = []
    var additions: [InspectorPropertyAddition] = []
    func field(
      _ id: String, _ systemImage: String, _ label: String, _ value: String?, tint: Color? = nil,
      isUserContent: Bool = false
    ) {
      if let value {
        rows.append(
          .init(
            id: id, systemImage: systemImage, label: label, value: value, tint: tint,
            isUserContent: isUserContent))
      } else {
        additions.append(.init(id: id, label: label))
      }
    }
    let priority = displayPriority(for: task)
    field("doOn", "calendar", Copy.addWhen, store.taskDetailDoOnSummary)
    field("estimate", "hourglass", Copy.addLength, store.taskDetailEstimateSummary)
    field("due", "flag", Copy.addDue, store.taskDetailDueSummary.map { Self.sentenceCased($0) }, tint: dueTint)
    field("list", "list.bullet", Copy.addList, store.taskDetailListSummary(task: task))
    field(
      "priority", "exclamationmark.circle", Copy.addPriority,
      priority == .p2 ? nil : priority.localizedName, tint: priorityTint(priority))
    field("repeat", "repeat", Copy.addRepeat, store.taskDetailRepeatSummary)
    field("reminders", "bell", Copy.addReminder, store.taskDetailRemindersSummary(task: task))
    field("tags", "tag", Copy.addTag, store.taskDetailTagsSummary)
    // The task it waits on by title, or how many when it waits on several.
    let waitsOnTitle = store.taskDetailWaitsOnTitle
    field(
      "dependencies", "arrow.triangle.branch", Copy.addWaitsOn,
      waitsOnTitle ?? store.taskDetailDependencyCountSummary, isUserContent: waitsOnTitle != nil)
    field("hideUntil", "eye.slash", Copy.addHideUntil, store.taskDetailHideUntilSummary.map { Self.sentenceCased($0) })
    return (rows, additions)
  }

  /// A value phrase written to follow other words ("the same day") as it
  /// reads standing alone in a row ("The same day"), capitalized by the rules of
  /// the app's language (Turkish "i" becomes "İ"). Scripts without case are
  /// unchanged.
  static func sentenceCased(_ phrase: String, locale: Locale = LorvexClockFormat.displayLocale) -> String {
    guard let first = phrase.first else { return phrase }
    return String(first).uppercased(with: locale) + phrase.dropFirst()
  }

  /// Red once the deadline has passed, orange when it is today or tomorrow.
  private var dueTint: Color? {
    guard store.taskDetailHasDueDate,
      let offset = lorvexDayOffset(from: store.logicalTodayDateString, to: store.taskDetailDueDatePickerDate)
    else { return nil }
    if offset < 0 { return LorvexDesign.Palette.overdue }
    if offset <= 1 { return LorvexDesign.Palette.dueSoon }
    return nil
  }

  private func priorityTint(_ priority: LorvexTask.Priority) -> Color? {
    priority == .p1 ? LorvexDesign.Palette.priorityHigh : nil
  }

  // MARK: - Word pickers

  /// The popover behind one word: only that field's control.
  @ViewBuilder
  func wordEditor(_ id: String, task: LorvexTask) -> some View {
    switch id {
    case "doOn":
      TaskDetailDayPicker(
        title: TaskDetailSentenceCopy.addWhen,
        hint: String(
          localized: "task_detail.metadata.planned_hint", defaultValue: "The day you plan to work on it.",
          table: "Localizable", bundle: LorvexL10n.bundle),
        presets: [.today, .tomorrow, .thisWeekend, .nextMonday],
        selection: store.taskDetailHasPlannedDate ? store.taskDetailPlannedDatePickerDate : nil,
        onSet: { date in
          store.setTaskDetailHasPlannedDate(true)
          store.taskDetailPlannedDatePickerDate = date
        },
        onClear: { store.setTaskDetailHasPlannedDate(false) },
        time: TaskDetailDayPicker.TimeField(
          value: store.taskDetailPlannedTime,
          defaultLength: LorvexNumberInput.integer(from: store.taskDetailEstimatedMinutesText),
          nowMinutes: store.nowMinutesInProductDay,
          isToday: lorvexDayOffset(
            from: store.logicalTodayDateString, to: store.taskDetailPlannedDatePickerDate) == 0,
          onChange: { store.taskDetailPlannedTime = $0 }))
    case "due":
      TaskDetailDayPicker(
        title: TaskDetailSentenceCopy.addDue,
        hint: String(
          localized: "task_detail.metadata.due_hint", defaultValue: "The deadline to finish by.",
          table: "Localizable", bundle: LorvexL10n.bundle),
        presets: [.today, .tomorrow, .thisWeekend, .nextMonday],
        selection: store.taskDetailHasDueDate ? store.taskDetailDueDatePickerDate : nil,
        onSet: { date in
          store.setTaskDetailHasDueDate(true)
          store.taskDetailDueDatePickerDate = date
        },
        onClear: { store.setTaskDetailHasDueDate(false) })
    case "hideUntil":
      TaskDetailDayPicker(
        title: TaskDetailSentenceCopy.addHideUntil,
        hint: String(
          localized: "task_detail.metadata.available_from_hint",
          defaultValue: "Hidden from your lists until this day.", table: "Localizable",
          bundle: LorvexL10n.bundle),
        presets: [.tomorrow, .nextMonday, .nextMonth],
        selection: store.taskDetailHasAvailableFrom ? store.taskDetailAvailableFromPickerDate : nil,
        onSet: { date in
          store.setTaskDetailHasAvailableFrom(true)
          store.taskDetailAvailableFromPickerDate = date
        },
        onClear: { store.setTaskDetailHasAvailableFrom(false) })
    case "estimate":
      TaskDetailLengthPicker(minutesText: $store.taskDetailEstimatedMinutesText)
    case "repeat": recurrenceContent
    case "reminders": remindersContent(task: task)
    case "dependencies": dependenciesContent(task: task)
    case "tags":
      TaskDetailTagsPicker(tagsText: taskTagsBinding(for: task), loadKnownTags: { await store.loadKnownTags() })
    default: EmptyView()
    }
  }

  /// The lists the task can move to, in the sidebar's order with the Inbox
  /// first, each with its icon; the task's list is checked. Choosing one moves
  /// the task at once.
  @ViewBuilder
  private func listMenuItems(task: LorvexTask) -> some View {
    let lists = store.orderedLists.filter { $0.archivedAt == nil }
    Picker(
      selection: Binding(
        get: { task.listID ?? "" },
        set: { id in Task { await store.moveSelectedTaskToList(id) } })
    ) {
      ForEach(lists.filter(\.isInbox) + lists.filter { !$0.isInbox }) { list in
        LorvexListMenuLabel(list: list).tag(list.id)
      }
    } label: {
      Text(TaskDetailSentenceCopy.addList)
    }
    .pickerStyle(.inline)
    .accessibilityIdentifier("task.detail.listControl")
  }

  /// The priority choices, the current one checked.
  @ViewBuilder
  private func priorityMenuItems(task: LorvexTask) -> some View {
    Picker(selection: taskPriorityBinding(for: task)) {
      ForEach(LorvexTask.Priority.allCases, id: \.self) { priority in
        Text(priority.localizedName).tag(priority)
      }
    } label: {
      Text(TaskDetailSentenceCopy.addPriority)
    }
    .pickerStyle(.inline)
    .accessibilityIdentifier("task.detail.priorityControl")
  }

  /// Never, the common repeats with the current one checked, and Custom…,
  /// which opens the full repeat editor on the row.
  @ViewBuilder
  private func repeatMenuItems(openEditor: @escaping () -> Void) -> some View {
    let current = store.taskDetailRecurrencePreset
    Button(String(localized: "recurrence.preset.never", defaultValue: "Never", table: "Localizable", bundle: LorvexL10n.bundle)) {
      Task { await store.applyTaskDetailRecurrencePreset(nil) }
    }
    Divider()
    ForEach(TaskDetailRecurrencePreset.allCases) { preset in
      Button {
        Task { await store.applyTaskDetailRecurrencePreset(preset) }
      } label: {
        if preset == current {
          Label(preset.title, systemImage: "checkmark")
        } else {
          Text(preset.title)
        }
      }
    }
    Divider()
    Button(String(localized: "recurrence.preset.custom", defaultValue: "Custom…", table: "Localizable", bundle: LorvexL10n.bundle)) {
      openEditor()
    }
  }
}
