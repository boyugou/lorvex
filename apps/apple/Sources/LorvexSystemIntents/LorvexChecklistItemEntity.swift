import AppIntents
import LorvexCore

/// One checklist item of a Lorvex task, as Siri and Shortcuts pick it: the
/// item's text, with the task it belongs to underneath.
///
/// The identifier joins the task's ID and the item's ID (see
/// ``identifier(taskID:itemID:)``), so a saved shortcut finds its item again by
/// reading that one task rather than every task with a checklist.
struct LorvexChecklistItemEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.checklist_item.type", defaultValue: "Lorvex Checklist Item", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexChecklistItemEntityQuery()

  var id: String
  var taskID: LorvexTask.ID
  var itemID: TaskChecklistItem.ID
  var text: String
  var taskTitle: String
  var completed: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(text)",
      subtitle: "\(taskTitle)",
      image: .init(systemName: completed ? "checkmark.circle.fill" : "circle")
    )
  }

  init(taskID: LorvexTask.ID, itemID: TaskChecklistItem.ID, text: String, taskTitle: String, completed: Bool) {
    self.id = Self.identifier(taskID: taskID, itemID: itemID)
    self.taskID = taskID
    self.itemID = itemID
    self.text = text
    self.taskTitle = taskTitle
    self.completed = completed
  }

  init(item: TaskChecklistItem, task: LorvexTask) {
    self.init(
      taskID: task.id,
      itemID: item.id,
      text: item.text,
      taskTitle: task.title,
      completed: item.completedAt != nil
    )
  }

  /// `taskID/itemID`. Lorvex IDs are hyphenated UUIDs, so the slash never
  /// occurs inside either half.
  static func identifier(taskID: LorvexTask.ID, itemID: TaskChecklistItem.ID) -> String {
    "\(taskID)/\(itemID)"
  }

  /// The task and item IDs an identifier joins, or nil for text that is not
  /// one.
  static func components(of identifier: String) -> (taskID: LorvexTask.ID, itemID: TaskChecklistItem.ID)? {
    let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (String(parts[0]), String(parts[1]))
  }
}
