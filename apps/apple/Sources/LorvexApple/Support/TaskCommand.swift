import LorvexCore
import SwiftUI

enum TaskCommand: CaseIterable {
  case showDetail
  case save
  case toggleStarted
  case deferToTomorrow
  case complete
  case reopen
  case cancel

  var title: String {
    switch self {
    case .showDetail: String(localized: "task_command.show_detail", defaultValue: "Show Task Detail", table: "Localizable", bundle: LorvexL10n.bundle)
    case .save: String(localized: "task_command.save", defaultValue: "Save Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .toggleStarted: String(localized: "task_command.start", defaultValue: "Start Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .deferToTomorrow: String(localized: "task_command.defer_to_tomorrow", defaultValue: "Defer to Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
    case .complete: String(localized: "task_command.complete", defaultValue: "Complete Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reopen: String(localized: "task_command.reopen", defaultValue: "Reopen Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cancel: String(localized: "task_command.cancel", defaultValue: "Cancel Task", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The menu title for the current selection: Start/Pause reads "Pause Task"
  /// when the one selected task is already started.
  func title(isStarted: Bool) -> String {
    switch self {
    case .toggleStarted where isStarted:
      String(localized: "task_command.pause", defaultValue: "Pause Task", table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      title
    }
  }

  var keyboardShortcut: KeyboardShortcut {
    switch self {
    case .showDetail:
      KeyboardShortcut("i", modifiers: [.command, .shift])
    case .save:
      KeyboardShortcut("s", modifiers: [.command])
    case .toggleStarted:
      // ⇧⌘S joins the other ⇧⌘ task verbs; Lorvex has no document to
      // "Save As", so the shortcut is free.
      KeyboardShortcut("s", modifiers: [.command, .shift])
    case .deferToTomorrow:
      KeyboardShortcut("d", modifiers: [.command, .shift])
    case .complete:
      KeyboardShortcut(.return, modifiers: [.command, .shift])
    case .reopen:
      KeyboardShortcut("o", modifiers: [.command, .shift])
    case .cancel:
      KeyboardShortcut(.delete, modifiers: [.command])
    }
  }

  @MainActor
  func isEnabled(in context: LorvexTaskCommandContext?) -> Bool {
    guard let context else { return false }
    let tasks = context.selectedTasks
    switch self {
    case .showDetail:
      return tasks.count == 1
    case .toggleStarted:
      guard tasks.count == 1 else { return false }
      let task = tasks[0]
      return task.status == .inProgress
        || (task.status == .open && !context.store.startIsHeldUp(for: task))
    case .deferToTomorrow:
      return tasks.contains { $0.status.isActive }
    case .save:
      guard let task = context.singleTask else { return false }
      return context.store.selectedTaskID == task.id && context.store.selectedTaskCanSave
    case .complete:
      return tasks.contains { $0.status.isActive }
    case .reopen:
      return tasks.contains { $0.status.isResolved }
    case .cancel:
      return tasks.contains { $0.status.isActive }
    }
  }

  var action: TaskCommandAction {
    switch self {
    case .showDetail: .openTaskDetail
    case .save: .saveSelectedTaskDraft
    case .toggleStarted: .toggleSelectedTaskStarted
    case .deferToTomorrow: .deferSelectedTask
    case .complete: .completeSelectedTask
    case .reopen: .reopenSelectedTask
    case .cancel: .cancelSelectedTask
    }
  }

  /// Runs the command on the context's selection. A completion or non-recurring
  /// cancel registers its ⌘Z with the key window's undo manager, the one the
  /// Edit menu's Undo item acts on.
  @MainActor
  func perform(
    in context: LorvexTaskCommandContext,
    openTaskDetail: @escaping (LorvexTask.ID) -> Void
  ) {
    LorvexCommandDispatcher(store: context.store) { _ in }
      .perform(
        action,
        selectionSurface: context.selectionSurface,
        fallbackTaskID: context.fallbackTaskID,
        openTaskDetail: openTaskDetail,
        undoManager: NSApp?.keyWindow?.undoManager
      )
  }
}
