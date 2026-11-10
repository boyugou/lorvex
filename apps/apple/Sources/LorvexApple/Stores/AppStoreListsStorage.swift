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
  /// True while the next page of the selected list's tasks is in flight.
  var isLoadingMoreSelectedListTasks = false
  var selectedListTaskIDs = Set<LorvexTask.ID>()
  var draftListName = ""
  var draftListDescription = ""
  /// SF Symbol name (or emoji glyph); nil uses the default folder glyph.
  var draftListIcon: String?
  /// `#RRGGBB` hex; nil uses the app accent.
  var draftListColor: String?
  /// The draft as ``AppStore/prepareListDraft(for:)`` filled it from the list
  /// being edited; nil while the draft holds a new list. Saving an edit writes
  /// only the fields that differ from it, so a field another writer changed
  /// while the sheet was open keeps that change. With no baseline every field
  /// is written.
  var draftListBaseline: ListDraftBaseline?

  /// The edited list's stored name and its draft fields as the edit sheet
  /// opened with them, text trimmed.
  struct ListDraftBaseline: Equatable {
    var storedName: String
    var name: String
    var description: String
    var icon: String?
    var color: String?
  }

  mutating func reset() {
    lists = nil
    archivedLists = nil
    selectedListID = nil
    selectedListDetail = nil
    isLoadingMoreSelectedListTasks = false
    selectedListTaskIDs.removeAll()
    draftListName = ""
    draftListDescription = ""
    draftListIcon = nil
    draftListColor = nil
    draftListBaseline = nil
  }
}
