import Foundation
import LorvexCore

/// Runtime state for the AI-memory workspace: the loaded snapshot, the key/content
/// draft (shared by the create and edit flows), and the in-flight save flag.
/// Mirrors the iOS `MobileStore` memory fields so both surfaces drive the same
/// `LorvexMemoryServicing` contract.
struct AppStoreMemoryStorage {
  var memory: MemorySnapshot?
  var memoryKeyDraft = ""
  var memoryContentDraft = ""
  /// The original key of the entry currently being edited, or `nil` when the
  /// composer is creating a new entry. Drives the editor's visible edit state
  /// and lets a key change rename rather than duplicate the entry.
  var memoryEditingKey: String?
  var isSavingMemory = false

  mutating func reset() {
    memory = nil
    memoryKeyDraft = ""
    memoryContentDraft = ""
    memoryEditingKey = nil
    isSavingMemory = false
  }
}
