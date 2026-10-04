import SwiftUI
import LorvexCore

enum SidebarRowSelection: Hashable {
    case destination(SidebarSelection)
    case listScope(LorvexList.ID)
}

// MARK: - View

struct SidebarView: View {
    @Bindable var store: AppStore
    // Shared with the list section in SidebarListSection.swift, so these are
    // module-internal rather than private (the AppStore multi-file split pattern).
    @State var isShowingCreateList = false
    @State var editingList: LorvexList?
    @State var dropTargetedListID: LorvexList.ID?
    @State var listPendingDeletion: LorvexList?
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(spacing: 0) {
            sidebarList
            utilitiesFooter
        }
        .frame(
            minWidth: SidebarMetrics.columnMinWidth,
            idealWidth: SidebarMetrics.columnIdealWidth,
            maxWidth: SidebarMetrics.columnMaxWidth
        )
        .sheet(isPresented: $isShowingCreateList) {
            CreateListSheet(store: store, isPresented: $isShowingCreateList)
        }
        .sheet(item: $editingList) { list in
            EditListSheet(
                list: list,
                store: store,
                isPresented: Binding(
                    get: { editingList != nil },
                    set: { if !$0 { editingList = nil } }
                )
            )
        }
    }

    private var sidebarList: some View {
        withListDeletionDialog(
            List(selection: sidebarSelection) {
                planSection
                listScopeSection
                archivedListScopeSection
            }
            .listStyle(.sidebar)
        )
        .accessibilityIdentifier("sidebar.list")
    }

    // MARK: - Selection → navigation

    /// The row the native selection highlight lands on, derived from the store's
    /// current workspace / list scope. `nil` when the active workspace has no
    /// source-list row (the Lists catalog, Matrix, or Dependencies), so the list
    /// simply shows nothing selected.
    var selectedRow: SidebarRowSelection? {
        if store.selection == .tasks, let scope = store.taskWorkspaceListScopeID {
            return .listScope(scope)
        }
        guard SidebarSelection.sidebarGroups.contains(where: { $0.items.contains(store.selection) })
        else { return nil }
        return .destination(store.selection)
    }

    func isSelected(_ row: SidebarRowSelection) -> Bool {
        selectedRow == row
    }

    /// Two-way binding for `List(selection:)`. Reads the derived `selectedRow`;
    /// on user selection (click, arrow-key move, type-select) it navigates so
    /// selecting a row *is* navigating, the Mail/Notes source-list convention. A
    /// nil write (a rare deselect) is ignored — the sidebar always reflects a
    /// live workspace.
    private var sidebarSelection: Binding<SidebarRowSelection?> {
        Binding(
            get: { selectedRow },
            set: { newValue in
                if let newValue { navigate(to: newValue) }
            }
        )
    }

    private func navigate(to row: SidebarRowSelection) {
        switch row {
        case .destination(let destination):
            store.navigateToWorkspace(destination)
        case .listScope(let id):
            store.openTaskListScope(id)
        }
    }

    // MARK: - Destination sections

    private var planSection: some View {
        Section {
            destinationRows(.plan)
        }
    }

    @ViewBuilder
    private func destinationRows(_ kind: SidebarGroupKind) -> some View {
        if let group = SidebarSelection.sidebarGroups.first(where: { $0.kind == kind }) {
            ForEach(group.items) { item in
                SidebarListRow {
                    Image(systemName: item.systemImage)
                } title: {
                    Text(item.macOSLocalizedTitle)
                }
                .listRowInsets(SidebarMetrics.rowInsets)
                .tag(SidebarRowSelection.destination(item))
                .accessibilityIdentifier("sidebar.\(item.rawValue)")
            }
        }
    }

    // MARK: - Footer

    /// The two places that don't belong to a scrolling group, pinned so they
    /// never scroll away behind a long list of lists: Memory, what the assistant
    /// remembers, which is not a daily workspace but must always be findable and
    /// shows its selection here while open; and Settings, which opens its own
    /// window. The command palette is intentionally absent: it is an action, not
    /// a place, and stays reachable through ⌘K and the File menu rather than
    /// occupying a sidebar row (which no native Mac app does).
    private var utilitiesFooter: some View {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            Button {
                store.navigateToWorkspace(.memory)
            } label: {
                SidebarFooterRow(isSelected: store.selection == .memory) {
                    Image(systemName: SidebarSelection.memory.systemImage)
                } title: {
                    Text(SidebarSelection.memory.macOSLocalizedTitle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: SidebarSelection.memory.macOSLocalizedTitle))
            .accessibilityAddTraits(store.selection == .memory ? .isSelected : [])
            .accessibilityIdentifier("sidebar.memory")

            SettingsLink {
                SidebarFooterRow {
                    Image(systemName: "gearshape")
                } title: {
                    Text(LocalizedStringResource("sidebar.settings", defaultValue: "Settings", table: "Localizable", bundle: LorvexL10n.bundle))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "sidebar.settings", defaultValue: "Settings", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityIdentifier("sidebar.settings")
        }
        .padding(.horizontal, SidebarMetrics.capsuleInset)
        .padding(.top, LorvexDesign.Spacing.sm)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.45)
        }
    }
}
