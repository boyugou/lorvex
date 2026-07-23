import Foundation
import LorvexCore

extension AppStore {
  var memory: MemorySnapshot? {
    get { memoryStorage.memory }
    set { memoryStorage.memory = newValue }
  }

  var memoryEntries: [MemoryEntry] { memoryStorage.memory?.entries ?? [] }

  var memoryKeyDraft: String {
    get { memoryStorage.memoryKeyDraft }
    set { memoryStorage.memoryKeyDraft = newValue }
  }

  var memoryContentDraft: String {
    get { memoryStorage.memoryContentDraft }
    set { memoryStorage.memoryContentDraft = newValue }
  }

  var isSavingMemory: Bool { memoryStorage.isSavingMemory }

  /// The original key of the entry being edited, or `nil` when composing a new
  /// entry. The composer reads this to show its edit banner and Cancel control.
  var memoryEditingKey: String? { memoryStorage.memoryEditingKey }

  /// A key + content are both required, and not mid-save. Trimmed so a
  /// whitespace-only draft can't be saved.
  var canSaveMemoryDraft: Bool {
    !memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isSavingMemory
  }

  func loadMemory() async {
    await perform {
      memoryStorage.memory = try await core.loadMemory()
    }
  }

  /// Adopt a refreshed memory snapshot without overwriting composer text. If a
  /// peer deleted the entry being edited, the draft becomes a create instead of
  /// retaining a rename source that no longer exists.
  func adoptReloadedMemoryPreservingDraft(_ loaded: MemorySnapshot) {
    memoryStorage.memory = loaded
    if let editingKey = memoryStorage.memoryEditingKey,
      !loaded.entries.contains(where: { $0.key == editingKey })
    {
      memoryStorage.memoryEditingKey = nil
    }
  }

  /// Begin editing an existing entry by loading it into the shared composer and
  /// recording its original key, which puts the composer in a visible edit mode
  /// and lets ``saveMemoryDraft()`` rename rather than duplicate on a key change.
  func beginEditingMemory(_ entry: MemoryEntry) {
    memoryStorage.memoryEditingKey = entry.key
    memoryStorage.memoryKeyDraft = entry.key
    memoryStorage.memoryContentDraft = entry.content
  }

  /// Abandon an in-progress edit or new draft, returning the composer to its
  /// empty create state.
  func cancelEditingMemory() {
    clearMemoryDraft()
  }

  func clearMemoryDraft() {
    memoryStorage.memoryKeyDraft = ""
    memoryStorage.memoryContentDraft = ""
    memoryStorage.memoryEditingKey = nil
  }

  @discardableResult
  func saveMemoryDraft() async -> Bool {
    guard canSaveMemoryDraft else { return false }
    memoryStorage.isSavingMemory = true
    defer { memoryStorage.isSavingMemory = false }
    do {
      let originalKey = memoryStorage.memoryEditingKey
      // Editing an entry under a new key is a rename, not a second entry. Route it
      // through the atomic core rename (one transaction, one in-place record edit)
      // so a crash can't leave the old + new keys both present.
      if let originalKey,
        originalKey != memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      {
        _ = try await core.renameMemory(
          oldKey: originalKey, newKey: memoryKeyDraft, content: memoryContentDraft)
      } else {
        _ = try await core.upsertMemory(key: memoryKeyDraft, content: memoryContentDraft)
      }
      let reloaded = try await core.loadMemory()
      lorvexAnimated(.snappy(duration: 0.18)) {
        memoryStorage.memory = reloaded
      }
      feedbackProvider.playFeedback(.contentSaved)
      clearMemoryDraft()
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  func deleteMemoryEntry(_ entry: MemoryEntry) async -> Bool {
    guard !isSavingMemory else { return false }
    memoryStorage.isSavingMemory = true
    defer { memoryStorage.isSavingMemory = false }
    do {
      _ = try await core.deleteMemory(key: entry.key)
      let reloaded = try await core.loadMemory()
      lorvexAnimated(.snappy(duration: 0.18)) {
        memoryStorage.memory = reloaded
      }
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }
}
