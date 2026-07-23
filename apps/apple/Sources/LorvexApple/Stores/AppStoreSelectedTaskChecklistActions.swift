import Foundation
import LorvexCore
import SwiftUI

extension AppStore {
  func addChecklistItemToSelectedTask() async {
    guard let taskID = selectedTask?.id else { return }
    let text = taskDetailNewChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    // Clear the field synchronously, before the await, so a fast second Return
    // sees no text and no-ops instead of adding a duplicate item.
    taskDetailNewChecklistText = ""
    do {
      let task = try await core.addTaskChecklistItem(taskID: taskID, text: text)
      replaceTask(task)
      syncSelectedTaskChecklistDrafts()
      errorMessage = nil
    } catch {
      // Restore the unsaved text so the user can retry.
      taskDetailNewChecklistText = text
      await presentUserFacingError(error)
    }
  }

  func toggleChecklistItem(_ item: TaskChecklistItem) async {
    await perform {
      let task = try await core.toggleTaskChecklistItem(
        itemID: item.id,
        completed: item.completedAt == nil
      )
      replaceTask(task)
      syncSelectedTaskChecklistDrafts()
    }
  }

  func checklistDraftBinding(for item: TaskChecklistItem) -> Binding<String> {
    Binding(
      get: { self.taskDetailChecklistDrafts[item.id] ?? item.text },
      set: { self.taskDetailChecklistDrafts[item.id] = $0 }
    )
  }

  func updateChecklistItem(_ item: TaskChecklistItem) async {
    let text = (taskDetailChecklistDrafts[item.id] ?? item.text)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // A checklist item must have text; emptying it then blurring/Return is not a
    // save. Snap the draft back to the saved value so the row shows its real
    // text instead of stranding a blank (delete is the right-click action).
    if text.isEmpty {
      taskDetailChecklistDrafts[item.id] = item.text
      return
    }
    guard text != item.text else { return }
    await perform {
      let task = try await core.updateTaskChecklistItem(itemID: item.id, text: text)
      replaceTask(task)
      syncSelectedTaskChecklistDrafts()
    }
  }

  func moveChecklistItem(_ item: TaskChecklistItem, direction: Int) async {
    guard let task = selectedTask,
      let currentIndex = task.checklistItems.firstIndex(where: { $0.id == item.id })
    else { return }
    let targetIndex = currentIndex + direction
    guard task.checklistItems.indices.contains(targetIndex) else { return }
    var itemIDs = task.checklistItems.map(\.id)
    itemIDs.swapAt(currentIndex, targetIndex)
    await perform {
      let updated = try await core.reorderTaskChecklistItems(taskID: task.id, itemIDs: itemIDs)
      replaceTask(updated)
      syncSelectedTaskChecklistDrafts()
    }
  }

  /// Drag-reorder: move the checklist item identified by `draggedID` to the
  /// slot currently held by `targetID`. Items dragged downward land after the
  /// target, items dragged upward land before it (the `remove` then `insert at
  /// target index` arithmetic yields both). No-ops if either id is unknown or
  /// the positions match.
  func reorderChecklistItem(
    _ draggedID: TaskChecklistItem.ID,
    toPositionOf targetID: TaskChecklistItem.ID
  ) async {
    guard let task = selectedTask else { return }
    var itemIDs = task.checklistItems.map(\.id)
    guard let from = itemIDs.firstIndex(of: draggedID),
      let to = itemIDs.firstIndex(of: targetID),
      from != to
    else { return }
    let moved = itemIDs.remove(at: from)
    itemIDs.insert(moved, at: to)
    await perform {
      let updated = try await core.reorderTaskChecklistItems(taskID: task.id, itemIDs: itemIDs)
      replaceTask(updated)
      syncSelectedTaskChecklistDrafts()
    }
  }

  func removeChecklistItem(_ item: TaskChecklistItem) async {
    await perform {
      let task = try await core.removeTaskChecklistItem(itemID: item.id)
      replaceTask(task)
      syncSelectedTaskChecklistDrafts()
    }
  }
}
