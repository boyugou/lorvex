import Foundation
import LorvexCore
import LorvexDomain

public struct MobileTaskEditDraft: Equatable, Identifiable, Sendable {
  public var id: LorvexTask.ID
  public var title: String
  public var notes: String
  public var priority: LorvexTask.Priority
  public var estimatedMinutesText: String
  /// The task's external deadline (`due_date`), the day to finish by —
  /// independent of the planned work day and the hide-until date. Editable
  /// through the ``hasDueDate`` toggle + ``dueDate`` picker; a UTC-midnight day
  /// anchor bridged to/from the local-calendar picker frame (see
  /// ``PlannedDayBridge``).
  public var hasDueDate: Bool
  public var dueDate: Date
  public var hasPlannedDate: Bool
  public var plannedDate: Date
  /// The task's defer-until / hide-until date (`available_from`): the task is
  /// hidden from day surfaces until this day. Editable through the
  /// ``hasAvailableFrom`` toggle + ``availableFrom`` picker; a UTC-midnight day
  /// anchor like ``dueDate`` and ``plannedDate``.
  public var hasAvailableFrom: Bool
  public var availableFrom: Date
  public var tagsText: String
  public var dependsOnText: String

  // Immutable baseline captured when the sheet opens. Saving derives a
  // field-level core patch from the differences instead of writing every stale
  // read-back value, so a concurrent Cloud/MCP edit to an untouched field
  // survives the user's later save.
  private let originalTitle: String
  private let originalNotes: String
  private let originalPriority: LorvexTask.Priority
  private let originalEstimatedMinutes: Int?
  private let originalDueDate: Date?
  private let originalPlannedDate: Date?
  private let originalAvailableFrom: Date?
  private let originalTags: [String]
  private let originalDependencies: [LorvexTask.ID]

  public init(task: LorvexTask, defaultPlannedDate: Date = Date()) {
    id = task.id
    title = task.title
    notes = task.notes
    priority = task.priority
    estimatedMinutesText = task.estimatedMinutes.map(String.init) ?? ""
    // Each stored date is a UTC-midnight day anchor; the pickers are
    // local-calendar controls, so bridge every one through PlannedDayBridge.
    hasDueDate = task.dueDate != nil
    dueDate = task.dueDate.map { PlannedDayBridge.displayDate(forStorageDate: $0) } ?? defaultPlannedDate
    hasPlannedDate = task.plannedDate != nil
    plannedDate =
      task.plannedDate.map { PlannedDayBridge.displayDate(forStorageDate: $0) } ?? defaultPlannedDate
    hasAvailableFrom = task.availableFrom != nil
    availableFrom =
      task.availableFrom.map { PlannedDayBridge.displayDate(forStorageDate: $0) } ?? defaultPlannedDate
    tagsText = task.tags.joined(separator: ", ")
    dependsOnText = task.dependsOn.joined(separator: ", ")
    originalTitle = task.title
    originalNotes = task.notes
    originalPriority = task.priority
    originalEstimatedMinutes = task.estimatedMinutes
    originalDueDate = task.dueDate
    originalPlannedDate = task.plannedDate
    originalAvailableFrom = task.availableFrom
    originalTags = task.tags
    originalDependencies = task.dependsOn
  }

  /// The `due_date` to persist: the picker day re-anchored to the storage
  /// (UTC-midnight) frame, or `nil` when the toggle is off (clears the deadline).
  public var dueDateForSave: Date? {
    hasDueDate ? PlannedDayBridge.storageDate(forLocalInstant: dueDate) : nil
  }

  /// The `planned_date` to persist, storage-frame anchored; `nil` clears it.
  public var plannedDateForSave: Date? {
    hasPlannedDate ? PlannedDayBridge.storageDate(forLocalInstant: plannedDate) : nil
  }

  /// The `available_from` to persist, storage-frame anchored; `nil` clears the
  /// hide-until so the task is never hidden.
  public var availableFromForSave: Date? {
    hasAvailableFrom ? PlannedDayBridge.storageDate(forLocalInstant: availableFrom) : nil
  }

  public var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var parsedEstimatedMinutes: Int? {
    let text = estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    guard let value = Int(text),
      (1...Int(ValidationLimits.maxEstimatedMinutes)).contains(value)
    else { return nil }
    return value
  }

  public var estimateIsValid: Bool {
    parsedEstimatedMinutes != nil
      || estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var parsedTags: [String] {
    Self.parseListText(tagsText)
  }

  public var parsedDependencies: [LorvexTask.ID] {
    Self.parseListText(dependsOnText)
  }

  /// Structured view of `tagsText` for token-style entry. Reading parses the
  /// comma-separated string; writing re-serializes to the same comma format so
  /// the persisted contract (`parsedTags`) is unchanged.
  public var tags: [String] {
    get { parsedTags }
    set { tagsText = newValue.joined(separator: ", ") }
  }

  /// Structured view of `dependsOnText` (dependency task IDs) for picker-style
  /// entry. Writing re-serializes to the comma format `parsedDependencies` reads.
  public var dependencyIDs: [LorvexTask.ID] {
    get { parsedDependencies }
    set { dependsOnText = newValue.joined(separator: ", ") }
  }

  public var canSave: Bool {
    !trimmedTitle.isEmpty && estimateIsValid
  }

  /// Patch only fields the user changed relative to the sheet's opening
  /// baseline. This is deliberately the same patch surface the MCP tool uses:
  /// an omitted field is never rewritten from a stale UI snapshot.
  var coreUpdateDraft: TaskUpdateDraft {
    let estimate = parsedEstimatedMinutes
    let due = dueDateForSave
    let planned = plannedDateForSave
    let available = availableFromForSave
    let tags = parsedTags
    let dependencies = parsedDependencies
    return TaskUpdateDraft(
      id: id,
      title: trimmedTitle == originalTitle ? nil : trimmedTitle,
      notes: notes == originalNotes ? nil : notes,
      priority: priority == originalPriority ? nil : priority,
      estimatedMinutes: Self.patch(estimate, comparedWith: originalEstimatedMinutes),
      dueDate: Self.patch(due, comparedWith: originalDueDate),
      plannedDate: Self.patch(planned, comparedWith: originalPlannedDate),
      availableFrom: Self.patch(available, comparedWith: originalAvailableFrom),
      tags: tags == originalTags ? nil : tags,
      dependsOn: dependencies == originalDependencies ? nil : dependencies)
  }

  private static func parseListText(_ text: String) -> [String] {
    var seen = Set<String>()
    return text
      .split(whereSeparator: { character in
        character == "," || character == "\n" || character == "\t"
      })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { seen.insert($0).inserted }
  }

  private static func patch<T: Equatable>(_ value: T?, comparedWith original: T?) -> Patch<T> {
    guard value != original else { return .unset }
    return value.map(Patch.set) ?? .clear
  }
}
