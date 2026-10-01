import LorvexCore

extension AppStore {
  var lists: ListCatalogSnapshot? {
    get { listsStorage.lists }
    set { listsStorage.lists = newValue }
  }

  var archivedLists: ListCatalogSnapshot? {
    get { listsStorage.archivedLists }
    set { listsStorage.archivedLists = newValue }
  }

  /// Archived lists in name order, for the sidebar's Archived section. Empty
  /// when nothing is archived, so the section can hide itself.
  var orderedArchivedLists: [LorvexList] {
    archivedLists?.lists ?? []
  }

  var selectedListID: LorvexList.ID? {
    get { listsStorage.selectedListID }
    set { listsStorage.selectedListID = newValue }
  }

  var selectedListDetail: ListDetailSnapshot? {
    get { listsStorage.selectedListDetail }
    set { listsStorage.selectedListDetail = newValue }
  }

  /// The selected list's loaded tasks, in the order the core returned them.
  var selectedListTasks: [LorvexTask] {
    selectedListDetail?.tasks ?? []
  }

  /// Every list in synced `position` order: the sidebar's Lists section, the
  /// Lists catalog, and the list-reorder drag all read this one collection, so
  /// the displayed order and the drag math agree. The core returns lists
  /// already ordered by `position`.
  var orderedLists: [LorvexList] {
    lists?.lists ?? []
  }

  var isLoadingMoreSelectedListTasks: Bool {
    get { listsStorage.isLoadingMoreSelectedListTasks }
    set { listsStorage.isLoadingMoreSelectedListTasks = newValue }
  }

  var selectedListTaskIDs: Set<LorvexTask.ID> {
    get { listsStorage.selectedListTaskIDs }
    set { listsStorage.selectedListTaskIDs = newValue }
  }

  var draftListName: String {
    get { listsStorage.draftListName }
    set { listsStorage.draftListName = newValue }
  }

  var draftListDescription: String {
    get { listsStorage.draftListDescription }
    set { listsStorage.draftListDescription = newValue }
  }

  var draftListIcon: String? {
    get { listsStorage.draftListIcon }
    set { listsStorage.draftListIcon = newValue }
  }

  var draftListColor: String? {
    get { listsStorage.draftListColor }
    set { listsStorage.draftListColor = newValue }
  }
}
