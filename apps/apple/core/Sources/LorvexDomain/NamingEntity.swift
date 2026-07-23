/// Entity type vocabulary — the canonical wire-format strings and the typed
/// ``EntityKind`` enum for every aggregate root, independent child, audit
/// stream, edge, and local-only kind that flows across the sync envelope,
/// payload shadow, version stamp, and outbox routing.
///
/// Wire format and SQLite TEXT columns carry the canonical string value
/// (``EntityKind/asString``); this enum is the single source of truth for the
/// closed set and the topological order used by batch sync / import.
public enum EntityName {
  public static let task = "task"
  public static let list = "list"
  public static let habit = "habit"
  public static let tag = "tag"
  public static let calendarEvent = "calendar_event"
  public static let calendarSeriesCutover = "calendar_series_cutover"
  public static let preference = "preference"
  public static let memory = "memory"
  public static let dailyReview = "daily_review"
  public static let currentFocus = "current_focus"
  public static let focusSchedule = "focus_schedule"
  public static let taskReminder = "task_reminder"
  public static let taskChecklistItem = "task_checklist_item"
  public static let habitReminderPolicy = "habit_reminder_policy"
  public static let aiChangelog = "ai_changelog"
  /// Permanent same-type identity alias emitted by deterministic aggregate merges.
  public static let entityRedirect = "entity_redirect"

  // Local-only entity type names (not synced, not in topologicalEntityOrder).
  public static let deviceState = "device_state"
  /// Synthetic entity classification for the `import_data` audit row. Not in
  /// ``EntityKind/allSyncableTypes``: import-session records are local audit
  /// metadata, not replicated state.
  public static let importSession = "import_session"

  /// All entity type names in declaration order.
  public static let allEntityTypes: [String] = [
    task,
    list,
    habit,
    tag,
    calendarEvent,
    calendarSeriesCutover,
    preference,
    memory,
    dailyReview,
    currentFocus,
    focusSchedule,
    taskReminder,
    taskChecklistItem,
    habitReminderPolicy,
    aiChangelog,
    entityRedirect,
  ]
}

/// Error returned by ``EntityKind/init(parsing:)`` for unrecognized values.
public struct UnknownEntityKind: Error, Equatable, CustomStringConvertible {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }

  public var description: String {
    "unknown entity kind: \(value)"
  }
}

/// Strongly-typed entity / edge classification used across the sync pipeline,
/// payload shadow, version stamping, and outbox routing.
///
/// Every consumer exhaustive-matches against this closed set instead of
/// dispatching on a raw `entity_type` string. The wire format and SQLite TEXT
/// columns carry the canonical string value (``asString`` / `rawValue`).
public enum EntityKind: String, Sendable, Hashable, Codable, CaseIterable, CustomStringConvertible {
  // Aggregate roots
  case task = "task"
  case list = "list"
  case habit = "habit"
  case tag = "tag"
  case calendarEvent = "calendar_event"
  case calendarSeriesCutover = "calendar_series_cutover"
  case preference = "preference"
  case memory = "memory"
  case dailyReview = "daily_review"
  case currentFocus = "current_focus"
  case focusSchedule = "focus_schedule"
  // Independent children
  case taskReminder = "task_reminder"
  case taskChecklistItem = "task_checklist_item"
  case habitReminderPolicy = "habit_reminder_policy"
  // Audit stream
  case aiChangelog = "ai_changelog"
  // Permanent identity-alias ledger
  case entityRedirect = "entity_redirect"
  // Edges
  case taskTag = "task_tag"
  case taskDependency = "task_dependency"
  case taskCalendarEventLink = "task_calendar_event_link"
  case habitCompletion = "habit_completion"
  // Local-only (not in allSyncableTypes / topologicalEntityOrder).
  case deviceState = "device_state"
  case importSession = "import_session"

  /// Canonical string form. Identical to the matching wire-format constant.
  public var asString: String { rawValue }

  public var description: String { rawValue }

  /// Parse a runtime string into an `EntityKind`, returning `nil` for any
  /// value not in the closed set. The caller is responsible for surfacing a
  /// typed error at its own layer.
  ///
  /// Callers that *know* the input must be a member of the closed set should
  /// prefer ``tryParse(_:)``, which surfaces a typed ``UnknownEntityKind`` and
  /// an `assertionFailure` in debug builds instead of a silent `nil`.
  public static func parse(_ value: String) -> EntityKind? {
    EntityKind(rawValue: value)
  }

  /// Parse a runtime string into an `EntityKind`, returning a typed error for
  /// unknown values. Fires an `assertionFailure` in debug builds so a future
  /// vocabulary extension that forgets to add an `EntityKind` case fails loudly.
  public static func tryParse(_ value: String) -> Result<EntityKind, UnknownEntityKind> {
    if let kind = parse(value) {
      return .success(kind)
    }
    assertionFailure(
      "EntityKind.tryParse: unknown entity kind \(value); if a new entity type "
        + "was added, extend the EntityKind enum to match.")
    return .failure(UnknownEntityKind(value))
  }

  /// Parse a runtime string into an `EntityKind`, throwing ``UnknownEntityKind``
  /// for unknown values. Unlike ``tryParse(_:)`` this never asserts — it is the
  /// boundary constructor for runtime strings that may legitimately be invalid.
  public init(parsing value: String) throws {
    guard let kind = EntityKind.parse(value) else {
      throw UnknownEntityKind(value)
    }
    self = kind
  }

  /// `true` iff this kind participates in cross-device sync (i.e. is not a
  /// local-only kind such as `device_state` or `import_session`).
  /// Mirrors ``allSyncableTypes``.
  public var isSyncableKind: Bool {
    switch self {
    case .deviceState, .importSession: return false
    default: return true
    }
  }

  /// `true` for the 4 edge kinds (composite-PK relationships).
  public var isEdge: Bool {
    switch self {
    case .taskTag, .taskDependency, .taskCalendarEventLink, .habitCompletion:
      return true
    default: return false
    }
  }

  /// `true` for entity kinds whose `entity_id` is a natural key (a date string
  /// or a preference key) rather than a UUIDv7. Natural-key entities never
  /// participate in merge-redirect rewriting.
  ///
  /// `memory` is intentionally NOT here: its `entity_id` is the row's opaque
  /// `id` (its human `key` is a plain UNIQUE column, decoupled from routing), so
  /// a same-key collision CAN converge via a permanent identity alias — which
  /// the redirect chase must be allowed to remap.
  public var isNaturalKey: Bool {
    switch self {
    case .dailyReview, .currentFocus, .focusSchedule, .preference, .calendarSeriesCutover:
      return true
    default: return false
    }
  }

  /// The SQL table that stores this kind's rows, or `nil` for kinds not
  /// persisted as a single SQL table (`import_session` is a synthetic audit
  /// classification with no table of its own).
  public var tableName: String? {
    switch self {
    case .task: return "tasks"
    case .list: return "lists"
    case .habit: return "habits"
    case .tag: return "tags"
    case .calendarEvent: return "calendar_events"
    case .calendarSeriesCutover: return "calendar_series_cutovers"
    case .preference: return "preferences"
    case .memory: return "memories"
    case .dailyReview: return "daily_reviews"
    case .currentFocus: return "current_focus"
    case .focusSchedule: return "focus_schedule"
    case .taskReminder: return "task_reminders"
    case .taskChecklistItem: return "task_checklist_items"
    case .habitReminderPolicy: return "habit_reminder_policies"
    case .taskTag: return "task_tags"
    case .taskDependency: return "task_dependencies"
    case .taskCalendarEventLink: return "task_calendar_event_links"
    case .habitCompletion: return "habit_completions"
    case .entityRedirect: return "sync_entity_redirects"
    case .deviceState: return "device_state"
    case .aiChangelog: return "ai_changelog"
    case .importSession: return nil
    }
  }

  /// A syncable simple-PK kind's `(table, pkColumn)` pair. `nil` for edges
  /// (composite PK), the audit stream (`ai_changelog`, append-only), and
  /// local-only kinds.
  public var tablePk: (table: String, pk: String)? {
    switch self {
    case .task: return ("tasks", "id")
    case .list: return ("lists", "id")
    case .habit: return ("habits", "id")
    case .tag: return ("tags", "id")
    case .calendarEvent: return ("calendar_events", "id")
    case .calendarSeriesCutover: return ("calendar_series_cutovers", "id")
    case .preference: return ("preferences", "key")
    // `memories` routes on the opaque `id`, not the human-meaningful `key`
    // (which is a plain UNIQUE column), so the CloudKit `entity_id` stays opaque.
    case .memory: return ("memories", "id")
    case .dailyReview: return ("daily_reviews", "date")
    case .currentFocus: return ("current_focus", "date")
    case .focusSchedule: return ("focus_schedule", "date")
    case .taskReminder: return ("task_reminders", "id")
    case .taskChecklistItem: return ("task_checklist_items", "id")
    case .habitReminderPolicy: return ("habit_reminder_policies", "id")
    case .aiChangelog, .entityRedirect, .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion, .deviceState, .importSession:
      return nil
    }
  }

  /// All entity and edge types the sync pipeline recognizes — the set an inbound
  /// envelope's `entity_type` is accepted against (a type outside it is treated
  /// as local-only and skipped on apply).
  ///
  /// This is the single source of truth. `ai_changelog` participates with a
  /// BOUNDED outbound contract rather than the usual bidirectional upsert/delete
  /// lane: the append-only audit stream is emitted once by the ordinary write
  /// path and converges by id-dedup (`INSERT OR IGNORE`, no LWW). Ordinary
  /// full-resync excludes it; a candidate generation separately stages every
  /// still-retained row before its predecessor retires. Retention GC queues an
  /// exact-zone CloudKit physical delete and inbound apply enforces the local
  /// frontier, so a lagging peer cannot resurrect retired history. Parent-owned
  /// collection tables are NOT independently synced; they are embedded in their
  /// parent entity payloads.
  public static let allSyncableTypes: [String] = [
    // Aggregate roots
    EntityName.task,
    EntityName.list,
    EntityName.habit,
    EntityName.tag,
    EntityName.calendarEvent,
    EntityName.calendarSeriesCutover,
    EntityName.preference,
    EntityName.memory,
    EntityName.dailyReview,
    EntityName.currentFocus,
    EntityName.focusSchedule,
    // Independent children
    EntityName.taskReminder,
    EntityName.taskChecklistItem,
    EntityName.habitReminderPolicy,
    // Audit stream
    EntityName.aiChangelog,
    // Permanent identity aliases use their own record namespace. They are
    // absorbing upserts, never ordinary domain deletes.
    EntityName.entityRedirect,
    // Edges
    EdgeName.taskTag,
    EdgeName.taskDependency,
    EdgeName.taskCalendarEventLink,
    EdgeName.habitCompletion,
  ]

  /// Fixed topological order for batch sync and import. Rows are applied in
  /// this order to satisfy foreign-key constraints without deferral: aggregate
  /// roots first, then edges, then independent children. Permanent aliases are
  /// last because an alias is accepted only after its terminal target exists.
  /// This is especially important for authoritative snapshots, where a deferred
  /// record aborts the atomic adoption rather than entering the retry inbox.
  public static let topologicalEntityOrder: [String] = [
    // Aggregate roots
    EntityName.list,
    EntityName.task,
    EntityName.habit,
    EntityName.tag,
    EntityName.calendarSeriesCutover,
    EntityName.calendarEvent,
    EntityName.preference,
    EntityName.memory,
    EntityName.dailyReview,
    EntityName.currentFocus,
    EntityName.focusSchedule,
    // Edges
    EdgeName.taskTag,
    EdgeName.taskDependency,
    EdgeName.taskCalendarEventLink,
    EdgeName.habitCompletion,
    // Independent children
    EntityName.taskReminder,
    EntityName.taskChecklistItem,
    EntityName.habitReminderPolicy,
    // Permanent identity aliases. Their targets may be any supported aggregate,
    // so aliases are replayed only after every possible target kind.
    EntityName.entityRedirect,
  ]
}
