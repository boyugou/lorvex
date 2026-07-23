import Foundation

/// A one-time notice that the on-disk database had to be quarantined when it was
/// opened: an unreadable or schema-incompatible file was renamed aside and a
/// fresh empty database created in its place. The previous file is preserved at
/// `backupPath`, never deleted.
///
/// Surfaces read this once after the first load and present a dismissible "your
/// previous data was set aside" notice, so a quarantine is never silent.
public struct DatabaseRecoveryNotice: Sendable, Equatable {
  /// Filesystem path where the quarantined database (and any `-wal`/`-shm`
  /// sidecars) were moved. The data is recoverable here.
  public let backupPath: String
  /// Human-readable reason the original could not be opened.
  public let reason: String

  public init(backupPath: String, reason: String) {
    self.backupPath = backupPath
    self.reason = reason
  }
}

public protocol LorvexCoreServicing: LorvexAIFocusScheduleReading, LorvexCalendarServicing,
  LorvexDataExportServicing,
  LorvexFocusPlanningServicing,
  LorvexHabitServicing, LorvexListTagServicing,
  LorvexMemoryServicing, LorvexReviewServicing, LorvexSystemServicing,
  LorvexTaskServicing, Sendable
{
  /// A pending database-quarantine notice from the on-disk store's open, or
  /// `nil` on a clean open and for backends without on-disk recovery (in-memory
  /// / preview). Read after the first load; see `DatabaseRecoveryNotice`.
  var databaseRecoveryNotice: DatabaseRecoveryNotice? { get }
}

public extension LorvexCoreServicing {
  /// Backends with no on-disk quarantine path report no notice.
  var databaseRecoveryNotice: DatabaseRecoveryNotice? { nil }
}

/// The kind of stored entity a ``LorvexCoreError/notFound(entity:id:)`` lookup
/// missed. ``displayName`` is the exact English noun the core interpolates into
/// the not-found sentence, so callers branch on the case while the rendered
/// message stays a single fixed wording per entity.
public enum LorvexEntityKind: Sendable, Equatable {
  case list
  case habit
  case calendarEvent
  case calendarSeries
  case tag
  case memory

  /// The capitalized English noun used in user-facing wording (e.g. "Calendar
  /// event"), interpolated into ``LorvexCoreError``'s not-found sentence. For
  /// ``tag`` and ``memory`` the accompanying `id` is the human name/key looked
  /// up (not a UUID), yielding e.g. "Tag 'urgent' not found."
  public var displayName: String {
    switch self {
    case .list: "List"
    case .habit: "Habit"
    case .calendarEvent: "Calendar event"
    case .calendarSeries: "Calendar series"
    case .tag: "Tag"
    case .memory: "Memory"
    }
  }
}

public enum LorvexCoreError: LocalizedError, Equatable {
  case taskNotFound
  case emptyTitle

  /// A lookup for `entity` with `id` missed — the row does not exist (a genuine
  /// not-found, distinct from an internal "missing after mutation" invariant,
  /// which stays an ``unsupportedOperation``). `id` is the raw stored identifier
  /// (a UUIDv7 for the current entities), carried for the diagnostics ring;
  /// surfaces present this case with their own not-found copy rather than reading
  /// `id`. ``errorDescription`` is the sentence "`<Noun>` '`<id>`' not found."; that
  /// exact wording is load-bearing — message-matching consumers (MCP envelope
  /// text, `error_logs`, the alert-layer string classifier) key off it.
  case notFound(entity: LorvexEntityKind, id: String?)

  /// A user-appropriate validation failure whose `message` is already a clean,
  /// human sentence with no raw identifier or internal marker (e.g. "Mood must be
  /// between 1 and 5."). `field` names the offending input when known, for callers
  /// that want to branch or annotate; the human copy is `message`, which
  /// ``errorDescription`` returns verbatim (the alert layer shows it as-is).
  case validation(field: String?, message: String)

  /// A uniqueness collision: the requested change would give an entity a
  /// name/key that already belongs to a *different* one (renaming a tag or
  /// memory onto an existing name). `message` is a clean, user-appropriate
  /// sentence that names the collision and the recommended action ("… already
  /// exists. Re-tag those tasks onto it instead …"), with no raw identifier;
  /// ``errorDescription`` returns it verbatim and surfaces show it as-is, like a
  /// ``validation`` message. Distinct from ``validation`` (a malformed input) and
  /// from an internal post-mutation ``unsupportedOperation`` invariant; maps to
  /// the `conflict` MCP wire code, matching `StoreError.staleVersion`.
  case conflict(message: String)

  case unsupportedOperation(String)

  /// The pure-Swift core returned a row that violates the app's decode
  /// contract: a schema-required field is missing or mistyped, a closed-enum
  /// column holds an unknown value, or a nested array element is malformed.
  /// `path` is the dotted field path that pinpoints the offending value (e.g.
  /// `task.checklist_items[2].id`, `task.status`, `calendar_event.start_date`);
  /// `reason` describes the violation.
  ///
  /// This is an internal-consistency break at the in-process core→app boundary
  /// (same process, same schema), so it is surfaced loudly rather than papered
  /// over with a fabricated placeholder (a random UUID the UI would act on
  /// against a nonexistent DB id, a terminal task shown as open, …).
  case malformedCoreData(path: String, reason: String)

  public var errorDescription: String? {
    switch self {
    case .taskNotFound: "The task could not be found."
    case .emptyTitle: "A task title is required."
    case let .notFound(entity, id):
      if let id { "\(entity.displayName) '\(id)' not found." } else { "\(entity.displayName) not found." }
    case .validation(_, let message): message
    case .conflict(let message): message
    case .unsupportedOperation(let message): message
    case let .malformedCoreData(path, reason): "Malformed data at \(path): \(reason)."
    }
  }
}
