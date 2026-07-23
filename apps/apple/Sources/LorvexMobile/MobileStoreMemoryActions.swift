import Foundation
import LorvexCore

extension MobileStore {
  public var canSaveMemoryDraft: Bool {
    !memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isSavingMemory
  }

  public func loadMemorySnapshot() async {
    do {
      memory = try await core.loadMemory()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  public func beginEditingMemory(_ entry: MemoryEntry) {
    memoryEditingKey = entry.key
    memoryKeyDraft = entry.key
    memoryContentDraft = entry.content
  }

  public func clearMemoryDraft() {
    memoryEditingKey = nil
    memoryKeyDraft = ""
    memoryContentDraft = ""
  }

  @discardableResult
  public func saveMemoryDraft() async -> Bool {
    guard canSaveMemoryDraft else { return false }
    isSavingMemory = true
    defer { isSavingMemory = false }
    do {
      let originalKey = memoryEditingKey
      // Editing an entry under a new key is an atomic rename (one in-place record
      // edit), not an upsert-new-then-delete-old pair that could leave both keys
      // present on a crash between the two writes.
      let saved: MemoryEntry
      if let originalKey,
        originalKey != memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      {
        saved = try await core.renameMemory(
          oldKey: originalKey, newKey: memoryKeyDraft, content: memoryContentDraft)
      } else {
        saved = try await core.upsertMemory(key: memoryKeyDraft, content: memoryContentDraft)
      }
      memory = try await core.loadMemory()
      // Select the entry that was just saved. `loadMemory` returns entries
      // ordered by key, so `entries.first` would jump the detail pane to the
      // alphabetically-first entry instead of the one the user wrote.
      selectedMemoryKey = saved.id
      clearMemoryDraft()
      errorMessage = nil
      feedbackProvider.playFeedback(.contentSaved)
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteMemoryEntry(_ entry: MemoryEntry) async -> Bool {
    guard !isSavingMemory else { return false }
    isSavingMemory = true
    defer { isSavingMemory = false }

    do {
      _ = try await core.deleteMemory(key: entry.key)
      memory = try await core.loadMemory()
      if selectedMemoryKey == entry.id {
        selectedMemoryKey = nil
      }
      if memoryEditingKey == entry.key {
        clearMemoryDraft()
      }
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteMemoryEntries(_ entries: some Sequence<MemoryEntry>) async -> Bool {
    let entries = Array(entries)
    guard !entries.isEmpty, !isSavingMemory else {
      return false
    }
    let keysToDelete = stableUniqueMemoryKeys(entries.map(\.key))

    isSavingMemory = true
    defer { isSavingMemory = false }

    // Each delete is its own transaction; a mid-batch failure leaves the earlier
    // deletions committed. Stop on the first failure but ALWAYS reconcile the
    // entries + selection/draft against the store, so a partial batch never leaves
    // the UI showing an already-deleted memory or a selection or composer pointing
    // at one.
    var caught: Error?
    for key in keysToDelete {
      do {
        _ = try await core.deleteMemory(key: key)
      } catch {
        caught = error
        break
      }
    }

    memory = (try? await core.loadMemory()) ?? memory
    let liveKeys = Set(memory?.entries.map(\.key) ?? [])
    if let selectedMemoryKey, !liveKeys.contains(selectedMemoryKey) {
      self.selectedMemoryKey = nil
    }
    if let memoryEditingKey, !liveKeys.contains(memoryEditingKey) {
      clearMemoryDraft()
    }

    if let caught {
      await presentUserFacingError(caught)
      return false
    }
    errorMessage = nil
    return true
  }

  private func stableUniqueMemoryKeys(_ keys: [MemoryEntry.ID]) -> [MemoryEntry.ID] {
    var seen = Set<MemoryEntry.ID>()
    return keys.filter { seen.insert($0).inserted }
  }
}
