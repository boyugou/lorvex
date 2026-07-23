import GRDB
import LorvexDomain

/// Canonical stored shape for one durable recurring-series boundary.
public struct CalendarSeriesCutoverRow: Sendable, Equatable {
  public var id: String
  public var lineageRootId: String
  public var cutoverDate: String
  public var state: CalendarSeriesCutoverState
  public var version: String
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String, lineageRootId: String, cutoverDate: String,
    state: CalendarSeriesCutoverState, version: String,
    createdAt: String, updatedAt: String
  ) {
    self.id = id
    self.lineageRootId = lineageRootId
    self.cutoverDate = cutoverDate
    self.state = state
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Validated persistence and remove-wins join for `calendar_series_cutovers`.
public enum CalendarSeriesCutoverRepo {
  public static func fetch(_ db: Database, id: String) throws -> CalendarSeriesCutoverRow? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, lineage_root_id, cutover_date, state, version, created_at, updated_at
          FROM calendar_series_cutovers WHERE id = ?
          """,
        arguments: [id])
    else { return nil }
    guard let state = CalendarSeriesCutoverState(rawValue: row["state"]) else {
      throw StoreError.invariant("calendar series cutover \(id) has an invalid state")
    }
    return CalendarSeriesCutoverRow(
      id: row["id"], lineageRootId: row["lineage_root_id"],
      cutoverDate: row["cutover_date"], state: state, version: row["version"],
      createdAt: row["created_at"], updatedAt: row["updated_at"])
  }

  /// Join and persist one boundary. Identity/date are immutable, `deleted` is
  /// absorbing, and the row version remains the maximum valid HLC observed.
  @discardableResult
  public static func upsert(
    _ db: Database, row incoming: CalendarSeriesCutoverRow
  ) throws -> CalendarSeriesCutoverRow {
    try validate(incoming)
    let merged: CalendarSeriesCutoverRow
    if let local = try fetch(db, id: incoming.id) {
      merged = try join(local: local, incoming: incoming)
    } else {
      merged = incoming
    }
    try db.execute(
      sql: """
        INSERT INTO calendar_series_cutovers
          (id, lineage_root_id, cutover_date, state, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          state = excluded.state,
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        """,
      arguments: [
        merged.id, merged.lineageRootId, merged.cutoverDate, merged.state.rawValue,
        merged.version, merged.createdAt, merged.updatedAt,
      ])
    return merged
  }

  public static func join(
    local: CalendarSeriesCutoverRow, incoming: CalendarSeriesCutoverRow
  ) throws -> CalendarSeriesCutoverRow {
    try validate(local)
    try validate(incoming)
    guard local.id == incoming.id,
      local.lineageRootId == incoming.lineageRootId,
      local.cutoverDate == incoming.cutoverDate
    else {
      throw StoreError.invariant(
        "calendar series cutover identity fields are immutable for \(local.id)")
    }

    let localVersion = try Hlc.parseCanonical(local.version)
    let incomingVersion = try Hlc.parseCanonical(incoming.version)
    let winner = incomingVersion > localVersion ? incoming : local
    return CalendarSeriesCutoverRow(
      id: local.id, lineageRootId: local.lineageRootId,
      cutoverDate: local.cutoverDate,
      state: local.state == .deleted || incoming.state == .deleted ? .deleted : .active,
      version: max(localVersion, incomingVersion).description,
      createdAt: min(local.createdAt, incoming.createdAt),
      updatedAt: incomingVersion == localVersion
        ? max(local.updatedAt, incoming.updatedAt) : winner.updatedAt)
  }

  public static func validate(_ row: CalendarSeriesCutoverRow) throws {
    guard SyncEntityId.isCanonicalUuid(row.lineageRootId) else {
      throw StoreError.validation("calendar series lineage_root_id must be a canonical UUID")
    }
    // Version 8 is reserved for deterministic cutover / occurrence identities.
    // Accept app-authored v7 and imported legacy UUID versions, but never let a
    // derived segment become the root of a second, overlapping lineage.
    guard Array(row.lineageRootId.utf8)[14] != 0x38 else {
      throw StoreError.validation(
        "calendar series lineage_root_id must not be a derived UUIDv8 identity")
    }
    guard case .success = LorvexDate.parse(row.cutoverDate) else {
      throw StoreError.validation("calendar series cutover_date must be YYYY-MM-DD")
    }
    let expected = CalendarSeriesCutoverID.make(
      lineageRootId: row.lineageRootId, cutoverDate: row.cutoverDate)
    guard row.id == expected else {
      throw StoreError.validation(
        "calendar series cutover id does not match its lineage and date")
    }
    guard let parsed = try? Hlc.parseCanonical(row.version), parsed.description == row.version else {
      throw StoreError.validation("calendar series cutover version must be a canonical HLC")
    }
    guard SyncTimestamp.parse(row.createdAt)?.asString == row.createdAt,
      SyncTimestamp.parse(row.updatedAt)?.asString == row.updatedAt
    else {
      throw StoreError.validation(
        "calendar series cutover timestamps must be canonical RFC 3339 UTC instants")
    }
    guard row.createdAt <= row.updatedAt else {
      throw StoreError.validation(
        "calendar series cutover updated_at must not precede created_at")
    }
  }
}
