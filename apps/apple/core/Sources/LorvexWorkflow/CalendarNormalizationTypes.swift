import Foundation
import LorvexDomain
import LorvexStore

// The input, output, and error value types of calendar-event normalization.
// The normalization logic itself lives in CalendarNormalization.swift.
// MARK: - Public types

/// Surface-agnostic Lorvex-native attendee input — the canonical shape every
/// surface translates its wire-level attendee struct into before feeding it to
/// ``CalendarEventCreate`` / ``CalendarEventUpdate``.
///
/// A lightweight annotation `{email?, name?}` pair: at least one field must be
/// non-empty, and there is no RSVP/PARTSTAT status. `email` is `""` when the
/// entry carries only a name. ``CalendarEventAttendees/serialize(_:)`` validates
/// and canonicalizes a list of these into the `calendar_events.attendees` column.
public struct CalendarAttendeeInput: Sendable, Equatable {
  public var email: String
  public var name: String?

  public init(email: String, name: String? = nil) {
    self.email = email
    self.name = name
  }
}

/// DST guard surfaced by calendar-event normalization. `ambiguous` cases
/// carry the wall-clock + IANA name so surfaces can render a diagnostic
/// alongside the persisted row.
public enum CalendarDstGuard: Sendable, Equatable {
  case ok
  case ambiguous(wallClock: String, timezone: String)
}

/// Errors raised by calendar-event normalization + the calendar_event
/// workflow operations. Surface adapters map this onto their typed error.
public enum CalendarEventOpError: Error, Equatable, CustomStringConvertible, LocalizedError {
  case validation(String)
  case store(StoreError)

  public var description: String {
    switch self {
    case .validation(let m): return m
    case .store(let e): return String(describing: e)
    }
  }

  /// Surfaced through `localizedDescription` (used by the MCP error bridge) so a
  /// failed calendar tool returns its real message instead of the opaque
  /// "CalendarEventOpError error 0" default.
  public var errorDescription: String? { description }

  /// Convert into a ``StoreError`` for code paths that need a uniform
  /// error type (e.g. a write step that surfaces failures as `StoreError`).
  func asStoreError() -> StoreError {
    switch self {
    case .validation(let m): return .validation(m)
    case .store(let s): return s
    }
  }
}

/// Inputs for ``CalendarNormalization/normalizeCalendarCreate(_:)``.
public struct CalendarCreateInput: Sendable, Equatable {
  public var title: String
  public var recurrence: String?
  public var timezone: String?
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool?
  public var description: String?
  public var location: String?
  public var url: String?
  public var color: String?
  public var eventType: CanonicalCalendarEventType?
  public var personName: String?

  public init(
    title: String, recurrence: String? = nil, timezone: String? = nil,
    startDate: String, startTime: String? = nil, endDate: String? = nil,
    endTime: String? = nil, allDay: Bool? = nil, description: String? = nil,
    location: String? = nil, url: String? = nil, color: String? = nil,
    eventType: CanonicalCalendarEventType? = nil, personName: String? = nil
  ) {
    self.title = title
    self.recurrence = recurrence
    self.timezone = timezone
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.description = description
    self.location = location
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
  }
}

public struct NormalizedCalendarCreate: Sendable, Equatable {
  public var title: String
  public var recurrence: String?
  public var timezone: String?
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool
  public var description: String?
  public var location: String?
  public var url: String?
  public var color: String?
  public var eventType: CanonicalCalendarEventType
  public var personName: String?
  public var dstGuard: CalendarDstGuard
}

/// Pre-mutation row read by ``CalendarNormalization/normalizeCalendarUpdate(_:existing:)``
/// so the patch logic can reconcile each `Patch<T>` against the existing
/// value before validating the prospective post-patch state.
public struct CalendarUpdateExisting: Sendable, Equatable {
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool
  public var timezone: String?
  /// Pre-mutation recurrence JSON. Read on a start_date re-anchor so
  /// ``CalendarNormalization/normalizeCalendarUpdate(_:existing:)`` can re-run
  /// create-time recurrence normalization against the new anchor. `nil` for a
  /// non-recurring event.
  public var recurrence: String?

  public init(
    startDate: String, startTime: String? = nil, endDate: String? = nil,
    endTime: String? = nil, allDay: Bool, timezone: String? = nil,
    recurrence: String? = nil
  ) {
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.timezone = timezone
    self.recurrence = recurrence
  }
}

public struct CalendarUpdateInput: Sendable, Equatable {
  public var title: String?
  public var recurrence: Patch<String>
  public var timezone: Patch<String>
  public var startDate: String?
  public var startTime: Patch<String>
  public var endDate: Patch<String>
  public var endTime: Patch<String>
  public var allDay: Bool?
  public var description: Patch<String>
  public var location: Patch<String>
  public var url: Patch<String>
  public var color: Patch<String>
  public var eventType: Patch<CanonicalCalendarEventType>
  public var personName: Patch<String>

  public init(
    title: String? = nil, recurrence: Patch<String> = .unset,
    timezone: Patch<String> = .unset, startDate: String? = nil,
    startTime: Patch<String> = .unset, endDate: Patch<String> = .unset,
    endTime: Patch<String> = .unset, allDay: Bool? = nil,
    description: Patch<String> = .unset, location: Patch<String> = .unset,
    url: Patch<String> = .unset, color: Patch<String> = .unset,
    eventType: Patch<CanonicalCalendarEventType> = .unset,
    personName: Patch<String> = .unset
  ) {
    self.title = title
    self.recurrence = recurrence
    self.timezone = timezone
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.description = description
    self.location = location
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
  }
}

/// Reconciled effective post-patch values, used by validation + the DST
/// guard so they see the actual prospective row, not the patch in isolation.
public struct EffectiveCalendarEventFields: Sendable, Equatable {
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool
  public var timezone: String?
}

public struct NormalizedCalendarUpdate: Sendable, Equatable {
  public var title: String?
  public var recurrence: Patch<String>
  public var timezone: Patch<String>
  public var startDate: String?
  public var startTime: Patch<String>
  public var endDate: Patch<String>
  public var endTime: Patch<String>
  public var allDay: Bool?
  public var description: Patch<String>
  public var location: Patch<String>
  public var url: Patch<String>
  public var color: Patch<String>
  public var eventType: Patch<CanonicalCalendarEventType>
  public var personName: Patch<String>
  public var effective: EffectiveCalendarEventFields
  public var dstGuard: CalendarDstGuard
}
