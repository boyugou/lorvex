@preconcurrency import EventKit
import Foundation
import LorvexCore
import LorvexStore

/// Result of writing a Lorvex-originated event into the dedicated Lorvex
/// EventKit calendar. `providerEventKey` is the stable EKEvent identity to bind
/// in `task_provider_event_links` and to resolve the event on later edit/delete.
struct EventKitWriteResult: Sendable, Equatable {
  let providerEventKey: String
}

/// Three-state notes patch for EventKit write-back. A temporal/recurrence-only
/// rewrite must preserve user text already present in Apple Calendar, while a
/// full form save must distinguish an explicit clear from a replacement value.
enum EventKitNotesPatch: Sendable, Equatable {
  case preserve
  case replace(String?)
}

/// The origin calendar of a system-calendar event, for fine-grained display in
/// the event inspector: the calendar's own title plus the account/source it
/// belongs to (e.g. title "Holidays in United States", account
/// "iCloud"). Mirrors the identity the calendar-filter
/// settings list shows, which the collapsed `provider_calendar_events` mirror
/// (one device-wide scope) cannot carry — so it is resolved live from EventKit
/// at display time rather than read from the timeline cache.
struct EventKitEventSource: Sendable, Equatable {
  let calendarTitle: String
  /// The owning account / source title (`EKSource.title`), nil when EventKit
  /// reports no distinct source or it equals the calendar title.
  let accountTitle: String?
}

/// Which EventKit calendar a Lorvex write-back lands in.
///
/// Lorvex-authored events default to a dedicated "Lorvex" calendar, but the
/// event form lets the user file an event into any writable calendar. The
/// choice lives only in EventKit (the canonical core event has no calendar
/// column), so the write path carries it here.
enum EventKitWriteTarget: Sendable, Equatable {
  /// The dedicated "Lorvex" calendar, created lazily on first use — the default.
  case lorvexDefault
  /// A specific writable calendar the user chose, by `calendarIdentifier`.
  /// Falls back to the Lorvex calendar when the id no longer resolves to a
  /// writable calendar.
  case calendar(id: String)
  /// Leave a reused event in whatever calendar it already occupies; a brand-new
  /// event still lands in the Lorvex calendar. Used by write-backs that only
  /// touch the temporal axis (drag-reschedule) so they never yank an event the
  /// user filed into a specific calendar back to the default.
  case keepExisting
}

enum EventKitReadAuthorizationState: Sendable, Equatable {
  /// EventKit currently reports read access.
  case authorized
  /// The app has a persisted successful grant, but EventKit is still returning
  /// `notDetermined` in this process. Keep the last-good mirror for this one
  /// incidental refresh; an explicit denied/write-only state is never mapped
  /// here.
  case staleNotDeterminedGrant
  /// EventKit does not currently permit reads.
  case unavailable

  var canRead: Bool {
    switch self {
    case .authorized, .staleNotDeterminedGrant: true
    case .unavailable: false
    }
  }
}

/// Protocol seam over EventKit for the tiered-read / isolated-write calendar
/// integration. The real implementation (`LiveEventKitAccess`) wraps an
/// `EKEventStore`; tests inject a fake.
///
/// Reads fetch system-calendar events as platform-neutral
/// ``EventKitFetchedEvent`` (the date/time fields are pre-rendered to canonical
/// wire forms) so the tier-redaction mapping (`EventKitIngest`) stays a pure,
/// testable function. Writes are isolated to a dedicated "Lorvex" calendar that
/// is created on first use — never the user's personal calendars.
protocol EventKitAccessing: Sendable {
  /// Request the access level needed for the integration. Returns whether the
  /// resulting authorization permits reading events.
  func requestAccess() async throws -> Bool

  /// Whether the current process authorization permits reading events, without
  /// prompting.
  func isReadAuthorized() -> Bool

  /// Detailed non-prompting read authorization state. Used to distinguish a
  /// stale post-grant `notDetermined` read from a real revoked/denied/write-only
  /// state, so Lorvex can avoid leaking old provider rows after revocation.
  func readAuthorizationState() -> EventKitReadAuthorizationState

  /// List readable EventKit calendars for user-facing include/exclude settings.
  func availableCalendars() async throws -> [EventKitCalendarDescriptor]

  /// List the calendars a Lorvex event can be written into: those permitting
  /// content modifications, each carrying its color, and excluding the dedicated
  /// "Lorvex" calendar (represented in the picker by the default option). Backs
  /// the event form's calendar picker.
  func writableCalendars() async throws -> [EventKitCalendarDescriptor]

  /// The `calendarIdentifier` of the calendar the Lorvex event's mirror
  /// currently lives in, so the edit form's picker can preselect it. Returns
  /// `nil` when the mirror is in the dedicated Lorvex calendar (the picker's
  /// default), when the event has no resolvable mirror, when its calendar is no
  /// longer writable, or when read access is not granted — never throws.
  func lorvexEventCalendarID(lorvexEventID: String) async -> String?

  /// Resolve the origin calendar (title + account) of a system-calendar event by
  /// its stable key (external or event identifier), for inspector display.
  /// `dayHint` (`yyyy-MM-dd`) narrows the search window when the key is not a
  /// direct local identifier. Returns nil when the event can't be found
  /// (deleted/moved) or read access is not granted — never throws.
  func eventSource(forEventKey key: String, dayHint: String?) async -> EventKitEventSource?

  /// Fetch system-calendar events overlapping `[start, end]` across all
  /// calendars, mapped to the neutral ingest shape. `windowEndDay` is the
  /// inclusive product-day label represented by the absolute interval; it is
  /// carried explicitly because formatting `end` in the device timezone can
  /// name a different day. Runs off the main actor.
  func fetchEvents(
    start: Date, end: Date, windowEndDay: String,
    calendarFilter: EventKitCalendarFilter
  ) async throws -> [EventKitFetchedEvent]

  /// Create-or-update the EKEvent for a Lorvex item in the calendar named by
  /// `target`. When an existing Lorvex-authored mirror resolves, it is updated
  /// in place (and moved to `target` when that names a different calendar);
  /// otherwise a new event is created. Updating an existing recurring mirror is a
  /// whole-series edit — it rewrites every occurrence via `EKSpan.futureEvents`
  /// on the series' first occurrence, never detaching a single one. Returns the
  /// stable provider event key.
  func upsertLorvexEvent(
    existingKey: String?,
    title: String,
    start: Date,
    end: Date,
    isAllDay: Bool,
    location: String?,
    notesPatch: EventKitNotesPatch,
    recurrence: String?,
    lorvexEventID: String,
    target: EventKitWriteTarget
  ) async throws -> EventKitWriteResult

  /// Atomically split a mirrored recurring series at `occurrenceDate` and turn
  /// the current-and-future segment into `replacement`. When the original
  /// mirror exists, implementations must mutate that occurrence and persist it
  /// with one `.futureEvents` save; they must not create the replacement before
  /// truncating the original series. Resolution is deliberately fail-closed:
  /// when the original occurrence cannot be proven, throw without creating,
  /// updating, or removing any EventKit event.
  func replaceFutureLorvexEventSeries(
    originalLorvexEventID: String,
    occurrenceDate: Date,
    replacement: CalendarEventExport,
    replacementLorvexEventID: String,
    target: EventKitWriteTarget
  ) async throws -> EventKitWriteResult

  /// Delete the Lorvex-calendar event identified by `providerEventKey`. A
  /// recurring mirror deletes the entire series (`EKSpan.futureEvents` on its
  /// first occurrence), not just the resolved occurrence. A no-op when the event
  /// is absent.
  func deleteLorvexEvent(providerEventKey: String) async throws

  /// Delete the Lorvex-calendar event whose notes carry the marker for
  /// `lorvexEventID` (used when no provider key was cached). A recurring mirror
  /// deletes the entire series. No-op when absent.
  func deleteLorvexEvent(lorvexEventID: String) async throws

  /// Remove one occurrence of the mirrored recurring Lorvex event by writing an
  /// EventKit `.thisEvent` exception. This is the single-occurrence counterpart
  /// to `deleteLorvexEvent`, which removes the whole series. No-op when the
  /// occurrence is absent.
  func removeLorvexEventOccurrence(lorvexEventID: String, occurrenceDate: Date) async throws

  /// Remove the addressed occurrence and every later occurrence from a
  /// recurring mirror with one native `EKSpan.futureEvents` operation. This is
  /// the EventKit adapter for Lorvex's durable `this_and_following` cutover;
  /// provider-side truncation is never written back into Lorvex recurrence.
  func removeFutureLorvexEventSeries(
    lorvexEventID: String, occurrenceDate: Date
  ) async throws
}

extension EventKitAccessing {
  /// Convenience for direct callers that are replacing the notes field. `nil`
  /// is an explicit clear; preservation uses the typed `notesPatch` entrypoint.
  func upsertLorvexEvent(
    existingKey: String?,
    title: String,
    start: Date,
    end: Date,
    isAllDay: Bool,
    location: String?,
    notes: String?,
    recurrence: String?,
    lorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    try await upsertLorvexEvent(
      existingKey: existingKey, title: title, start: start, end: end,
      isAllDay: isAllDay, location: location, notesPatch: .replace(notes),
      recurrence: recurrence, lorvexEventID: lorvexEventID, target: target)
  }
}

/// Errors surfaced by the EventKit access layer.
enum EventKitAccessError: LocalizedError, Equatable, Sendable {
  case readAccessDenied
  case writeAccessDenied
  case noWritableSource
  case integrationDisabled
  case originalMirrorOccurrenceUnresolved(eventID: String)

  var errorDescription: String? {
    switch self {
    case .readAccessDenied: "Calendar read access denied."
    case .writeAccessDenied: "Calendar write access denied."
    case .noWritableSource: "No writable calendar source is available for the Lorvex calendar."
    case .integrationDisabled: "Calendar integration is disabled."
    case .originalMirrorOccurrenceUnresolved(let eventID):
      "The original Calendar mirror occurrence for '\(eventID)' could not be resolved. No replacement was created."
    }
  }
}
