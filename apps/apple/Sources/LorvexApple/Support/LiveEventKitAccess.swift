import AppKit
@preconcurrency import EventKit
import Foundation
import LorvexCore
import LorvexStore

/// `EventKitAccessing` over a real `EKEventStore` (or any `EventKitEventStoring`
/// fake in tests).
///
/// All EKEventStore work runs inside the actor, off the main actor. The
/// dedicated Lorvex calendar is created lazily on first write; its
/// `calendarIdentifier` is cached through the injected `loadCalendarID` /
/// `saveCalendarID` closures so it is not re-searched every call.
actor LiveEventKitAccess: EventKitAccessing {
  static let lorvexCalendarTitle = "Lorvex"

  private let store: any EventKitEventStoring
  private let loadCalendarID: @Sendable () async -> String?
  private let saveCalendarID: @Sendable (String) async -> Void
  private let authorizationStatusProvider: @Sendable () -> EKAuthorizationStatus
  private let readAuthorizationProvider: @Sendable () -> Bool
  /// Persisted "Lorvex has been granted calendar read access" latch. EKEventKit's
  /// static `authorizationStatus` can keep returning a stale `notDetermined` for
  /// the rest of a session after an in-app grant; the latch records the grant so
  /// reads don't regress to "denied" mid-session (it is overridden only by a
  /// *real* `denied`/`restricted`, never by `notDetermined`).
  private let loadConfirmedReadAccess: @Sendable () -> Bool
  private let saveConfirmedReadAccess: @Sendable (Bool) -> Void

  init(
    store: any EventKitEventStoring = EKEventStore(),
    loadCalendarID: @escaping @Sendable () async -> String? = { nil },
    saveCalendarID: @escaping @Sendable (String) async -> Void = { _ in },
    authorizationStatusProvider: @escaping @Sendable () -> EKAuthorizationStatus = {
      EKEventStore.authorizationStatus(for: .event)
    },
    readAuthorizationProvider: @escaping @Sendable () -> Bool = {
      switch EKEventStore.authorizationStatus(for: .event) {
      case .fullAccess: true
      default: false
      }
    },
    loadConfirmedReadAccess: @escaping @Sendable () -> Bool = { false },
    saveConfirmedReadAccess: @escaping @Sendable (Bool) -> Void = { _ in }
  ) {
    self.store = store
    self.loadCalendarID = loadCalendarID
    self.saveCalendarID = saveCalendarID
    self.authorizationStatusProvider = authorizationStatusProvider
    self.readAuthorizationProvider = readAuthorizationProvider
    self.loadConfirmedReadAccess = loadConfirmedReadAccess
    self.saveConfirmedReadAccess = saveConfirmedReadAccess
  }

  func requestAccess() async throws -> Bool {
    if isReadAuthorized() {
      return true
    }
    switch authorizationStatusProvider() {
    case .notDetermined:
      let granted = try await store.requestFullAccessToEvents()
      if granted {
        // Latch the grant and refresh the store: the instance created at launch
        // (before the grant) otherwise keeps reading an empty/denied snapshot
        // until the app relaunches.
        saveConfirmedReadAccess(true)
        store.reset()
      }
      return granted
    case .fullAccess:
      saveConfirmedReadAccess(true)
      return true
    case .denied, .restricted, .writeOnly:
      return false
    @unknown default:
      return false
    }
  }

  nonisolated func isReadAuthorized() -> Bool {
    readAuthorizationState().canRead
  }

  nonisolated func readAuthorizationState() -> EventKitReadAuthorizationState {
    if readAuthorizationProvider() {
      saveConfirmedReadAccess(true)
      return .authorized
    }
    // Not directly authorized: distinguish a *stale* `notDetermined` (trust the
    // grant latch) from a genuine `denied`/`restricted`/write-only (respect it).
    switch authorizationStatusProvider() {
    case .denied, .restricted, .writeOnly:
      return .unavailable
    case .fullAccess:
      saveConfirmedReadAccess(true)
      return .authorized
    case .notDetermined where loadConfirmedReadAccess():
      return .staleNotDeterminedGrant
    default:
      return .unavailable
    }
  }

  func availableCalendars() async throws -> [EventKitCalendarDescriptor] {
    try await calendarDescriptors(includeColor: false) { calendar, lorvexID in
      calendar.calendarIdentifier != lorvexID && !calendar.calendarIdentifier.isEmpty
    }
  }

  func writableCalendars() async throws -> [EventKitCalendarDescriptor] {
    try await calendarDescriptors(includeColor: true) { calendar, lorvexID in
      calendar.allowsContentModifications
        && !calendar.calendarIdentifier.isEmpty
        && calendar.calendarIdentifier != lorvexID
    }
  }

  /// Map the readable EKCalendars passing `include` to sorted descriptors; the
  /// cached dedicated-calendar id reaches the predicate so both lists exclude
  /// it. `includeColor` fills the picker's dot color; the settings list omits it.
  private func calendarDescriptors(
    includeColor: Bool,
    include: (EKCalendar, String?) -> Bool
  ) async throws -> [EventKitCalendarDescriptor] {
    guard isReadAuthorized() else {
      throw EventKitAccessError.readAccessDenied
    }
    let lorvexID = await loadCalendarID()
    return store.eventCalendars()
      .filter { include($0, lorvexID) }
      .map { calendar in
        let sourceTitle = calendar.source?.title
        return EventKitCalendarDescriptor(
          id: calendar.calendarIdentifier,
          title: calendar.title.isEmpty
            ? String(localized: "calendar.picker.untitled", defaultValue: "Untitled Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
            : calendar.title,
          sourceTitle: sourceTitle?.isEmpty == false ? sourceTitle : nil,
          colorHex: includeColor ? Self.hexString(from: calendar.cgColor) : nil)
      }
      .sorted {
        let lhs = (($0.sourceTitle ?? ""), $0.title, $0.id)
        let rhs = (($1.sourceTitle ?? ""), $1.title, $1.id)
        return lhs < rhs
      }
  }

  func lorvexEventCalendarID(lorvexEventID: String) async -> String? {
    guard isReadAuthorized() else { return nil }
    guard let calendar = resolveLorvexEvent(key: nil, lorvexID: lorvexEventID)?.calendar else {
      return nil
    }
    // A mirror in the dedicated Lorvex calendar maps to the picker's nil default.
    if let lorvexID = await loadCalendarID(), calendar.calendarIdentifier == lorvexID {
      return nil
    }
    guard calendar.allowsContentModifications else { return nil }
    return calendar.calendarIdentifier
  }

  func fetchEvents(
    start: Date, end: Date, windowEndDay: String,
    calendarFilter: EventKitCalendarFilter = .all
  ) async throws -> [EventKitFetchedEvent] {
    guard isReadAuthorized() else {
      throw EventKitAccessError.readAccessDenied
    }
    // Chunk a wide range into <=4-year windows: EventKit rejects predicates
    // spanning more than four years and a single huge predicate is slow.
    var occurrences: [EventKitOccurrence] = []
    let lorvexID = await loadCalendarID()
    var windowStart = start
    let chunk: TimeInterval = 4 * 365 * 24 * 3600
    while windowStart < end {
      let windowEnd = min(windowStart.addingTimeInterval(chunk), end)
      let predicate = store.predicateForEvents(
        withStart: windowStart, end: windowEnd, calendars: nil)
      for ekEvent in store.events(matching: predicate) {
        // Never re-ingest events Lorvex itself wrote. The calendar-id match is
        // the fast path when the local Lorvex calendar id is known, but it's nil
        // on a second Mac where the Lorvex calendar synced down via iCloud (or
        // after lost defaults) — exactly when re-ingestion would mirror every
        // Lorvex event as a duplicate. Fall back to the `lorvex-event-id:` notes
        // marker every Lorvex-authored event carries.
        if let lorvexID, ekEvent.calendar?.calendarIdentifier == lorvexID { continue }
        if ekEvent.notes?.contains(lorvexCalendarEventPrefix) == true { continue }
        guard calendarFilter.allows(calendarID: ekEvent.calendar?.calendarIdentifier) else {
          continue
        }
        occurrences.append(
          EventKitOccurrence(
            event: Self.fetchedEvent(from: ekEvent),
            isDetached: ekEvent.isDetached,
            occurrenceYmd: ekEvent.occurrenceDate.map {
              Self.ymdString(from: $0, timeZone: ekEvent.timeZone ?? .current)
            }))
      }
      windowStart = windowEnd
    }
    // Collapse the one-EKEvent-per-occurrence enumeration into master rows with
    // recurrence exceptions plus standalone rows for moved occurrences, so
    // moved/cancelled occurrences render correctly (see EventKitSeriesAssembly).
    return EventKitSeriesAssembly.assemble(
      occurrences, windowEndYmd: windowEndDay)
  }

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
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    let marker = "\(lorvexCalendarEventPrefix)\(lorvexEventID)"
    // Reuse an existing mirror only when it carries the Lorvex marker or, for the
    // by-key path, already sits in the target — never hijack an unrelated event.
    let reused: EKEvent? = {
      guard let found = resolveLorvexEvent(key: existingKey, lorvexID: lorvexEventID) else {
        return nil
      }
      if found.notes?.contains(marker) == true { return found }
      if case .calendar(let id) = target, found.calendar?.calendarIdentifier == id {
        return found
      }
      return nil
    }()
    // Editing an existing recurring mirror is a whole-series edit: rewrite the
    // series' first occurrence with `.futureEvents`. EventKit rejects
    // `.thisEvent` once recurrence rules change, and `.thisEvent` would
    // otherwise detach a single occurrence; `.futureEvents` from the first
    // occurrence rewrites every occurrence. A new event, or reuse of a
    // non-recurring one, saves as itself with `.thisEvent`.
    let editingSeries = reused?.hasRecurrenceRules == true
    let writeEvent = reused.map { editingSeries ? seriesMaster(for: $0) : $0 }
    let calendar = try await resolveWriteCalendar(target, reusing: writeEvent)
    let ekEvent = writeEvent ?? store.makeEvent()
    ekEvent.title = title
    ekEvent.startDate = start
    ekEvent.endDate = end
    ekEvent.isAllDay = isAllDay
    ekEvent.location = location
    let userNotes: String?
    switch notesPatch {
    case .preserve:
      userNotes = Self.userNotes(
        fromMarkedNotes: writeEvent?.notes, lorvexID: lorvexEventID)
    case .replace(let replacement):
      userNotes = replacement
    }
    ekEvent.notes = Self.notesWithMarker(userNotes: userNotes, lorvexID: lorvexEventID)
    ekEvent.recurrenceRules = try EventKitRecurrenceBridge.rules(from: recurrence)
    ekEvent.calendar = calendar
    try store.save(ekEvent, span: editingSeries ? .futureEvents : .thisEvent, commit: true)
    return EventKitWriteResult(providerEventKey: Self.stableKey(for: ekEvent))
  }

  func replaceFutureLorvexEventSeries(
    originalLorvexEventID: String,
    occurrenceDate: Date,
    replacement: CalendarEventExport,
    replacementLorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    guard
      let occurrence = resolveLorvexOccurrence(
        lorvexID: originalLorvexEventID, occurrenceDate: occurrenceDate)
    else {
      throw EventKitAccessError.originalMirrorOccurrenceUnresolved(
        eventID: originalLorvexEventID)
    }

    let recurrenceRules = try EventKitRecurrenceBridge.rules(from: replacement.recurrence)
    let calendar = try await resolveWriteCalendar(target, reusing: occurrence)
    occurrence.title = replacement.title
    occurrence.startDate = replacement.startDate
    occurrence.endDate = replacement.endDate
    occurrence.isAllDay = replacement.isAllDay
    occurrence.location = replacement.location
    occurrence.notes = Self.notesWithMarker(
      userNotes: replacement.notes, lorvexID: replacementLorvexEventID)
    occurrence.recurrenceRules = recurrenceRules
    occurrence.calendar = calendar
    try store.save(occurrence, span: .futureEvents, commit: true)
    return EventKitWriteResult(providerEventKey: Self.stableKey(for: occurrence))
  }

  /// Resolve the EKCalendar a write-back lands in for `target`. An explicit
  /// writable calendar wins; `keepExisting` leaves a reused event where it is; a
  /// default choice — or an id that no longer resolves to a writable calendar —
  /// falls back to the dedicated Lorvex calendar (created on first use).
  private func resolveWriteCalendar(
    _ target: EventKitWriteTarget, reusing reused: EKEvent?
  ) async throws -> EKCalendar {
    switch target {
    case .calendar(let id):
      if let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
        return calendar
      }
      return try await ensureLorvexCalendar()
    case .keepExisting:
      if let existing = reused?.calendar { return existing }
      return try await ensureLorvexCalendar()
    case .lorvexDefault:
      return try await ensureLorvexCalendar()
    }
  }

  func deleteLorvexEvent(providerEventKey: String) async throws {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    guard let ekEvent = resolveEvent(key: providerEventKey) else { return }
    try removeWholeSeries(ekEvent)
  }

  func deleteLorvexEvent(lorvexEventID: String) async throws {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    guard let ekEvent = resolveLorvexEvent(key: nil, lorvexID: lorvexEventID) else { return }
    try removeWholeSeries(ekEvent)
  }

  func removeLorvexEventOccurrence(lorvexEventID: String, occurrenceDate: Date) async throws {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    guard let occurrence = resolveLorvexOccurrence(lorvexID: lorvexEventID, occurrenceDate: occurrenceDate)
    else { return }
    try store.remove(occurrence, span: .thisEvent, commit: true)
  }

  func removeFutureLorvexEventSeries(
    lorvexEventID: String, occurrenceDate: Date
  ) async throws {
    guard try await requestAccess() else {
      throw EventKitAccessError.writeAccessDenied
    }
    guard
      let occurrence = resolveLorvexOccurrence(
        lorvexID: lorvexEventID, occurrenceDate: occurrenceDate)
    else { return }
    try store.remove(occurrence, span: .futureEvents, commit: true)
  }

  /// Remove a Lorvex mirror as a whole. A recurring mirror deletes its entire
  /// series: normalize to the first occurrence (`seriesMaster(for:)`) and remove
  /// with `EKSpan.futureEvents`, so every occurrence goes rather than leaving the
  /// rest orphaned in the user's live calendar. A non-recurring mirror removes as
  /// itself with `.thisEvent`. Dropping a single occurrence of a series is a
  /// different operation — see `removeLorvexEventOccurrence`.
  private func removeWholeSeries(_ event: EKEvent) throws {
    guard event.hasRecurrenceRules else {
      try store.remove(event, span: .thisEvent, commit: true)
      return
    }
    try store.remove(seriesMaster(for: event), span: .futureEvents, commit: true)
  }

  /// Normalize a recurring EKEvent to its series' first occurrence. A predicate
  /// scan resolves whichever occurrence lands in its window, but a whole-series
  /// edit/delete must act on the first occurrence so `EKSpan.futureEvents` spans
  /// the entire series. `EKEventStore` resolves a recurring event's identifier to
  /// its first occurrence; falls back to `event` when it cannot be re-resolved
  /// (e.g. an unsaved event with no identifier index).
  private func seriesMaster(for event: EKEvent) -> EKEvent {
    guard let master = store.calendarItem(withIdentifier: event.calendarItemIdentifier) as? EKEvent
    else { return event }
    return master
  }

  // MARK: - Lorvex calendar

  private func ensureLorvexCalendar() async throws -> EKCalendar {
    if let cachedID = await loadCalendarID(),
      let calendar = store.calendar(withIdentifier: cachedID)
    {
      return calendar
    }
    guard let source = store.preferredCalendarSource else {
      throw EventKitAccessError.noWritableSource
    }
    let calendar = store.makeCalendar()
    calendar.title = Self.lorvexCalendarTitle
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    await saveCalendarID(calendar.calendarIdentifier)
    return calendar
  }

  /// Resolve the EKEvent for a Lorvex-originated event: by cached `key` when
  /// present, else by the `lorvex-event-id:` notes marker (the
  /// device-independent breadcrumb written on every Lorvex export).
  private func resolveLorvexEvent(key: String?, lorvexID: String) -> EKEvent? {
    if let key, let byKey = resolveEvent(key: key) {
      return byKey
    }
    let marker = "\(lorvexCalendarEventPrefix)\(lorvexID)"
    let now = Date()
    // EventKit silently truncates a fetch predicate to ~4 years from its start,
    // so the old 7-year span dropped far-future Lorvex events and resolved them
    // as missing — writing a duplicate EKEvent on the next update. Keep the
    // window just under 4 years, biased to the future where Lorvex events live.
    let day: TimeInterval = 24 * 3600
    let start = now.addingTimeInterval(-90 * day)
    let end = now.addingTimeInterval(1350 * day)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate).first { $0.notes?.contains(marker) == true }
  }

  /// Resolve a specific occurrence instance of a mirrored Lorvex recurring
  /// event. Removing that occurrence with `.thisEvent` records EventKit's EXDATE.
  private func resolveLorvexOccurrence(lorvexID: String, occurrenceDate: Date) -> EKEvent? {
    let marker = "\(lorvexCalendarEventPrefix)\(lorvexID)"
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: occurrenceDate)
    let start = dayStart.addingTimeInterval(-60 * 60)
    let end = dayStart.addingTimeInterval(25 * 60 * 60)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate)
      .filter { $0.notes?.contains(marker) == true }
      .min {
        abs($0.startDate.timeIntervalSince(occurrenceDate))
          < abs($1.startDate.timeIntervalSince(occurrenceDate))
      }
  }

  /// Resolve an EKEvent by its stable key (external identifier or event
  /// identifier). A direct identifier lookup is O(1); failing that (the key is
  /// an external identifier, which has no direct lookup), scan a window of
  /// events. `dayHint` (`yyyy-MM-dd`) tightens that window to a few days around
  /// the known event date so the inspector's per-open resolution stays cheap;
  /// without a hint it falls back to a broad multi-year scan (the write-back
  /// path, which has no date in hand).
  private func resolveEvent(key: String, dayHint: String? = nil) -> EKEvent? {
    if let item = store.calendarItem(withIdentifier: key) as? EKEvent {
      return item
    }
    let start: Date
    let end: Date
    if let dayHint, let day = LorvexDateFormatters.ymd.date(from: dayHint) {
      start = day.addingTimeInterval(-2 * 24 * 3600)
      end = day.addingTimeInterval(2 * 24 * 3600)
    } else {
      let now = Date()
      start = now.addingTimeInterval(-2 * 365 * 24 * 3600)
      end = now.addingTimeInterval(5 * 365 * 24 * 3600)
    }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate).first { Self.stableKey(for: $0) == key }
  }

  func eventSource(forEventKey key: String, dayHint: String?) async -> EventKitEventSource? {
    guard isReadAuthorized() else { return nil }
    guard let calendar = resolveEvent(key: key, dayHint: dayHint)?.calendar else { return nil }
    let title = calendar.title
    let account = calendar.source?.title
    return EventKitEventSource(
      calendarTitle: title.isEmpty
        ? String(localized: "calendar.picker.untitled", defaultValue: "Untitled Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
        : title,
      accountTitle: account?.isEmpty == false ? account : nil)
  }

  /// `#RRGGBB` for an EventKit calendar's `cgColor`, resolved in sRGB; nil when
  /// EventKit reports no color or it can't be resolved to RGB.
  private static func hexString(from cgColor: CGColor?) -> String? {
    guard let cgColor, let srgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
      return nil
    }
    return String(
      format: "#%02X%02X%02X",
      Int((srgb.redComponent * 255).rounded()),
      Int((srgb.greenComponent * 255).rounded()),
      Int((srgb.blueComponent * 255).rounded()))
  }

}
