import Foundation

/// Provenance for an event block inside a persisted focus schedule.
///
/// The source belongs to the schedule aggregate itself: it must not be inferred
/// from whether a related calendar row happens to be present on this device.
/// Canonical blocks reference a synced Lorvex calendar event; provider blocks
/// originate in a device-local calendar mirror; freeform blocks are authored
/// directly in the schedule and have no calendar identity.
public enum FocusScheduleEventSource: String, Codable, Sendable, Hashable, CaseIterable {
  case canonical
  case provider
  case freeform

  public static func parse(_ raw: String) -> FocusScheduleEventSource? {
    Self(rawValue: raw)
  }
}

/// Typed `focus_schedule_blocks.block_type` enum.
///
/// Every reader / writer of `focus_schedule_blocks.block_type` routes through
/// this closed enum so dispatch stays exhaustive across the MCP host, platform
/// surfaces, the sync apply pipeline (`ApplyDayScoped` validates each inbound
/// value via ``parse(_:)``), and the storage layer. The column also
/// carries a SQL `CHECK (block_type IN ('task','buffer','event'))`, so an
/// unvalidated future value would raise `SQLITE_CONSTRAINT` on write; the
/// appliers therefore reject an unknown value as a single-envelope drop rather
/// than letting the constraint failure wedge the whole inbound batch.
public enum FocusBlockType: Sendable, Hashable, CaseIterable, CustomStringConvertible {
  /// User-authored work block tied to a `task_id` (FK into `tasks`).
  case task
  /// Break / transition slot between work blocks. No `task_id`.
  case buffer
  /// Calendar event imported from a native subscription. No `task_id`.
  case event

  /// Wire form (matches the historical SQL bind values).
  public var asString: String {
    switch self {
    case .task: return "task"
    case .buffer: return "buffer"
    case .event: return "event"
    }
  }

  public var description: String { asString }

  /// Strict parse — returns `nil` for any value not in the closed set.
  /// Callers persisting from external input should treat `nil` as a
  /// rejection (validation error / drop the row), not silently coerce to
  /// a default.
  public static func parse(_ raw: String) -> FocusBlockType? {
    switch raw {
    case "task": return .task
    case "buffer": return .buffer
    case "event": return .event
    default: return nil
    }
  }

  /// `true` when the block requires a non-empty `task_id` to be persisted.
  public var requiresTaskId: Bool {
    self == .task
  }
}
