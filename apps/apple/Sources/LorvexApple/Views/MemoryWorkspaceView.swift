import LorvexCore
import SwiftUI

/// The macOS surface for AI memory: the key/content notes the assistant keeps
/// about the user's preferences and context. The entries render as rows in a
/// scroll view, like the other workspaces' catalogs, with hover and per-row
/// context menus; the composer above them appears on demand (the toolbar's
/// add button, or a row's Edit) to add or edit an entry. The window's toolbar
/// search field (``WorkspaceView``) narrows the rows to the notes whose key or content match.
/// Memory is AI-managed context that the app edits as the AI actor.
struct MemoryWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var isComposerPresented = false
  @State private var entryPendingDeletion: MemoryEntry?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if showsComposer {
        composerRegion
      }
      entriesArea
    }
    .navigationTitle(String(localized: "sidebar.item.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle))
    .toolbar {
      // Leading edge: the window's search field holds the trailing one.
      ToolbarItem(placement: .primaryAction) {
        Button {
          isComposerPresented = true
        } label: {
          Label(
            String(localized: "memory.composer.title", defaultValue: "New Memory", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "plus")
        }
        .help(String(localized: "memory.composer.title", defaultValue: "New Memory", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("memory.toolbar.add")
      }
    }
    .lorvexOpenDestinationActivity(selection: .memory, isActive: store.selection == .memory)
    .task {
      await store.loadMemory()
    }
    .confirmationDialog(
      entryPendingDeletion.map(deleteMemoryDialogTitle) ?? "",
      isPresented: Binding(
        get: { entryPendingDeletion != nil },
        set: { if !$0 { entryPendingDeletion = nil } }
      ),
      titleVisibility: .visible,
      presenting: entryPendingDeletion
    ) { entry in
      Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive) {
        Task { await store.deleteMemoryEntry(entry) }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: { _ in
      Text(LocalizedStringResource(
        "memory.delete.confirm.message",
        defaultValue: "The memory entry is removed. This can’t be undone.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
  }

  private func deleteMemoryDialogTitle(_ entry: MemoryEntry) -> String {
    String(
      format: String(
        localized: "memory.delete.confirm.title",
        defaultValue: "Delete memory \u{201C}%@\u{201D}?",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      entry.displayTitle
    )
  }

  // MARK: - Header

  private var header: some View {
    WorkspaceDashboardHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: "sidebar.item.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized: "memory.workspace.subtitle",
          defaultValue: "What the assistant remembers about you. You can add or edit entries too.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        icon: SidebarSelection.memory.systemImage,
        accessibilityIdentifier: "memory.header.identity",
        subtitleAccessibilityIdentifier: "memory.header.subtitle"
      )
    }
  }

  // MARK: - Composer

  /// The add/edit composer, shown above the list only while an entry is being
  /// added or edited (or a draft still holds text), so the default view is the
  /// list itself rather than a permanent empty editor. It sits above the list
  /// so editing always has a visible target and consecutive adds flow without
  /// scrolling.
  private var composerRegion: some View {
    WorkspaceDashboardLane {
      MemoryComposerCard(
        store: store,
        cancelCreate: {
          store.clearMemoryDraft()
          isComposerPresented = false
        },
        onSaved: { isComposerPresented = false }
      )
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.top, LorvexDesign.Spacing.m)
    .padding(.bottom, LorvexDesign.Spacing.s)
  }

  // MARK: - Entries

  @ViewBuilder
  private var entriesArea: some View {
    if store.memory == nil {
      WorkspaceDashboardLane {
        LorvexSkeletonRows(count: 3)
          .padding(.horizontal, LorvexDesign.Spacing.l)
          .padding(.vertical, LorvexDesign.Spacing.s)
      }
      .frame(maxHeight: .infinity, alignment: .top)
    } else if store.memoryEntries.isEmpty {
      LorvexEmptyStatePanel(
        title: String(localized: "memory.empty.title", defaultValue: "No Memory Entries", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "memory.empty.description",
          defaultValue: "Click ＋ to save something your assistant should remember.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "brain",
        tint: .accentColor
      )
    } else if store.filteredMemoryEntries.isEmpty {
      LorvexEmptyStatePanel(
        title: String(localized: "memory.empty.search_title", defaultValue: "No Matching Memory Entries", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "memory.empty.search_description",
          defaultValue: "No memory entry matches your search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "magnifyingglass",
        tint: .secondary
      ) {
        Button {
          store.searchText = ""
        } label: {
          Label(
            String(localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "xmark.circle")
        }
        .accessibilityIdentifier("memory.empty.clearSearch")
      }
    } else {
      entriesList
    }
  }

  private var entriesList: some View {
    ScrollView {
      WorkspaceDashboardLane {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(store.filteredMemoryEntries.enumerated()), id: \.element.id) { index, entry in
            if index > 0 {
              Divider()
            }
            MemoryEntryRow(
              entry: entry,
              edit: { store.beginEditingMemory(entry) },
              delete: { entryPendingDeletion = entry }
            )
            .padding(.vertical, LorvexDesign.Spacing.xs)
          }
        }
      }
      // Padded outside the lane, like the header's chrome, so the rows start
      // under the header's title at every window width.
      .padding(.horizontal, LorvexDesign.Spacing.l)
      .padding(.vertical, LorvexDesign.Spacing.s)
    }
    .accessibilityIdentifier("memory.list")
  }

  private var showsComposer: Bool {
    store.memoryEditingKey != nil
      || isComposerPresented
      || !store.memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !store.memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
