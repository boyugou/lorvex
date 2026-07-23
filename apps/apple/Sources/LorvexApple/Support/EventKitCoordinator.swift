import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore

/// Drives EventKit ↔ Lorvex two-way integration: tiered read into the local
/// `provider_calendar_events` mirror, and isolated write-back of
/// Lorvex-originated events into the dedicated Lorvex calendar (bound to a task
/// via `task_provider_event_links`).
///
/// All EventKit + core-write work runs off the main actor inside this actor.
/// It is inert unless both a real `EventKitAccessing` and an
/// `EventKitProviderServicing` core are present and the user toggle is enabled.
///
/// Tier redaction is enforced at INGEST via the pure `EventKitIngest.providerRows`
/// before the rows touch the mirror — never relied on at the read layer alone.
actor EventKitCoordinator {
  struct IngestReport: Sendable, Equatable {
    let ingestedCount: Int
  }

  private let access: any EventKitAccessing
  private var provider: any EventKitProviderServicing
  /// Reads the persisted `CalendarAiAccessMode` (busy-only default). Injected so
  /// it can come from the core's device-local state without a hard dependency here.
  private let loadAccessMode: @Sendable () async -> CalendarAiAccessMode
  /// Reads the persisted calendar include/exclude rules before each ingest.
  private let loadCalendarFilter: @Sendable () async -> EventKitCalendarFilter
  /// Whether the user has enabled the EventKit integration.
  private let isEnabled: @Sendable () async -> Bool

  init(
    access: any EventKitAccessing,
    provider: any EventKitProviderServicing,
    loadAccessMode: @escaping @Sendable () async -> CalendarAiAccessMode,
    loadCalendarFilter: @escaping @Sendable () async -> EventKitCalendarFilter = { .all },
    isEnabled: @escaping @Sendable () async -> Bool
  ) {
    self.access = access
    self.provider = provider
    self.loadAccessMode = loadAccessMode
    self.loadCalendarFilter = loadCalendarFilter
    self.isEnabled = isEnabled
  }

  /// Build a coordinator from an app `core` only when the backend supports the
  /// provider mirror; otherwise nil (the preview service does not conform).
  static func make(
    core: any LorvexCoreServicing,
    access: any EventKitAccessing,
    loadAccessMode: @escaping @Sendable () async -> CalendarAiAccessMode,
    loadCalendarFilter: @escaping @Sendable () async -> EventKitCalendarFilter = { .all },
    isEnabled: @escaping @Sendable () async -> Bool
  ) -> EventKitCoordinator? {
    guard let provider = core as? any EventKitProviderServicing else { return nil }
    return EventKitCoordinator(
      access: access, provider: provider,
      loadAccessMode: loadAccessMode,
      loadCalendarFilter: loadCalendarFilter,
      isEnabled: isEnabled)
  }

  /// Rebind the database-backed provider after the app switches core storage.
  /// The EventKit access object intentionally stays stable: it owns the live
  /// `EKEventStore` and its cached Lorvex-calendar identifier, while only the
  /// SQLite write target changes.
  func updateProvider(from core: any LorvexCoreServicing) {
    if let provider = core as? any EventKitProviderServicing {
      updateProvider(provider)
    }
  }

  func updateProvider(_ provider: any EventKitProviderServicing) {
    self.provider = provider
  }

  // MARK: - Tiered read

  /// Request system Calendar access directly. This is intentionally not gated by
  /// the EventKit sync toggle or AI access tier: those settings decide whether
  /// Lorvex mirrors calendars, while this method only asks macOS for permission.
  func requestAccess() async throws -> Bool {
    try await access.requestAccess()
  }

  func integrationEnabled() async -> Bool {
    await isEnabled()
  }

  func availableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard await isEnabled() else { return [] }
    return try await access.availableCalendars()
  }

  /// Writable target calendars for the event form's calendar picker. Empty when
  /// the integration is disabled — the write-back is skipped then, so there is
  /// nothing to target.
  func writableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard await isEnabled() else { return [] }
    return try await access.writableCalendars()
  }

  /// The calendar the mirror of `lorvexEventID` currently lives in, for
  /// preselecting the edit form's picker. Nil when the integration is disabled,
  /// the mirror is in the dedicated Lorvex calendar, or it can't be resolved.
  func lorvexEventCalendarID(lorvexEventID: String) async -> String? {
    guard await isEnabled() else { return nil }
    return await access.lorvexEventCalendarID(lorvexEventID: lorvexEventID)
  }

  /// Resolve the fine-grained origin calendar (title + account) of a mirrored
  /// system-calendar event for inspector display, from its timeline composite id
  /// (`"<kind>:<scope>:<key>"` as built by `SwiftLorvexCoreService.providerEvent`).
  /// Splits at most twice so a `:`-bearing event key survives intact. Inert (nil)
  /// when the integration is disabled or the id is not an EventKit provider event.
  func eventSource(forTimelineID timelineID: String, dayHint: String?) async -> EventKitEventSource? {
    guard await isEnabled() else { return nil }
    let parts = timelineID.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == ProviderKind.eventkit else { return nil }
    return await access.eventSource(forEventKey: String(parts[2]), dayHint: dayHint)
  }

  /// Fetch system-calendar events in `[from, to)`, map them through the
  /// access-tier redaction, and upsert into the local mirror. When the toggle
  /// is off, clears the mirror. When the tier is `off`, ingests nothing (and
  /// clears any prior mirror). Returns the count of mirrored rows.
  @discardableResult
  func ingest(
    from: Date,
    to: Date,
    windowStart: String? = nil,
    windowEnd: String? = nil,
    requestAccess: Bool = false
  ) async throws -> IngestReport {
    let signpost = LorvexSignpost.begin(.eventKitIngest)
    defer { LorvexSignpost.end(signpost) }
    guard await isEnabled() else {
      try provider.clearEventKitMirror()
      return IngestReport(ingestedCount: 0)
    }
    let mode = await loadAccessMode()
    guard mode.includesProvider else {
      // `off`: no occupancy mirrored. Drop any rows from a prior tier.
      try provider.clearEventKitMirror()
      return IngestReport(ingestedCount: 0)
    }
    if requestAccess {
      guard try await access.requestAccess() else {
        throw EventKitAccessError.readAccessDenied
      }
    } else if !access.isReadAuthorized() {
      // Do NOT clear the mirror here. This branch runs on incidental refreshes
      // (the EKEventStoreChanged observer, week navigation). Keep the last-good
      // mirror only for EventKit's known stale post-grant `notDetermined` read;
      // an explicit denied/restricted/write-only state must hide old provider
      // rows immediately so revoked calendar data does not remain visible.
      if access.readAuthorizationState() != .staleNotDeterminedGrant {
        try provider.clearEventKitMirror()
      }
      throw EventKitAccessError.readAccessDenied
    }
    let resolvedWindowStart = windowStart ?? Self.ymd(from)
    let resolvedWindowEnd = windowEnd ?? Self.ymd(to)
    let fetched = try await access.fetchEvents(
      start: from,
      end: to,
      windowEndDay: resolvedWindowEnd,
      calendarFilter: await loadCalendarFilter())
    let rows = EventKitIngest.providerRows(
      from: fetched, scope: SwiftLorvexCoreService.eventKitScope, accessMode: mode)
    let count = try provider.ingestEventKitEvents(
      rows, builtAtMode: mode,
      windowStart: resolvedWindowStart,
      windowEnd: resolvedWindowEnd)
    return IngestReport(ingestedCount: count)
  }

  private static func ymd(_ date: Date) -> String {
    LorvexDateFormatters.ymd.string(from: date)
  }

  // MARK: - Isolated write-back

  /// Write a Lorvex event into the calendar named by `target` (the dedicated
  /// Lorvex calendar by default) and bind it to a task. `existingKey` (when
  /// known from a prior link) updates in place.
  @discardableResult
  func writeBack(
    taskID: String?,
    existingKey: String?,
    lorvexEventID: String,
    title: String,
    start: Date,
    end: Date,
    isAllDay: Bool,
    location: String?,
    notes: String?,
    recurrence: String? = nil,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> String {
    try await writeBack(
      taskID: taskID, existingKey: existingKey, lorvexEventID: lorvexEventID,
      title: title, start: start, end: end, isAllDay: isAllDay, location: location,
      notesPatch: .replace(notes), recurrence: recurrence, target: target)
  }

  @discardableResult
  func writeBack(
    taskID: String?,
    existingKey: String?,
    lorvexEventID: String,
    title: String,
    start: Date,
    end: Date,
    isAllDay: Bool,
    location: String?,
    notesPatch: EventKitNotesPatch,
    recurrence: String? = nil,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> String {
    guard await isEnabled() else {
      throw EventKitAccessError.integrationDisabled
    }
    let result = try await access.upsertLorvexEvent(
      existingKey: existingKey, title: title, start: start, end: end,
      isAllDay: isAllDay, location: location, notesPatch: notesPatch, recurrence: recurrence,
      lorvexEventID: lorvexEventID, target: target)
    if let taskID {
      try provider.linkTaskToEventKitEvent(
        taskID: taskID, providerEventKey: result.providerEventKey)
    }
    return result.providerEventKey
  }

  /// Split an existing recurring mirror and write its replacement segment in
  /// one EventKit operation. The access layer fails closed when it cannot resolve
  /// the original occurrence, so callers cannot accidentally create a duplicate
  /// replacement without first truncating the original series.
  @discardableResult
  func replaceFutureWriteBack(
    originalLorvexEventID: String,
    occurrenceDate: Date,
    replacement: CalendarEventExport,
    replacementLorvexEventID: String,
    target: EventKitWriteTarget
  ) async throws -> String {
    guard await isEnabled() else {
      throw EventKitAccessError.integrationDisabled
    }
    let result = try await access.replaceFutureLorvexEventSeries(
      originalLorvexEventID: originalLorvexEventID,
      occurrenceDate: occurrenceDate,
      replacement: replacement,
      replacementLorvexEventID: replacementLorvexEventID,
      target: target)
    return result.providerEventKey
  }

  /// Delete the Lorvex-calendar event for a Lorvex item and drop the binding
  /// (when bound to a task). Resolves the EKEvent by the task's link row when
  /// `taskID` is given, else by the `lorvexEventID` notes marker.
  func removeWriteBack(taskID: String?, lorvexEventID: String) async throws {
    guard await isEnabled() else {
      throw EventKitAccessError.integrationDisabled
    }
    if let taskID, let key = try provider.eventKitLinksForTask(taskID: taskID).first?.providerEventKey {
      try await access.deleteLorvexEvent(providerEventKey: key)
      _ = try provider.unlinkTaskFromEventKitEvent(taskID: taskID, providerEventKey: key)
    } else {
      try await access.deleteLorvexEvent(lorvexEventID: lorvexEventID)
    }
  }

  /// Remove a single mirrored recurring occurrence from the dedicated Lorvex
  /// calendar. EventKit persists this as an EXDATE on the recurring event.
  func removeOccurrenceWriteBack(lorvexEventID: String, occurrenceDate: Date) async throws {
    guard await isEnabled() else {
      throw EventKitAccessError.integrationDisabled
    }
    try await access.removeLorvexEventOccurrence(
      lorvexEventID: lorvexEventID, occurrenceDate: occurrenceDate)
  }

  /// Mirror a durable Lorvex cutover by removing the corresponding EventKit
  /// occurrence and its future siblings with the provider's native span.
  func removeFutureWriteBack(lorvexEventID: String, occurrenceDate: Date) async throws {
    guard await isEnabled() else {
      throw EventKitAccessError.integrationDisabled
    }
    try await access.removeFutureLorvexEventSeries(
      lorvexEventID: lorvexEventID, occurrenceDate: occurrenceDate)
  }

  /// The bound EventKit event key for a task, if any.
  func eventKey(forTask taskID: String) throws -> String? {
    try provider.eventKitLinksForTask(taskID: taskID).first?.providerEventKey
  }
}
