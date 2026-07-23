import GRDB

/// Restores focus references from a cancelled recurrence successor to the
/// reopened parent. Leaving them on the successor would make the task vanish
/// from focus surfaces even though the user's focus intent still exists.
enum LifecycleSuccessorFocusRewind {
  struct Result: Sendable, Equatable {
    let focusScheduleDates: [String]
    let currentFocusDates: [String]
  }

  static func rewire(
    _ db: Database,
    successorId: String,
    parentId: String
  ) throws -> Result {
    let focusScheduleDates = try String.fetchAll(
      db,
      sql:
        "SELECT DISTINCT date FROM focus_schedule_blocks "
        + "WHERE task_id = ?1 ORDER BY date ASC",
      arguments: [successorId])
    let currentFocusDates = try String.fetchAll(
      db,
      sql:
        "SELECT DISTINCT date FROM current_focus_items "
        + "WHERE task_id = ?1 ORDER BY date ASC",
      arguments: [successorId])

    // A focus schedule may intentionally contain multiple blocks for one task,
    // so replacing the task identity is lossless.
    try db.execute(
      sql:
        "UPDATE focus_schedule_blocks SET task_id = ?1 "
        + "WHERE task_id = ?2",
      arguments: [parentId, successorId])

    // Current focus admits each task only once per day. If the parent was
    // independently added after the successor was spawned, keep that existing
    // placement and remove only the now-cancelled successor entry; otherwise
    // replace in place so its position stays stable.
    try db.execute(
      sql:
        "DELETE FROM current_focus_items AS successor "
        + "WHERE successor.task_id = ?1 AND EXISTS ("
        + "SELECT 1 FROM current_focus_items AS parent "
        + "WHERE parent.date = successor.date AND parent.task_id = ?2)",
      arguments: [successorId, parentId])
    try db.execute(
      sql:
        "UPDATE current_focus_items SET task_id = ?1 "
        + "WHERE task_id = ?2",
      arguments: [parentId, successorId])

    return Result(
      focusScheduleDates: focusScheduleDates,
      currentFocusDates: currentFocusDates)
  }
}
