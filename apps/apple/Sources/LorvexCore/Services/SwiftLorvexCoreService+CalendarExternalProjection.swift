import Foundation
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// Load one canonical event in the form safe to send to an external calendar
  /// provider. Durable recurrence stays cutover-independent; only this
  /// ephemeral projection clips a recurring segment at its next boundary.
  public func getCalendarEventForExternalProjection(
    id: CalendarTimelineEvent.ID
  ) async throws -> CalendarTimelineEvent? {
    try read { db in
      guard let row = try CalendarTimelineQueries.getCalendarEvent(db, id: id) else {
        return nil
      }
      var event = SwiftLorvexCalendarDeserializers.event(row)
      guard row.recurrence != nil else { return event }
      let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
        db, eventId: row.id)
      event.recurrenceRule = try Self.effectiveExternalCalendarRecurrence(
        row: row, ownership: ownership)
      return event
    }
  }

  /// Render the durable segment's upper bound into an adapter wire form
  /// without changing the stored Lorvex recurrence. Every outbound calendar
  /// adapter must use this projection so no segment can cross a later cutover.
  static func effectiveExternalCalendarRecurrence(
    row: CalendarEventRow, ownership: CalendarSeriesOwnership?
  ) throws -> String? {
    guard let recurrence = row.recurrence else { return nil }
    guard let ownership, ownership.isActive else {
      throw LorvexCoreError.unsupportedOperation(
        "Calendar series '\(row.id)' has no active cutover ownership")
    }
    guard let nextCutoverDate = ownership.nextCutoverDate else { return recurrence }
    switch CalendarRecurrenceScope.truncateRecurrenceBefore(
      rawRecurrence: recurrence,
      splitDateYmd: nextCutoverDate,
      seriesStartYmd: row.startDate.asString)
    {
    case .truncated(let clipped): return clipped
    case .noop: return recurrence
    case .collapse:
      throw LorvexCoreError.unsupportedOperation(
        "Calendar series '\(row.id)' has no occurrence before its next cutover")
    }
  }
}
