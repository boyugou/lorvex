import Foundation
import LorvexStore

/// Maps the core's `lists`-table rows onto the app's stable `LorvexList` model
/// type, preserving the stable field shape (`open_count` / `total_count` /
/// `updated_at`).
enum SwiftLorvexListDeserializers {

  /// Map a `ListWithCounts` (a `lists` row plus open/total task counts) onto a
  /// `LorvexList`. `updatedAt` renders the canonical millisecond-`Z` string.
  static func list(_ row: ListWithCounts) -> LorvexList {
    LorvexList(
      id: row.list.id,
      name: row.list.name,
      color: row.list.color,
      icon: row.list.icon,
      description: row.list.description,
      aiNotes: row.list.aiNotes,
      openCount: Int(row.openCount),
      completedCount: Int(row.completedCount),
      cancelledCount: Int(row.cancelledCount),
      totalCount: Int(row.totalCount),
      updatedAt: row.list.updatedAt.asString,
      archivedAt: row.list.archivedAt,
      position: row.list.position)
  }

  /// Map a bare `ListRow` (no counts available — e.g. the row returned by a
  /// create/update) onto a `LorvexList` with the supplied counts, defaulting to
  /// zero. A freshly created list has no tasks, so all-zero is correct there.
  static func list(
    _ row: ListRow,
    openCount: Int = 0,
    completedCount: Int = 0,
    cancelledCount: Int = 0,
    totalCount: Int = 0
  ) -> LorvexList {
    LorvexList(
      id: row.id,
      name: row.name,
      color: row.color,
      icon: row.icon,
      description: row.description,
      aiNotes: row.aiNotes,
      openCount: openCount,
      completedCount: completedCount,
      cancelledCount: cancelledCount,
      totalCount: totalCount,
      updatedAt: row.updatedAt.asString,
      archivedAt: row.archivedAt,
      position: row.position)
  }
}
