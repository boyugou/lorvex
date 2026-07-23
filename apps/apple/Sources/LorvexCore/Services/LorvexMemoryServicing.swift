import Foundation

public protocol LorvexMemoryServicing: Sendable {
  func loadMemory() async throws -> MemorySnapshot

  func upsertMemory(key: String, content: String) async throws -> MemoryEntry

  /// Atomically rename a memory from `oldKey` to `newKey` in one transaction
  /// (optionally replacing content with `content`), preserving the entry's opaque
  /// sync id so it is one in-place record edit rather than a create + tombstone.
  /// Rejects a rename onto a different existing key. Returns the renamed entry.
  func renameMemory(oldKey: String, newKey: String, content: String?) async throws -> MemoryEntry

  /// Deletes a memory entry by key. Returns false when the key was already absent.
  func deleteMemory(key: String) async throws -> Bool
}

extension LorvexMemoryServicing {
  /// Non-atomic fallback rename for conformers (test doubles) that don't provide a
  /// dedicated implementation: upsert the new key, then delete the old. The
  /// production ``SwiftLorvexCoreService`` overrides this with a single atomic,
  /// id-preserving in-place rename (the whole point of ``renameMemory``), so this
  /// default is never the shipping path.
  public func renameMemory(oldKey: String, newKey: String, content: String?) async throws
    -> MemoryEntry
  {
    let resolvedContent: String
    if let content {
      resolvedContent = content
    } else {
      resolvedContent = try await loadMemory().entries.first { $0.key == oldKey }?.content ?? ""
    }
    let saved = try await upsertMemory(key: newKey, content: resolvedContent)
    if oldKey != newKey {
      _ = try await deleteMemory(key: oldKey)
    }
    return saved
  }
}
