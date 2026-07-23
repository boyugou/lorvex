/// Durable state of one recurring-calendar lineage boundary.
///
/// `deleted` is absorbing: once any peer deletes a segment boundary, no stale
/// or later `active` snapshot for the same deterministic identity can reactivate
/// it. A new schedule on that date must use a new independent series.
public enum CalendarSeriesCutoverState: String, Codable, CaseIterable, Sendable, Equatable,
  Hashable
{
  case active
  case deleted
}
