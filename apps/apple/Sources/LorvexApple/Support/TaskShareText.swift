import AppKit
import LorvexCore

extension AppStore {
  /// The plain text a task is copied or shared as: the layout of
  /// ``LorvexTaskShareText`` worded from this app's catalog, with the list's
  /// name taken from the sidebar's lists.
  func shareText(for task: LorvexTask) -> String {
    LorvexTaskShareText.text(
      for: task,
      listName: task.listID.flatMap { id in orderedLists.first { $0.id == id }?.displayName },
      logicalDay: logicalTodayDateString,
      labels: LorvexTaskShareLabels(
        field: Self.shareFieldLabel,
        line: { label, value in
          String(
            localized: "share.field", defaultValue: "\(label): \(value)", table: "Localizable",
            bundle: LorvexL10n.bundle)
        },
        dayAtTime: { day, range in
          let time = lorvexClockRangeLabel(startMinutes: range.lowerBound, endMinutes: range.upperBound)
          return String(
            localized: "task_detail.do_on.day_time", defaultValue: "\(day), \(time)", table: "Localizable",
            bundle: LorvexL10n.bundle)
        },
        assistantContext: String(
          localized: "task_detail.ai_notes.context_label", defaultValue: "Assistant Context",
          table: "Localizable", bundle: LorvexL10n.bundle),
        checklist: String(
          localized: "task_detail.checklist.title", defaultValue: "Checklist", table: "Localizable",
          bundle: LorvexL10n.bundle)))
  }

  /// The text of several tasks, each as ``shareText(for:)`` gives it, one after
  /// another with a rule between them.
  func shareText(for tasks: [LorvexTask]) -> String {
    tasks.map { shareText(for: $0) }.joined(separator: "\n\n---\n\n")
  }

  /// Puts ``shareText(for:)`` of the task on the general pasteboard as plain text.
  func copyShareText(of task: LorvexTask) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(shareText(for: task), forType: .string)
  }

  /// The name the inspector gives a field. Nonisolated, since the labels a
  /// share text is built from are `Sendable`.
  private nonisolated static func shareFieldLabel(_ field: LorvexTaskShareField) -> String {
    switch field {
    case .doOn:
      String(localized: "task_detail.add.when", defaultValue: "When", table: "Localizable", bundle: LorvexL10n.bundle)
    case .estimate:
      String(localized: "task_detail.add.length", defaultValue: "How long", table: "Localizable", bundle: LorvexL10n.bundle)
    case .due:
      String(localized: "task_detail.add.due", defaultValue: "Due", table: "Localizable", bundle: LorvexL10n.bundle)
    case .list:
      String(localized: "task_detail.add.list", defaultValue: "List", table: "Localizable", bundle: LorvexL10n.bundle)
    case .priority:
      String(localized: "task_detail.add.priority", defaultValue: "Priority", table: "Localizable", bundle: LorvexL10n.bundle)
    case .recurrence:
      String(localized: "task_detail.add.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tags:
      String(localized: "task_detail.add.tag", defaultValue: "Tags", table: "Localizable", bundle: LorvexL10n.bundle)
    case .hideUntil:
      String(localized: "task_detail.add.hide_until", defaultValue: "Hide until", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
