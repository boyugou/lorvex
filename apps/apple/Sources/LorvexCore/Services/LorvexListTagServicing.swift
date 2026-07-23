import Foundation

public protocol LorvexListTagServicing: Sendable {
  func loadLists() async throws -> ListCatalogSnapshot

  /// The archived lists (set-aside lists kept with their task history); disjoint
  /// from ``loadLists()``, which returns only active lists.
  func loadArchivedLists() async throws -> ListCatalogSnapshot

  func loadListDetail(id: LorvexList.ID, limit: Int, offset: Int) async throws -> ListDetailSnapshot

  func createList(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?
  ) async throws -> LorvexList

  /// Id-preserving idempotent upsert for data import/restore. Inserts the list
  /// at the supplied `id`, or overwrites the existing row's columns when that id
  /// is already present. No version gate: an import always wins, so re-importing
  /// the same payload overwrites in place rather than duplicating.
  func importList(
    id: LorvexList.ID,
    name: String,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?,
    archivedAt: String?,
    position: Int64?
  ) async throws -> LorvexList

  func moveTask(id: LorvexTask.ID, toListID listID: LorvexList.ID) async throws -> LorvexTask

  func updateList(
    id: LorvexList.ID,
    name: String?,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> LorvexList

  /// Replace the list's assistant-maintained context block. Passing an empty
  /// string clears the block.
  func setListAINotes(id: LorvexList.ID, notes: String) async throws -> LorvexList

  func deleteList(id: LorvexList.ID) async throws

  /// Archive a whole list: keep it and all its tasks (completed history under
  /// the list name) but hide it from the active catalog. Returns the list.
  func archiveList(id: LorvexList.ID) async throws -> LorvexList

  /// Restore an archived list to the active catalog.
  func unarchiveList(id: LorvexList.ID) async throws -> LorvexList

  func getList(id: LorvexList.ID) async throws -> LorvexList

  func getListHealthSnapshot() async throws -> ListHealthSnapshot

  /// Persist the manual display order of the active lists catalog. `orderedIDs`
  /// is the full desired order of active list ids; each listed list's synced
  /// `position` is rewritten to its index, so a reorder on one device converges
  /// across peers as an ordinary last-writer-wins field. Ids absent from
  /// `orderedIDs` are left untouched. Returns the refreshed active catalog.
  func reorderLists(orderedIDs: [LorvexList.ID]) async throws -> ListCatalogSnapshot

  func listAllTags() async throws -> [String]

  func renameTag(oldTag: String, newTag: String) async throws

  /// Permanently delete a tag, removing it from every task (deleting its
  /// `task_tags` links) and deleting the tag row. Throws when no tag matches
  /// `name`. Returns the deleted tag and the tasks it was unlinked from.
  func deleteTag(name: String) async throws -> TagDeletionOutcome

  /// Merge the `source` tag into `target`: re-point every task from `source`
  /// onto `target` (de-duplicating tasks that already carry `target`), then
  /// delete `source`. Both tags must already exist and differ; renaming a tag
  /// to a brand-new name is ``renameTag(oldTag:newTag:)``. Returns the surviving
  /// tag and how many tasks were moved versus de-duplicated.
  func mergeTags(source: String, target: String) async throws -> TagMergeOutcome

  func countTasksByTag(tag: String) async throws -> Int

  func getTasksByTag(tag: String) async throws -> [LorvexTask]
}

extension LorvexListTagServicing {
  /// Convenience for callers that don't set appearance: creates with the
  /// default folder glyph and accent color.
  public func createList(name: String, description: String?) async throws -> LorvexList {
    try await createList(name: name, description: description, color: nil, icon: nil, aiNotes: nil)
  }

  /// Convenience for callers that set appearance but no AI notes (the common
  /// human-facing path). `ai_notes` is AI-only, written only through MCP.
  public func createList(
    name: String, description: String?, color: String?, icon: String?
  ) async throws -> LorvexList {
    try await createList(
      name: name, description: description, color: color, icon: icon, aiNotes: nil)
  }

  /// Convenience for callers that don't touch AI notes.
  public func updateList(
    id: LorvexList.ID, name: String?, description: String?, color: String?, icon: String?
  ) async throws -> LorvexList {
    try await updateList(
      id: id, name: name, description: description, color: color, icon: icon, aiNotes: nil)
  }

  /// Convenience for import callers that don't carry AI notes.
  public func importList(
    id: LorvexList.ID, name: String, description: String?, color: String?, icon: String?
  ) async throws -> LorvexList {
    try await importList(
      id: id, name: name, description: description, color: color, icon: icon, aiNotes: nil,
      archivedAt: nil, position: nil)
  }

  /// Convenience for import callers that carry AI notes but no archive/order metadata.
  public func importList(
    id: LorvexList.ID,
    name: String,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> LorvexList {
    try await importList(
      id: id, name: name, description: description, color: color, icon: icon, aiNotes: aiNotes,
      archivedAt: nil, position: nil)
  }
}
