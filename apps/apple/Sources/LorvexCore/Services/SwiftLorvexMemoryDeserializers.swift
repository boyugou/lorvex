import Foundation

/// Maps the core's `memories` rows onto the app's stable `MemoryEntry` model.
///
/// Taking primitive fields rather than the core `MemoryRepo.MemoryEntry` struct
/// sidesteps the name clash between the core's `LorvexStore.MemoryEntry` and the
/// app's `MemoryEntry`.
enum SwiftLorvexMemoryDeserializers {
  static func memoryEntry(key: String, content: String, updatedAt: String) -> MemoryEntry {
    MemoryEntry(key: key, content: content, updatedAt: updatedAt)
  }
}
