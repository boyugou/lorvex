import LorvexCore
import SwiftUI

/// The macOS surface for AI memory: the key/content notes the assistant keeps
/// about the user's preferences and context. The entries render as a native
/// `List` with hover and per-row context menus; the composer above them adds or
/// edits entries. Memory is AI-managed context that the app edits as the AI
/// actor.
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
    .lorvexOpenDestinationActivity(selection: .memory, isActive: store.selection == .memory)
    .task { await store.loadMemory() }
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
        defaultValue: "The memory entry is removed. This can't be undone.",
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
      entry.key
    )
  }

  // MARK: - Header

  private var header: some View {
    WorkspaceDashboardHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: "sidebar.item.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized: "memory.workspace.subtitle",
          defaultValue: "What the assistant remembers about you. You can add or edit notes too.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: SidebarSelection.memory.systemImage,
        accessibilityIdentifier: "memory.header.identity",
        subtitleAccessibilityIdentifier: "memory.header.subtitle"
      )
    }
  }

  // MARK: - Composer

  /// The add/edit composer, pinned above the list so editing an entry always has
  /// a visible target and consecutive adds flow without scrolling. On an empty
  /// memory store it opens only after the empty-state action, so the first view
  /// reads as a clean state rather than a disabled editor plus an empty panel.
  private var composerRegion: some View {
    WorkspaceDashboardLane {
      MemoryComposerCard(
        store: store,
        cancelCreate: store.memoryEntries.isEmpty ? {
          store.clearMemoryDraft()
          isComposerPresented = false
        } : nil
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
        title: String(localized: "memory.empty.title", defaultValue: "No memory yet", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "memory.empty.description",
          defaultValue: "Notes you or your assistant save about your preferences and context appear here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "brain",
        tint: .accentColor
      ) {
        Button {
          isComposerPresented = true
        } label: {
          Label(
            String(localized: "memory.composer.title", defaultValue: "New memory", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "plus")
        }
        .buttonStyle(.lorvexPrimary)
        .accessibilityIdentifier("memory.empty.add")
      }
    } else {
      entriesList
    }
  }

  @ViewBuilder
  private var entriesList: some View {
    WorkspaceDashboardLane {
      List {
        ForEach(store.memoryEntries) { entry in
          MemoryEntryRow(
            entry: entry,
            edit: { store.beginEditingMemory(entry) },
            delete: { entryPendingDeletion = entry }
          )
          .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }
      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
      .accessibilityIdentifier("memory.list")
    }
    .frame(maxHeight: .infinity)
  }

  private var showsComposer: Bool {
    store.memoryEditingKey != nil
      || isComposerPresented
      || !store.memoryEntries.isEmpty
      || !store.memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !store.memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
