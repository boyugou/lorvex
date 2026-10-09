import LorvexCore
import SwiftUI

/// The sidebar's Lists section: the lists, then a quiet "New List" row that
/// opens the create sheet (the Reminders pattern: creation sits where the
/// lists end, not as a glyph on the header), per-row Edit / reorder / Delete context menus, drag-to-reorder via
/// `.onMove`, and drag-tasks-onto-a-list drop targets (``TaskDropTarget``). This is the
/// Reminders/Notes pattern — lists are managed inline where they live. It is the
/// scoped list picker in the Tasks workspace sidebar: each row selects a list to
/// scope the task view.
extension SidebarView {
    @ViewBuilder
    var listScopeSection: some View {
        Section {
            ForEach(store.orderedLists) { list in
                SidebarListRow(
                    count: list.openCount > 0 ? list.openCount : nil,
                    spokenLabel: list.spokenSummary
                ) {
                    SidebarListIcon(
                        icon: list.icon,
                        tint: Color(lorvexHex: list.color) ?? .accentColor
                    )
                } title: {
                    Text(list.displayName)
                }
                .listRowInsets(SidebarMetrics.rowInsets)
                .tag(SidebarRowSelection.listScope(list.id))
                .accessibilityIdentifier("sidebar.list.\(list.id)")
                .contextMenu {
                    Button {
                        store.prepareListDraft(for: list)
                        editingList = list
                    } label: {
                        Label(String(localized: "list_row.edit.action", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "pencil")
                    }
                    Button {
                        openWindow(value: list.id)
                    } label: {
                        Label(String(localized: "list_row.open_new_window", defaultValue: "Open in New Window", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "macwindow.on.rectangle")
                    }
                    Divider()
                    let listIndex = store.orderedLists.firstIndex { $0.id == list.id }
                    Button {
                        moveList(list, by: -1)
                    } label: {
                        Label(String(localized: "list_row.move_up", defaultValue: "Move Up", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "arrow.up")
                    }
                    .disabled(listIndex == nil || listIndex == 0)
                    Button {
                        moveList(list, by: 1)
                    } label: {
                        Label(String(localized: "list_row.move_down", defaultValue: "Move Down", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "arrow.down")
                    }
                    .disabled(listIndex == nil || listIndex == store.orderedLists.count - 1)
                    // The Inbox is the list every task falls back to: it can be
                    // edited and moved, never archived or deleted.
                    if !list.isInbox {
                        Divider()
                        Button {
                            Task { await store.archiveList(list) }
                        } label: {
                            Label(String(localized: "list_row.archive.action", defaultValue: "Archive List", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            listPendingDeletion = list
                        } label: {
                            Label(String(localized: "list_row.delete.action", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash")
                        }
                    }
                }
                .taskDropTarget(
                    SidebarRowSelection.listScope(list.id), targeted: $dropTargetedRow,
                    outset: SidebarMetrics.capsuleOutset, cornerRadius: LorvexDesign.Radius.m
                ) { ids in
                    Task { await store.moveTasks(ids: ids, toListID: list.id, undoManager: undoManager) }
                }
            }
            .onMove { source, destination in
                moveLists(fromOffsets: source, toOffset: destination)
            }
            newListRow
        } header: {
            SidebarSectionHeader(title: LocalizedStringResource("sidebar.section.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle))
        }
    }

    /// The last row of the Lists section: a plus in the icon column and
    /// "New List" in the secondary style, so it reads as an action beside the
    /// lists rather than as one of them. It carries no selection tag, so
    /// clicking it opens the create sheet without moving the selection.
    private var newListRow: some View {
        Button {
            isShowingCreateList = true
        } label: {
            SidebarListRow {
                Image(systemName: "plus")
                    .font(SidebarTypography.title.weight(.medium))
            } title: {
                Text(LocalizedStringResource("sidebar.lists.new", defaultValue: "New List", table: "Localizable", bundle: LorvexL10n.bundle))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(SidebarMetrics.rowInsets)
        .moveDisabled(true)
        .help(String(localized: "lists.create.help", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("sidebar.lists.create")
    }

    /// The sidebar's Archived section: lists retired via archive. Hidden when
    /// nothing is archived. Rows stay selectable so the list's preserved tasks
    /// (mostly completed history) remain viewable, and each carries Unarchive /
    /// Open / Delete actions. Delete still hard-blocks while tasks are assigned,
    /// matching the active section.
    @ViewBuilder
    var archivedListScopeSection: some View {
        if !store.orderedArchivedLists.isEmpty {
            Section {
                ForEach(store.orderedArchivedLists) { list in
                    SidebarListRow {
                        SidebarListIcon(icon: list.icon, tint: .secondary)
                    } title: {
                        Text(list.displayName)
                    }
                    .listRowInsets(SidebarMetrics.rowInsets)
                    .tag(SidebarRowSelection.listScope(list.id))
                    .accessibilityIdentifier("sidebar.archivedList.\(list.id)")
                    .contextMenu {
                        Button {
                            Task { await store.unarchiveList(list) }
                        } label: {
                            Label(String(localized: "list_row.unarchive.action", defaultValue: "Unarchive List", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "tray.and.arrow.up")
                        }
                        Button {
                            openWindow(value: list.id)
                        } label: {
                            Label(String(localized: "list_row.open_new_window", defaultValue: "Open in New Window", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "macwindow.on.rectangle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            listPendingDeletion = list
                        } label: {
                            Label(String(localized: "list_row.delete.action", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash")
                        }
                    }
                }
            } header: {
                SidebarSectionHeader(title: LocalizedStringResource("sidebar.section.archived_lists", defaultValue: "Archived", table: "Localizable", bundle: LorvexL10n.bundle))
            }
        }
    }

    /// Wraps the source list in the list delete / archive confirmation dialog.
    /// The dialog rides the whole `List` rather than a single `Section`, so it
    /// presents reliably regardless of which list row triggered
    /// `listPendingDeletion`.
    func withListDeletionDialog<Content: View>(_ content: Content) -> some View {
        content.confirmationDialog(
            listPendingDeletion.map(deleteListDialogTitle) ?? "",
            isPresented: Binding(
                get: { listPendingDeletion != nil },
                set: { if !$0 { listPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: listPendingDeletion
        ) { list in
            // An empty list can be deleted outright. A non-empty active list
            // can't — delete hard-blocks while any task is assigned — so the
            // forward action is to archive it, keeping the tasks. A non-empty
            // archived list is already retired, so re-archiving is meaningless;
            // offer to unarchive it (restoring the list and its tasks) instead.
            if list.totalCount == 0 {
                Button(String(localized: "list_row.delete.confirm", defaultValue: "Delete List", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive) {
                    Task { await store.deleteList(list) }
                }
                Button(String(localized: "list_row.delete.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
            } else if list.isArchived {
                Button(String(localized: "list_row.unarchive.action", defaultValue: "Unarchive List", table: "Localizable", bundle: LorvexL10n.bundle)) {
                    Task { await store.unarchiveList(list) }
                }
                Button(String(localized: "list_row.delete.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
            } else {
                Button(String(localized: "list_row.archive.confirm", defaultValue: "Archive List", table: "Localizable", bundle: LorvexL10n.bundle)) {
                    Task { await store.archiveList(list) }
                }
                Button(String(localized: "list_row.delete.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
            }
        } message: { list in
            Text(deleteListDialogMessage(for: list))
        }
    }

    func deleteListDialogTitle(_ list: LorvexList) -> String {
        // The archived branch only ever offers Unarchive, never re-archive, so
        // its title stays a plain delete prompt (the message explains why delete
        // is blocked). Only the active non-empty branch leads with archiving.
        if list.totalCount == 0 || list.isArchived {
            return String(
                format: String(localized: "list_row.delete.title", defaultValue: "Delete list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
                list.displayName
            )
        }
        return String(
            format: String(localized: "list_row.archive.title", defaultValue: "Archive list “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
            list.displayName
        )
    }

    func deleteListDialogMessage(for list: LorvexList) -> String {
        if list.totalCount == 0 {
            return String(
                localized: "list_row.delete.empty_message",
                defaultValue: "The list is empty and will be removed.",
                table: "Localizable",
                bundle: LorvexL10n.bundle
            )
        }
        if list.isArchived {
            // Already archived, so re-archiving isn't an option; delete still
            // hard-blocks while tasks remain. Unarchiving brings the list and
            // its tasks back so they can be cleared before a later delete.
            return String(
                localized: "list_row.delete.archived_nonempty_message",
                defaultValue: "This list can’t be deleted while it still holds tasks. Unarchive it to restore the list and its tasks, then move or clear them before deleting it.",
                table: "Localizable",
                bundle: LorvexL10n.bundle
            )
        }
        // Delete is blocked while tasks remain; archiving retires the list while
        // keeping every task — including its completed and cancelled history —
        // under the list's name, and it can be restored later.
        return String(
            localized: "list_row.archive.nonempty_count_message",
            defaultValue: "“\(list.displayName)” can’t be deleted while it still holds \(list.totalCount) tasks. Archive it instead to retire it while keeping its tasks and history. You can unarchive it later.",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
    }

    /// Reorders a sidebar list by swapping it with its neighbour, backing the
    /// context-menu Move Up / Move Down actions. The sidebar shows every list, so
    /// the visible order is the full order — a direct swap of the id sequence is
    /// sufficient. The new order persists (and syncs) via the core's `position`
    /// column.
    private func moveList(_ list: LorvexList, by delta: Int) {
        var ids = store.orderedLists.map(\.id)
        guard let index = ids.firstIndex(of: list.id) else { return }
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        Task { await store.reorderLists(ids) }
    }

    /// Reorders sidebar lists from a drag `.onMove`. The sidebar shows every list
    /// in `position` order, so the visible offsets map straight onto the full id
    /// sequence; the result persists (and syncs) through the same core
    /// `reorderLists` path as the context-menu moves.
    func moveLists(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = store.orderedLists.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        Task { await store.reorderLists(ids) }
    }
}
