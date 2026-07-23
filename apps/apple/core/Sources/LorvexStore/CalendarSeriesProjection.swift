import Foundation
import GRDB
import LorvexDomain

/// The durable slot interval owned by one recurring calendar-series segment.
///
/// The root segment is implicit (`segmentCutoverId == nil`). Tail segments are
/// addressed by their deterministic cutover id. Both active and deleted
/// cutovers participate in interval partitioning, so `nextCutoverDate` is
/// derived from the complete ordered boundary set rather than active rows only.
public struct CalendarSeriesOwnership: Sendable, Equatable {
  public let segmentEventId: String
  public let lineageRootId: String
  public let segmentCutoverId: String?
  public let lowerBoundCutoverDate: String?
  public let nextCutoverDate: String?
  public let isActive: Bool

  public init(
    segmentEventId: String,
    lineageRootId: String,
    segmentCutoverId: String?,
    lowerBoundCutoverDate: String?,
    nextCutoverDate: String?,
    isActive: Bool
  ) {
    self.segmentEventId = segmentEventId
    self.lineageRootId = lineageRootId
    self.segmentCutoverId = segmentCutoverId
    self.lowerBoundCutoverDate = lowerBoundCutoverDate
    self.nextCutoverDate = nextCutoverDate
    self.isActive = isActive
  }

  /// Whether this segment owns an original recurrence slot. Display dates of
  /// moved replacement decisions deliberately do not participate.
  public func owns(recurrenceInstanceDate: String) -> Bool {
    guard isActive else { return false }
    if let lowerBoundCutoverDate, recurrenceInstanceDate < lowerBoundCutoverDate {
      return false
    }
    if let nextCutoverDate, recurrenceInstanceDate >= nextCutoverDate {
      return false
    }
    return true
  }
}

extension CalendarTimelineQueries {
  /// Resolve the current segment addressed by either a base event id or an
  /// occurrence-decision id. A tail whose cutover has not arrived fails closed
  /// as `nil`; a tail behind an absorbing deleted cutover returns an inactive
  /// ownership so workflows can distinguish it from a missing row.
  public static func getCalendarSeriesOwnership(
    _ db: Database, eventId: String
  ) throws -> CalendarSeriesOwnership? {
    guard
      let addressed = try Row.fetchOne(
        db,
        sql: "SELECT id, series_id FROM calendar_events WHERE id = ?",
        arguments: [eventId])
    else {
      return nil
    }
    let decisionSeriesId: String? = addressed[1]
    let segmentEventId = decisionSeriesId ?? eventId
    guard
      let segment = try Row.fetchOne(
        db,
        sql: "SELECT series_id, series_cutover_id FROM calendar_events WHERE id = ?",
        arguments: [segmentEventId]),
      (segment[0] as String?) == nil
    else {
      return nil
    }
    let seriesCutoverId: String? = segment[1]
    guard seriesCutoverId == nil || seriesCutoverId == segmentEventId else {
      return nil
    }
    let candidates = CalendarSeriesProjectionIndex.Candidates(
      lineageRootIds: seriesCutoverId == nil ? [segmentEventId] : [],
      cutoverIds: seriesCutoverId == nil ? [] : [segmentEventId])
    let index = try CalendarSeriesProjectionIndex(db, candidates: candidates)
    return index.ownership(
      segmentEventId: segmentEventId, seriesCutoverId: seriesCutoverId)
  }

  /// Convenience guard for scoped workflows. Membership is based on the
  /// original recurrence slot, never a replacement's moved display date.
  public static func calendarSeriesOwnsOccurrence(
    _ db: Database, eventId: String, recurrenceInstanceDate: String
  ) throws -> Bool {
    try getCalendarSeriesOwnership(db, eventId: eventId)?
      .owns(recurrenceInstanceDate: recurrenceInstanceDate) == true
  }

  /// Resolve a segment from the durable relation alone, without requiring its
  /// `calendar_events` row to have arrived. Sync preflight uses this for the
  /// boundary-first order: an occurrence decision may be retained for its known
  /// segment while the segment event itself is still pending.
  ///
  /// A tail is known when its id is a cutover id. An implicit root is known when
  /// at least one cutover names it as `lineage_root_id`; an unrelated id returns
  /// nil because the relation cannot distinguish a plain event from a root that
  /// has never been partitioned.
  public static func getCalendarSeriesOwnershipForSegmentIdentity(
    _ db: Database, segmentEventId: String
  ) throws -> CalendarSeriesOwnership? {
    let candidates = CalendarSeriesProjectionIndex.Candidates(
      ambiguousSegmentEventIds: [segmentEventId])
    return try CalendarSeriesProjectionIndex(
      db, candidates: candidates
    ).ownershipForSegmentIdentity(segmentEventId)
  }

  /// Resolve a batch of already-loaded base rows against one cutover snapshot.
  /// Adapters exporting many recurrence components use this to avoid rescanning
  /// the complete boundary relation once per series.
  public static func getCalendarSeriesOwnerships(
    _ db: Database, baseEvents: [CalendarEventRow]
  ) throws -> [String: CalendarSeriesOwnership] {
    let candidates = CalendarSeriesProjectionIndex.Candidates(
      events: baseEvents.lazy.filter { $0.seriesId == nil })
    let index = try CalendarSeriesProjectionIndex(db, candidates: candidates)
    var result: [String: CalendarSeriesOwnership] = [:]
    result.reserveCapacity(baseEvents.count)
    for event in baseEvents where event.seriesId == nil {
      if let ownership = index.ownership(
        segmentEventId: event.id, seriesCutoverId: event.seriesCutoverId)
      {
        result[event.id] = ownership
      }
    }
    return result
  }

}

/// A read-consistent, lineage-bound cache of the ordered cutover relation.
/// Timeline reads load the relevant set once; paginated list and search reads
/// extend the cache only for newly encountered segment identities.
struct CalendarSeriesProjectionIndex {
  struct Candidates {
    var lineageRootIds: [String]
    var cutoverIds: [String]

    init(
      lineageRootIds: [String] = [], cutoverIds: [String] = [],
      ambiguousSegmentEventIds: [String] = []
    ) {
      self.lineageRootIds = lineageRootIds + ambiguousSegmentEventIds
      self.cutoverIds = cutoverIds + ambiguousSegmentEventIds
    }

    init<S: Sequence>(events: S) where S.Element == CalendarEventRow {
      lineageRootIds = []
      cutoverIds = []
      for event in events {
        if let seriesId = event.seriesId {
          lineageRootIds.append(seriesId)
          cutoverIds.append(seriesId)
        } else if event.seriesCutoverId == nil {
          lineageRootIds.append(event.id)
        } else {
          cutoverIds.append(event.id)
        }
      }
    }
  }

  struct Cutover: Sendable, Equatable {
    let id: String
    let lineageRootId: String
    let cutoverDate: String
    let isActive: Bool
  }

  private var byId: [String: Cutover] = [:]
  private var byLineage: [String: [Cutover]] = [:]
  private var loadedSegmentEventIds: Set<String> = []

  init() {}

  init(_ db: Database, candidates: Candidates) throws {
    self.init()
    try load(db, candidates: candidates)
  }

  /// Add the complete boundary sets for the requested roots and cutover ids.
  /// Ambiguous segment identities are included in both candidate arrays. This
  /// single statement resolves both forms and then uses the primary-key and
  /// `(lineage_root_id, cutover_date)` indexes to load only those lineages.
  /// Keeping resolution and loading in one statement also preserves one SQLite
  /// read snapshot when a caller supplies a bare autocommit `Database`.
  mutating func load(_ db: Database, candidates: Candidates) throws {
    let requestedRoots = Array(
      Set(candidates.lineageRootIds).subtracting(loadedSegmentEventIds)
    ).sorted()
    let requestedCutovers = Array(
      Set(candidates.cutoverIds).subtracting(loadedSegmentEventIds)
    ).sorted()
    guard !requestedRoots.isEmpty || !requestedCutovers.isEmpty else { return }
    let rootsJSON = String(
      decoding: try JSONEncoder().encode(requestedRoots), as: UTF8.self)
    let cutoversJSON = String(
      decoding: try JSONEncoder().encode(requestedCutovers), as: UTF8.self)
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, lineage_root_id, cutover_date, state
        FROM calendar_series_cutovers
        WHERE lineage_root_id IN (
          SELECT CAST(value AS TEXT) FROM json_each(?1)
          UNION ALL
          SELECT lineage_root_id
          FROM calendar_series_cutovers
          WHERE id IN (SELECT CAST(value AS TEXT) FROM json_each(?2))
        )
        ORDER BY lineage_root_id ASC, cutover_date ASC, id ASC
        """,
      arguments: [rootsJSON, cutoversJSON])
    var loaded: [Cutover] = []
    loaded.reserveCapacity(rows.count)
    for row in rows {
      let rawState: String = row[3]
      guard let state = CalendarSeriesCutoverState(rawValue: rawState) else {
        throw StoreError.invariant(
          "calendar series cutover \(row[0] as String) has an invalid state")
      }
      let cutover = Cutover(
        id: row[0], lineageRootId: row[1], cutoverDate: row[2],
        isActive: state == .active)
      loaded.append(cutover)
    }
    loadedSegmentEventIds.formUnion(requestedRoots)
    loadedSegmentEventIds.formUnion(requestedCutovers)
    for cutover in loaded {
      byId[cutover.id] = cutover
      byLineage[cutover.lineageRootId, default: []].append(cutover)
      loadedSegmentEventIds.insert(cutover.id)
      loadedSegmentEventIds.insert(cutover.lineageRootId)
    }
  }

  func ownership(
    segmentEventId: String, seriesCutoverId: String?
  ) -> CalendarSeriesOwnership? {
    guard let seriesCutoverId else {
      return CalendarSeriesOwnership(
        segmentEventId: segmentEventId,
        lineageRootId: segmentEventId,
        segmentCutoverId: nil,
        lowerBoundCutoverDate: nil,
        nextCutoverDate: byLineage[segmentEventId]?.first?.cutoverDate,
        isActive: true)
    }
    guard seriesCutoverId == segmentEventId, let cutover = byId[seriesCutoverId]
    else {
      return nil
    }
    let nextDate = byLineage[cutover.lineageRootId]?
      .first { $0.cutoverDate > cutover.cutoverDate }?.cutoverDate
    return CalendarSeriesOwnership(
      segmentEventId: segmentEventId,
      lineageRootId: cutover.lineageRootId,
      segmentCutoverId: cutover.id,
      lowerBoundCutoverDate: cutover.cutoverDate,
      nextCutoverDate: nextDate,
      isActive: cutover.isActive)
  }

  func ownershipForSegmentIdentity(
    _ segmentEventId: String
  ) -> CalendarSeriesOwnership? {
    if byId[segmentEventId] != nil {
      return ownership(
        segmentEventId: segmentEventId, seriesCutoverId: segmentEventId)
    }
    guard byLineage[segmentEventId] != nil else { return nil }
    return ownership(segmentEventId: segmentEventId, seriesCutoverId: nil)
  }
}
