/// An existing occurrence's source start, derived from a validated series or
/// stored row inside the write transaction. Materializing that same start may
/// preserve a recurrence's spring-gap clock; a different date, clock, zone, or
/// all-day state still undergoes the normal new-time validation.
///
/// This is internal workflow context, never a user-supplied tool argument.
public struct CalendarInheritedStart: Sendable, Equatable {
  public let date: String
  public let time: String?
  public let timezone: String?
  public let allDay: Bool

  public init(date: String, time: String?, timezone: String?, allDay: Bool) {
    self.date = date
    self.time = time
    self.timezone = timezone
    self.allDay = allDay
  }
}
