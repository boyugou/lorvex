import Foundation
import LorvexCore

/// Holds runtime state for the lists domain: the loaded catalog, the selected
/// list and its detail snapshot, and the new-list name/description drafts.
struct AppStoreListsStorage {
  var lists: ListCatalogSnapshot?
  /// Lists retired via archive: hidden from the main Lists section but kept,
  /// with all their tasks, so completed history stays under the list's name.
  var archivedLists: ListCatalogSnapshot?
  var selectedListID: LorvexList.ID?
  var selectedListDetail: ListDetailSnapshot?
  var selectedListTaskIDs = Set<LorvexTask.ID>()
  var draftListName = ""
  var draftListDescription = ""
  /// SF Symbol name (or emoji glyph); nil uses the default folder glyph.
  var draftListIcon: String?
  /// `#RRGGBB` hex; nil uses the app accent.
  var draftListColor: String?

  mutating func reset() {
    lists = nil
    archivedLists = nil
    selectedListID = nil
    selectedListDetail = nil
    selectedListTaskIDs.removeAll()
    draftListName = ""
    draftListDescription = ""
    draftListIcon = nil
    draftListColor = nil
  }
}
