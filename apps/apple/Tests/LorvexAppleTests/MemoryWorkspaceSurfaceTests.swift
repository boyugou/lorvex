import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - Search filtering

@MainActor
@Test
func filteredMemoryEntriesReturnsAllWhenQueryEmpty() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.loadMemory()

  store.searchText = ""
  #expect(store.filteredMemoryEntries.count == store.memoryEntries.count)
  #expect(store.filteredMemoryEntries.count >= 2)
}

@MainActor
@Test
func filteredMemoryEntriesMatchesOnKey() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.loadMemory()

  store.searchText = "swift"
  let keys = store.filteredMemoryEntries.map(\.key)
  #expect(keys == ["swift_migration"])
}

@MainActor
@Test
func filteredMemoryEntriesMatchesOnContentCaseInsensitively() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.loadMemory()

  // "swift_migration" content mentions "database"; "notes_for_ai" does not.
  store.searchText = "DATABASE"
  #expect(store.filteredMemoryEntries.map(\.key) == ["swift_migration"])

  // "notes_for_ai" content mentions frameworks; the migration entry does not.
  store.searchText = "framework"
  #expect(store.filteredMemoryEntries.map(\.key) == ["notes_for_ai"])
}

@MainActor
@Test
func filteredMemoryEntriesEmptyForNonMatchingQuery() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.loadMemory()

  store.searchText = "zzz-no-such-memory"
  #expect(store.filteredMemoryEntries.isEmpty)
}

// MARK: - Native surface (source assertions)

private func memorySource(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
}

@Test
func memoryWorkspaceUsesNativeListAndContextualComposer() throws {
  let source = try memorySource("Sources/LorvexApple/Views/MemoryWorkspaceView.swift")
  // Rows in a scroll view like the other workspaces: a `List` under the
  // window toolbar lifts the header above the window's top edge.
  #expect(source.contains("ScrollView {"))
  #expect(source.contains("LazyVStack(alignment: .leading, spacing: 0)"))
  #expect(!source.contains("List {"))
  #expect(source.contains(#".accessibilityIdentifier("memory.list")"#))
  // The search field belongs to the window (WorkspaceView), not the workspace,
  // so switching workspaces never stacks two toolbar search items.
  #expect(!source.contains(".lorvexWorkspaceSearchField("))
  #expect(source.contains("store.filteredMemoryEntries"))
  #expect(source.contains("@State private var isComposerPresented = false"))
  #expect(source.contains("if showsComposer {"))
  // The toolbar's add button is the one way to start a note; the empty state
  // does not repeat it.
  #expect(source.contains(#".accessibilityIdentifier("memory.toolbar.add")"#))
  #expect(!source.contains(#".accessibilityIdentifier("memory.empty.add")"#))
  #expect(source.contains("private var showsComposer: Bool"))
  #expect(source.contains("MemoryEntryRow("))
  // First-paint stays a skeleton, not a spinner.
  #expect(source.contains("LorvexSkeletonRows(count: 3)"))
  #expect(!source.contains("ProgressView()"))
}

@Test
func memoryRowExposesHoverPointerAndContextMenu() throws {
  let source = try memorySource("Sources/LorvexApple/Views/MemoryEntryRow.swift")
  #expect(source.contains(".contextMenu {"))
  #expect(source.contains(".onHover"))
  #expect(source.contains("NSCursor.pointingHand"))
  #expect(source.contains(#"accessibilityIdentifier("memory.row.\(entry.key)")"#))
  // Edit / Delete reveal on hover and in the context menu; every memory is
  // AI-managed, so there is no ownership gate on the write actions.
  #expect(source.contains("if isHovering {"))
}
