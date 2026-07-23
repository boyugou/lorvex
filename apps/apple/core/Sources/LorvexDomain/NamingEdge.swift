/// Edge type vocabulary — composite-key relationship rows that flow through the
/// sync envelope alongside aggregate roots and independent children. This lists
/// edge tables only; parent-owned collection tables (which ride embedded inside
/// their parent payload) are excluded from ``EntityKind/allSyncableTypes``.
public enum EdgeName {
  public static let taskTag = "task_tag"
  public static let taskDependency = "task_dependency"
  public static let taskCalendarEventLink = "task_calendar_event_link"
  public static let habitCompletion = "habit_completion"

  /// All edge type names in declaration order. Parent-owned collection tables
  /// are excluded — they are not independent sync entities.
  public static let allEdgeTypes: [String] = [
    taskTag,
    taskDependency,
    taskCalendarEventLink,
    habitCompletion,
  ]
}
