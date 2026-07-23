import LorvexCore
import SwiftUI

enum TaskCommand: CaseIterable {
  case showDetail
  case save
  case toggleFocus
  case deferToTomorrow
  case complete
  case reopen
  case cancel

  var title: String {
    switch self {
    case .showDetail: String(localized: "task_command.show_detail", defaultValue: "Show Task Detail", table: "Localizable", bundle: LorvexL10n.bundle)
    case .save: String(localized: "task_command.save", defaultValue: "Save Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .toggleFocus: String(localized: "task_command.add_focus", defaultValue: "Add to Focus", table: "Localizable", bundle: LorvexL10n.bundle)
    case .deferToTomorrow: String(localized: "task_command.defer_to_tomorrow", defaultValue: "Defer to Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
    case .complete: String(localized: "task_command.complete", defaultValue: "Complete Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reopen: String(localized: "task_command.reopen", defaultValue: "Reopen Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cancel: String(localized: "task_command.cancel", defaultValue: "Cancel Task", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  func title(isFocused: Bool) -> String {
    switch self {
    case .toggleFocus:
      isFocused
        ? String(localized: "task_command.remove_focus", defaultValue: "Remove from Focus", table: "Localizable", bundle: LorvexL10n.bundle)
        : String(localized: "task_command.add_focus", defaultValue: "Add to Focus", table: "Localizable", bundle: LorvexL10n.bundle)
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
    case .toggleFocus:
      // ⌥⌘F, not ⌘F: plain ⌘F is the system Find accelerator that `.searchable`
      // binds to focus the toolbar search field.
      KeyboardShortcut("f", modifiers: [.command, .option])
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
    case .showDetail, .toggleFocus:
      return tasks.count == 1
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
    case .toggleFocus: .toggleSelectedTaskFocus
    case .deferToTomorrow: .deferSelectedTask
    case .complete: .completeSelectedTask
    case .reopen: .reopenSelectedTask
    case .cancel: .cancelSelectedTask
    }
  }

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
        openTaskDetail: openTaskDetail
      )
  }
}
