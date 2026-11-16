/// The source civil fields of a canonical occurrence. These preserve the
/// intended clock through DST gaps and keep missing endpoints missing.
public struct CalendarEventSourceTiming: Equatable, Sendable {
  public let startDate: String
  public let startTime: String?
  public let endDate: String?
  public let endTime: String?
  public let allDay: Bool
  public let timezone: String?

  public init(
    startDate: String, startTime: String?, endDate: String?, endTime: String?,
    allDay: Bool, timezone: String?
  ) {
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.timezone = timezone
  }
}
