#if canImport(EventKit)
  @preconcurrency import EventKit
  import Foundation
  import LorvexCore
  import LorvexDomain
  import LorvexStore
  #if canImport(UIKit)
    import UIKit
  #endif

  actor MobileLiveEventKitAccess: MobileEventKitAccessing {
    private let store: EKEventStore
    private let loadCalendarID: @Sendable () async -> String?
    private let saveConfirmedReadAccess: @Sendable (Bool) -> Void
    private let loadConfirmedReadAccess: @Sendable () -> Bool

    init(
      store: EKEventStore = EKEventStore(),
      loadCalendarID: @escaping @Sendable () async -> String? = { nil },
      loadConfirmedReadAccess: @escaping @Sendable () -> Bool = { false },
      saveConfirmedReadAccess: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
      self.store = store
      self.loadCalendarID = loadCalendarID
      self.loadConfirmedReadAccess = loadConfirmedReadAccess
      self.saveConfirmedReadAccess = saveConfirmedReadAccess
    }

    func requestAccess() async throws -> Bool {
      if isReadAuthorized() { return true }
      switch EKEventStore.authorizationStatus(for: .event) {
      case .notDetermined:
        let granted = try await store.requestFullAccessToEvents()
        if granted {
          saveConfirmedReadAccess(true)
          store.reset()
        }
        return granted
      case .fullAccess:
        saveConfirmedReadAccess(true)
        return true
      default:
        return false
      }
    }

    nonisolated func isReadAuthorized() -> Bool {
      switch EKEventStore.authorizationStatus(for: .event) {
      case .fullAccess:
        saveConfirmedReadAccess(true)
        return true
      case .notDetermined:
        return loadConfirmedReadAccess()
      default:
        return false
      }
    }

    func availableCalendars() async throws -> [EventKitCalendarDescriptor] {
      guard isReadAuthorized() else { throw MobileEventKitAccessError.readAccessDenied }
      let lorvexID = await loadCalendarID()
      return store.calendars(for: .event)
        .filter { calendar in
          if let lorvexID, calendar.calendarIdentifier == lorvexID { return false }
          return !calendar.calendarIdentifier.isEmpty
        }
        .map { calendar in
          let sourceTitle = calendar.source?.title
          return EventKitCalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title.isEmpty
              ? String(
                localized: "calendar.picker.untitled", defaultValue: "Untitled Calendar",
                table: "Localizable", bundle: MobileL10n.bundle)
              : calendar.title,
            sourceTitle: sourceTitle?.isEmpty == false ? sourceTitle : nil)
        }
        .sorted {
          let lhs = (($0.sourceTitle ?? ""), $0.title, $0.id)
          let rhs = (($1.sourceTitle ?? ""), $1.title, $1.id)
          return lhs < rhs
        }
    }

    func fetchEvents(
      start: Date,
      end: Date,
      calendarFilter: EventKitCalendarFilter = .all
    ) async throws -> [EventKitFetchedEvent] {
      guard isReadAuthorized() else { throw MobileEventKitAccessError.readAccessDenied }
      var events: [EventKitFetchedEvent] = []
      let lorvexID = await loadCalendarID()
      var windowStart = start
      let chunk: TimeInterval = 4 * 365 * 24 * 3600
      while windowStart < end {
        let windowEnd = min(windowStart.addingTimeInterval(chunk), end)
        let predicate = store.predicateForEvents(
          withStart: windowStart,
          end: windowEnd,
          calendars: nil
        )
        for event in store.events(matching: predicate) {
          if let lorvexID, event.calendar?.calendarIdentifier == lorvexID { continue }
          if event.notes?.contains(Self.lorvexCalendarEventPrefix) == true { continue }
          guard calendarFilter.allows(calendarID: event.calendar?.calendarIdentifier) else {
            continue
          }
          events.append(Self.fetchedEvent(from: event))
        }
        windowStart = windowEnd
      }
      return events
    }

    static func fetchedEvent(from event: EKEvent) -> EventKitFetchedEvent {
      let eventTimeZone = event.timeZone ?? .current
      let startDate = AllDayEventSpan.dayKey(for: event.startDate, timeZone: eventTimeZone)
      let startTime =
        event.isAllDay ? nil : clockTimeKey(for: event.startDate, timeZone: eventTimeZone)
      return EventKitFetchedEvent(
        key: stableKey(for: event, startDate: startDate, startTime: startTime),
        title: event.title?.isEmpty == false ? event.title : nil,
        notes: event.notes,
        startDate: startDate,
        startTime: startTime,
        endDate: lorvexEndDate(from: event, timeZone: eventTimeZone),
        endTime: event.isAllDay
          ? nil : event.endDate.map { clockTimeKey(for: $0, timeZone: eventTimeZone) },
        allDay: event.isAllDay,
        location: event.location?.isEmpty == false ? event.location : nil,
        timezone: event.timeZone?.identifier,
        color: hexColor(from: event.calendar?.cgColor),
        organizerEmail: participantEmail(event.organizer),
        url: event.url?.absoluteString,
        attendees: fetchedAttendees(from: event.attendees)
      )
    }

    /// EventKit's all-day end is exclusive; Lorvex stores the final occupied
    /// civil day inclusively. Timed events already use the same end-date shape.
    private static func lorvexEndDate(from event: EKEvent, timeZone: TimeZone) -> String? {
      guard let endDate = event.endDate else { return nil }
      guard event.isAllDay else {
        return AllDayEventSpan.dayKey(for: endDate, timeZone: timeZone)
      }
      let startDate = event.startDate ?? endDate
      let inclusiveEnd = AllDayEventSpan.inclusiveEnd(
        start: startDate,
        exclusiveEnd: endDate,
        calendar: AllDayEventSpan.gregorianCalendar(timeZone: timeZone))
      return AllDayEventSpan.dayKey(for: inclusiveEnd, timeZone: timeZone)
    }

    /// Render an instant as the event's own 24-hour wall-clock time. These
    /// fields are later interpreted in `source_tzid`, so using the device zone
    /// here would silently move the event when the two zones differ.
    private static func clockTimeKey(for date: Date, timeZone: TimeZone) -> String {
      let components = AllDayEventSpan.gregorianCalendar(timeZone: timeZone)
        .dateComponents([.hour, .minute], from: date)
      return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// Map `EKEvent.attendees` into the platform-neutral projection, dropping
    /// participants with no addressable email (the read path keys attendees by
    /// email) and normalizing each `EKParticipantStatus` to the canonical
    /// RFC 5545 PARTSTAT subset.
    static func fetchedAttendees(from participants: [EKParticipant]?) -> [EventKitFetchedAttendee] {
      guard let participants else { return [] }
      return participants.compactMap { participant in
        guard let email = participantEmail(participant) else { return nil }
        return EventKitFetchedAttendee(
          email: email,
          name: participant.name?.isEmpty == false ? participant.name : nil,
          status: attendeeStatus(from: participant.participantStatus))
      }
    }

    /// A participant's email, stripped of the `mailto:` scheme EventKit wraps it
    /// in. `nil` when the participant carries no non-empty address.
    static func participantEmail(_ participant: EKParticipant?) -> String? {
      guard let participant else { return nil }
      let raw = participant.url.absoluteString
      let email =
        raw.lowercased().hasPrefix("mailto:")
        ? String(raw.dropFirst("mailto:".count)) : raw
      return email.isEmpty ? nil : email
    }

    /// Map `EKParticipantStatus` onto the canonical attendee-status vocabulary.
    /// Undecided (`pending`) and indeterminate states fold to `needs-action`,
    /// matching RFC 5545.
    static func attendeeStatus(from status: EKParticipantStatus) -> AttendeeStatus {
      switch status {
      case .accepted: return .accepted
      case .declined: return .declined
      case .tentative: return .tentative
      default: return .needsAction
      }
    }

    static func stableKey(for event: EKEvent, startDate: String, startTime: String?) -> String {
      let base: String
      if let external = event.calendarItemExternalIdentifier, !external.isEmpty {
        base = external
      } else {
        base = event.eventIdentifier ?? event.calendarItemIdentifier
      }
      guard event.hasRecurrenceRules else {
        return base
      }
      if let startTime {
        return "\(base):\(startDate)T\(startTime)"
      }
      return "\(base):\(startDate)"
    }

    static let lorvexCalendarEventPrefix = "lorvex-event-id:"

    static func hexColor(from cgColor: CGColor?) -> String? {
      guard let cgColor else { return nil }
      #if canImport(UIKit)
        let color = UIColor(cgColor: cgColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
          format: "#%02X%02X%02X",
          Int((red * 255).rounded()),
          Int((green * 255).rounded()),
          Int((blue * 255).rounded()))
      #else
        return nil
      #endif
    }
  }
#endif
