/// Sentinel value for the schema-seeded universal inbox list. Predates the
/// UUID convention and remains a non-UUID string forever; the storage and
/// sync layer treats it as a stable opaque identifier.
public let inboxSentinel: String = "inbox"

/// Typed entity identifier wrappers.
///
/// Every Lorvex entity kind is identified by a UUIDv7 string at the storage
/// and wire layer. These wrappers enforce type discipline at the API boundary
/// so swapping two distinct id kinds at a call site is a compile error rather
/// than a silent wrong-row update. Each stays a thin wrapper around the
/// canonical UUIDv7 string:
///
/// - `Codable` encodes/decodes as a bare string (single-value container), so
///   JSON / sync envelopes / MCP arg shapes keep encoding the id as a bare
///   string.
/// - ``parse(_:)`` reuses ``EntityID/parseIDWithSentinel(_:field:sentinel:)``
///   so trust-boundary surfaces keep their unified trim / sentinel / UUID-shape
///   rules.
/// - ``new()`` mints a fresh UUIDv7 via ``EntityID/newEntityIDString()``.
public protocol TypedEntityID: Sendable, Hashable, Codable, CustomStringConvertible {
  /// Field label embedded in `ValidationError.invalidFormat { field, .. }`.
  static var fieldLabel: String { get }

  /// Single non-UUID sentinel this kind accepts, or `nil` if it always
  /// requires a UUID-shaped value.
  static var sentinel: String? { get }

  /// The canonical string representation.
  var rawValue: String { get }

  /// Construct from an already-validated string without re-running the
  /// trust-boundary parser.
  init(trusted value: String)
}

extension TypedEntityID {
  public static var sentinel: String? { nil }

  /// Mint a new id from a fresh UUIDv7.
  public static func new() -> Self {
    Self(trusted: EntityID.newEntityIDString())
  }

  /// Parse an untrusted string at a trust boundary. Trims surrounding
  /// whitespace, accepts the configured sentinel (if any), and otherwise
  /// enforces UUID shape. The returned `ValidationError` carries
  /// ``fieldLabel``.
  public static func parse(_ value: String) -> Result<Self, ValidationError> {
    EntityID.parseIDWithSentinel(value, field: fieldLabel, sentinel: sentinel)
      .map { Self(trusted: $0) }
  }

  /// Borrow the canonical string representation.
  public var asString: String { rawValue }

  public var description: String { rawValue }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(trusted: try container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

// One id struct per entity kind. Field labels match the schema column names
// and the parameter names used across the repositories.

public struct TaskId: TypedEntityID {
  public static let fieldLabel = "task_id"
  public let rawValue: String
  public init(trusted value: String) { self.rawValue = value }
}

public struct ListId: TypedEntityID {
  public static let fieldLabel = "list_id"
  public static let sentinel: String? = ListId.inboxSentinel
  public let rawValue: String
  public init(trusted value: String) { self.rawValue = value }

  /// Sentinel value for the schema-seeded universal inbox list. Predates the
  /// UUID convention and remains a non-UUID string forever.
  public static let inboxSentinel = LorvexDomain.inboxSentinel

  /// The inbox sentinel as a typed `ListId`.
  public static func inbox() -> ListId {
    ListId(trusted: inboxSentinel)
  }
}

public struct EventId: TypedEntityID {
  public static let fieldLabel = "event_id"
  public let rawValue: String
  public init(trusted value: String) { self.rawValue = value }
}

public struct TagId: TypedEntityID {
  public static let fieldLabel = "tag_id"
  public let rawValue: String
  public init(trusted value: String) { self.rawValue = value }
}

public struct ChecklistItemId: TypedEntityID {
  public static let fieldLabel = "checklist_item_id"
  public let rawValue: String
  public init(trusted value: String) { self.rawValue = value }
}

// MARK: - Composite edge ids

/// Composite id for a `task_tags` edge row.
///
/// Wire form is `"<task_id>:<tag_id>"`. Construction goes through
/// ``init(taskId:tagId:)`` so a bare interpolation cannot silently emit a
/// malformed id.
public struct TaskTagEdgeId: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(taskId: TaskId, tagId: TagId) {
    self.rawValue = "\(taskId.asString):\(tagId.asString)"
  }

  public var asString: String { rawValue }
  public var description: String { rawValue }
}

/// Composite id for a `task_dependencies` edge row.
///
/// Wire form is `"<task_id>:<depends_on_task_id>"`. Same construction contract
/// as ``TaskTagEdgeId``.
public struct TaskDependencyEdgeId: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// `taskId` is the row that depends on `dependsOnTaskId`.
  public init(taskId: TaskId, dependsOnTaskId: TaskId) {
    self.rawValue = "\(taskId.asString):\(dependsOnTaskId.asString)"
  }

  public var asString: String { rawValue }
  public var description: String { rawValue }
}
