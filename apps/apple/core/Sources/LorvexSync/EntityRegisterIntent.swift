import Foundation
import LorvexDomain

/// Typed device-local provenance for independently versioned entity registers.
///
/// The persisted `register_intent` integer is interpreted only together with
/// the envelope's entity kind. This wrapper prevents calendar bits from being
/// accidentally replayed as task bits (or vice versa), while keeping the local
/// metadata compact and outside the sync wire contract.
public enum EntityRegisterIntent: Sendable, Equatable, Hashable {
  case none
  case calendar(CalendarEventRegisterIntent)
  case task(TaskRegisterIntent)

  public var rawValue: Int64 {
    switch normalized {
    case .none: return 0
    case .calendar(let intent): return intent.rawValue
    case .task(let intent): return intent.rawValue
    }
  }

  public var isEmpty: Bool {
    if case .none = normalized { return true }
    return false
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.normalized, rhs.normalized) {
    case (.none, .none): return true
    case (.calendar(let left), .calendar(let right)): return left == right
    case (.task(let left), .task(let right)): return left == right
    default: return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch normalized {
    case .none:
      hasher.combine(0)
    case .calendar(let intent):
      hasher.combine(1)
      hasher.combine(intent.rawValue)
    case .task(let intent):
      hasher.combine(2)
      hasher.combine(intent.rawValue)
    }
  }

  public static func inferredLocalMutation(
    entityType: EntityKind, from payload: JSONValue
  ) -> Self {
    switch entityType {
    case .calendarEvent:
      return .calendar(CalendarEventRegisterIntent.inferredLocalMutation(from: payload)).normalized
    case .task:
      return .task(TaskRegisterIntent.inferredLocalMutation(from: payload)).normalized
    default:
      return .none
    }
  }

  static func validatedStored(
    rawValue: Int64, entityType: EntityKind, operation: SyncOperation, payload: String
  ) throws -> Self {
    let value: Self
    if rawValue == 0 {
      value = .none
    } else {
      switch entityType {
      case .calendarEvent:
        let calendar = CalendarEventRegisterIntent(rawValue: rawValue)
        guard calendar.subtracting(.all).isEmpty else {
          throw EntityRegisterIntentError.invalidRawValue(rawValue)
        }
        value = .calendar(calendar)
      case .task:
        let task = TaskRegisterIntent(rawValue: rawValue)
        guard task.subtracting(.all).isEmpty else {
          throw EntityRegisterIntentError.invalidRawValue(rawValue)
        }
        value = .task(task)
      default:
        throw EntityRegisterIntentError.invalidEnvelope
      }
    }
    return try value.validated(
      entityType: entityType, operation: operation, payload: payload)
  }

  func validated(for envelope: SyncEnvelope) throws -> Self {
    try validated(
      entityType: envelope.entityType, operation: envelope.operation,
      payload: envelope.payload)
  }

  func retainingUnchangedRegisters(
    existingPayload: String, replacementPayload: String
  ) -> Self {
    switch normalized {
    case .none:
      return .none
    case .calendar(let intent):
      return .calendar(
        intent.retainingUnchangedRegisters(
          existingPayload: existingPayload, replacementPayload: replacementPayload)
      ).normalized
    case .task(let intent):
      return .task(
        intent.retainingUnchangedRegisters(
          existingPayload: existingPayload, replacementPayload: replacementPayload)
      ).normalized
    }
  }

  func union(_ other: Self) throws -> Self {
    switch (normalized, other.normalized) {
    case (.none, let value), (let value, .none):
      return value
    case (.calendar(let lhs), .calendar(let rhs)):
      return .calendar(lhs.union(rhs)).normalized
    case (.task(let lhs), .task(let rhs)):
      return .task(lhs.union(rhs)).normalized
    default:
      throw EntityRegisterIntentError.mismatchedEntityKinds
    }
  }

  private var normalized: Self {
    switch self {
    case .calendar(let intent) where intent.isEmpty: return .none
    case .task(let intent) where intent.isEmpty: return .none
    default: return self
    }
  }

  private func validated(
    entityType: EntityKind, operation: SyncOperation, payload: String
  ) throws -> Self {
    switch normalized {
    case .none:
      return .none
    case .calendar(let intent):
      guard intent.subtracting(.all).isEmpty else {
        throw EntityRegisterIntentError.invalidRawValue(intent.rawValue)
      }
      guard entityType == .calendarEvent, operation == .upsert,
        CalendarEventRegisterIntent.isBasePayload(payload)
      else {
        throw EntityRegisterIntentError.invalidEnvelope
      }
      return .calendar(intent)
    case .task(let intent):
      guard intent.subtracting(.all).isEmpty else {
        throw EntityRegisterIntentError.invalidRawValue(intent.rawValue)
      }
      guard entityType == .task, operation == .upsert,
        case .object? = JSONValue.parse(payload)
      else {
        throw EntityRegisterIntentError.invalidEnvelope
      }
      return .task(intent)
    }
  }
}

enum EntityRegisterIntentError: Error, Sendable, Equatable {
  case invalidRawValue(Int64)
  case invalidEnvelope
  case mismatchedEntityKinds
}
