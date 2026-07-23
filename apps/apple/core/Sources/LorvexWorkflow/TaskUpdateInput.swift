import Foundation
import LorvexDomain

/// Single-item task update patch. Field names match the MCP `update_task`
/// tool's argument schema exactly so the cross-surface contract stays
/// in lockstep.
///
/// Three-state ``Patch`` is used for every nullable scalar column.
/// The `tags_*` and `depends_on*` set-mutating fields are
/// ``Optional<[String]>`` rather than ``Patch`` by design:
///
/// - **absent / `nil`** → no-op (don't touch the relation).
/// - **`[]` or any array** → apply the operation with that item list.
///
/// For the replace variants (`tagsSet`, `dependsOn`), `Some([])` *is*
/// the clear semantic. For the add/remove variants, `Some([])` is a
/// no-op. There is no third state to encode for set-typed relations
/// that write into junction tables.
public struct TaskUpdateInput: Sendable {
  public var id: String
  /// Three-state. `tasks.title` is NOT NULL, so ``Patch/clear``
  /// must be rejected by the preparation gate.
  public var title: Patch<String>
  public var body: Patch<String>
  public var rawInput: Patch<String>
  public var aiNotes: Patch<String>
  /// Three-state. `tasks.status` is NOT NULL with a closed-set
  /// allow-list (`open|completed|cancelled|someday`), so the
  /// preparation gate must reject ``Patch/clear``.
  public var status: Patch<String>
  /// Three-state. `tasks.list_id` is NOT NULL, so the preparation
  /// gate must reject ``Patch/clear``.
  public var listId: Patch<String>
  /// Replace the full tag set. `nil` = no-op; `Some([])` clears
  /// every tag. Mutually exclusive with `tagsAdd` / `tagsRemove`.
  public var tagsSet: [String]?
  /// Append tags without touching the rest of the set. Mutually
  /// exclusive with `tagsSet`.
  public var tagsAdd: [String]?
  /// Remove tags without touching the rest of the set. Mutually
  /// exclusive with `tagsSet`.
  public var tagsRemove: [String]?
  /// Three-state. `priority` is nullable in the schema (1..=3).
  public var priority: Patch<UInt8>
  public var dueDate: Patch<String>
  public var estimatedMinutes: Patch<UInt32>
  public var recurrence: Patch<JSONValue>
  /// Replace the full dependency edge set. `nil` = no-op;
  /// `Some([])` clears every edge. Mutually exclusive with
  /// `dependsOnAdd` / `dependsOnRemove`.
  public var dependsOn: [String]?
  public var dependsOnAdd: [String]?
  public var dependsOnRemove: [String]?
  public var plannedDate: Patch<String>
  public var availableFrom: Patch<String>

  public init(
    id: String,
    title: Patch<String> = .unset,
    body: Patch<String> = .unset,
    rawInput: Patch<String> = .unset,
    aiNotes: Patch<String> = .unset,
    status: Patch<String> = .unset,
    listId: Patch<String> = .unset,
    tagsSet: [String]? = nil,
    tagsAdd: [String]? = nil,
    tagsRemove: [String]? = nil,
    priority: Patch<UInt8> = .unset,
    dueDate: Patch<String> = .unset,
    estimatedMinutes: Patch<UInt32> = .unset,
    recurrence: Patch<JSONValue> = .unset,
    dependsOn: [String]? = nil,
    dependsOnAdd: [String]? = nil,
    dependsOnRemove: [String]? = nil,
    plannedDate: Patch<String> = .unset,
    availableFrom: Patch<String> = .unset
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.rawInput = rawInput
    self.aiNotes = aiNotes
    self.status = status
    self.listId = listId
    self.tagsSet = tagsSet
    self.tagsAdd = tagsAdd
    self.tagsRemove = tagsRemove
    self.priority = priority
    self.dueDate = dueDate
    self.estimatedMinutes = estimatedMinutes
    self.recurrence = recurrence
    self.dependsOn = dependsOn
    self.dependsOnAdd = dependsOnAdd
    self.dependsOnRemove = dependsOnRemove
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
  }

  /// Canonical field set this input accepts. Used by the
  /// cross-surface contract verifier that pins every consumer's
  /// `update_task` wire shape to the same field set.
  public static let fields: [String] = [
    "id",
    "title",
    "body",
    "raw_input",
    "ai_notes",
    "status",
    "list_id",
    "tags_set",
    "tags_add",
    "tags_remove",
    "priority",
    "due_date",
    "estimated_minutes",
    "recurrence",
    "depends_on",
    "depends_on_add",
    "depends_on_remove",
    "planned_date",
    "available_from",
  ]
}

/// Free-text Unicode sanitizer for an update patch: every free-text
/// scalar runs through ``UnicodeHygiene/sanitizeUserText(_:)``; the
/// tag set-fields apply the same sanitizer to each element.
///
/// Operates in-place so orchestrator call sites read the sanitized
/// patch directly.
public enum TaskUpdateSanitize {
  public static func sanitizeInput(_ patch: inout TaskUpdateInput) {
    patch.title = patch.title.map(UnicodeHygiene.sanitizeUserText)
    patch.body = patch.body.map(UnicodeHygiene.sanitizeUserText)
    patch.rawInput = patch.rawInput.map(UnicodeHygiene.sanitizeUserText)
    patch.aiNotes = patch.aiNotes.map(UnicodeHygiene.sanitizeUserText)
    patch.tagsSet = sanitizeVec(patch.tagsSet)
    patch.tagsAdd = sanitizeVec(patch.tagsAdd)
    patch.tagsRemove = sanitizeVec(patch.tagsRemove)
  }

  private static func sanitizeVec(_ values: [String]?) -> [String]? {
    values.map { $0.map(UnicodeHygiene.sanitizeUserText) }
  }
}
