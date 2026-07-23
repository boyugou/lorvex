import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Structural safety net against a whole class of silent sync data-loss bugs:
/// **outbound / inbound field-set asymmetry.**
///
/// A syncable column has to survive TWO independent hand-maintained field sets to
/// converge across devices:
///  - OUTBOUND, the payload must actually carry the column.
///    `OutboxEnqueue.readEntityPayloadSnapshot` produces it via, per entity, the
///    generic reader (whose column list comes from the entity's
///    ``SyncEntityDescriptor`` outbound columns when the entity is migrated, else from
///    `pragma_table_info`), the day-scoped / calendar aggregate builders, or the
///    dedicated habit / preference loaders.
///  - INBOUND, the HAND-WRITTEN applier (`ApplyTask`, `ApplyList`,
///    `ApplyCalendarEvent`, `ApplyChild`, `ApplyEdge`, `ApplyDayScoped`, …) must
///    parse and write it.
///
/// Adding a schema column can silently break EITHER side. For a
/// descriptor-migrated entity, a column not added to the descriptor is omitted at
/// OUTBOUND (never shipped). For any entity, a column the applier ignores is
/// dropped at INBOUND. In both cases the field never converges across devices,
/// with no other test failing. `PayloadShadow.ownedKeysForEntity` + the schema
/// parity test only prove a field is LISTED in owned keys — not that it is shipped
/// outbound and that the applier parses and writes it.
///
/// This suite closes that gap with a per-column round-trip probe. For each
/// syncable entity, and for each of its syncable columns:
///  1. seed a source DB row whose column holds a distinctive non-default
///     sentinel (type- and name-appropriate: marker string, specific int, date,
///     time, timestamp);
///  2. build the outbound payload through the REAL outbound path
///     (`readEntityPayloadSnapshot` for single-PK/aggregate kinds; the production
///     `PayloadLoaders` projection for composite edges),
///     enqueue it, and take the exact `Outbox.getPending` envelope that would be
///     pushed;
///  3. apply that envelope to a SEPARATE empty peer DB through the REAL inbound
///     applier registry (`Apply.applyEnvelope` + `defaultEntityAppliers()`);
///  4. read the column back from the peer and assert it equals the source value.
///
/// A column that ships outbound but is dropped inbound reads back as
/// NULL/default on the peer ≠ the source sentinel → the probe FAILS, naming the
/// entity and column.
///
/// ## Data-driven seeding — NOT lockstep with the outbound column source
///
/// The seed/enumeration column set is `pragma_table_info(table)` at runtime.
/// `pragma_table_info` omits generated columns (`tasks.priority_effective`,
/// `calendar_events.recurrence_end_date` surface as hidden), and device-local
/// columns are filtered exactly as `StorageSchema.isDeviceLocalColumn` classifies
/// them (currently none). Every unconstrained column gets an auto-generated
/// sentinel.
///
/// This is NO LONGER the same source the outbound reader uses: a migrated entity's
/// generic reader sources its column list from the entity's ``SyncEntityDescriptor``
/// outbound columns, not `pragma_table_info`. That divergence is exactly what makes
/// this a TWO-SIDED probe — a newly-added free column is automatically seeded and
/// checked, and it fails the round-trip if it is dropped at EITHER end: omitted
/// from the descriptor (never shipped outbound) OR ignored by the applier (never
/// written inbound), in either case without anyone editing the test. A new
/// CHECK/FK-constrained column the auto-sentinel cannot satisfy trips the seed
/// insert loudly, forcing the author to add an override AND wire both the outbound
/// source (descriptor or builder) and the applier.
///
/// ## Intentionally special-cased columns (excluded from the value assertion)
///
/// These are applied, but NOT stored verbatim, so a raw source==peer comparison
/// is the wrong oracle. Each is covered by its own dedicated suite:
///  - `task.recurrence`, `calendar_event.recurrence` — normalized to canonical
///    RRULE form at the inbound trust boundary (`ApplyTask`,
///    `ApplyCalendarEvent`).
///
/// `habit.lookup_key` and `tag.lookup_key` are derived-local storage columns.
/// Their probes seed the canonical derivation, assert the final wire manifest
/// excludes the key, and still compare the reconstructed peer value.
///
/// `ai_changelog` is intentionally NOT probed here: it is an append-only audit
/// stream with a bounded, id-dedup (`INSERT OR IGNORE`, no LWW) outbound
/// contract rather than the bidirectional upsert lane this asymmetry class lives
/// in; its final builder→outbox key shape is covered by
/// `SyncPayloadContractTests`. The
/// `testEverySyncableKindHasARoundTripProbe` guard enforces that every OTHER
/// syncable kind is covered, so a future kind added to `allSyncableTypes` fails
/// until a probe is added.
final class SyncFieldRoundTripProbeTests: XCTestCase {

  // MARK: - Sentinel model

  /// A seed value bound into a source column and, for edges, projected into the
  /// outbound payload. Only the three storage classes the syncable tables use.
  private enum Seed {
    case text(String)
    case int(Int64)
    case null

    var db: DatabaseValue {
      switch self {
      case .text(let s): return s.databaseValue
      case .int(let n): return n.databaseValue
      case .null: return .null
      }
    }
  }

  /// Canonical zero HLC used as the seeded pre-sync `version`; the enqueue
  /// context version dominates it so the version stamp advances cleanly.
  private let zeroHlc = "0000000000000_0000_0000000000000000"
  /// Enqueue context version — dominates every seeded row version. Both the
  /// stamped source row and the applied peer row end up at this value, so
  /// `version` round-trips to it on both sides.
  private let contextVersion = "1743280000000_0001_deadbeefdeadbeef"
  private let deviceId = "dev-probe"

  // MARK: - Ids

  /// Canonical hyphenated UUIDv7-shaped id for index `n` (matches the shape the
  /// envelope entity_id validator requires).
  private func uuid(_ n: Int) -> String {
    "\(String(format: "%08x", n))-0000-7000-8000-000000000000"
  }

  private var pList: String { uuid(101) }
  private var pTask: String { uuid(102) }
  private var pTask2: String { uuid(103) }
  private var pTag: String { uuid(104) }
  private var pHabit: String { uuid(105) }
  private var pEvent: String { uuid(106) }
  private var pCutoverRoot: String { uuid(107) }
  private var pRecurrenceGroup: String { uuid(108) }
  private var pRecurringSuccessor: String {
    TaskRecurrenceSuccessorID.make(
      parentTaskId: pTask, recurrenceGroupId: pRecurrenceGroup)
  }
  private var pParentAuthorization: String {
    "1743270000000_0001_cafebabecafebabe"
  }
  private var pCutoverDate: String { "2029-03-05" }
  private var pCutover: String {
    CalendarSeriesCutoverID.make(
      lineageRootId: pCutoverRoot, cutoverDate: pCutoverDate)
  }

  // MARK: - Parent seeding

  private enum ParentKind {
    case list, task, task2, recurringTask, tag, habit, event, calendarCutover
  }

  /// FK-target parents seeded (raw, idempotent) into BOTH the source (so the
  /// probe row's own FK inserts succeed) and the peer (so inbound FK preflight
  /// does not defer the envelope). `list` is always ordered before `task`.
  private func seedParents(_ db: Database, _ parents: [ParentKind]) throws {
    let needsList =
      parents.contains(.list) || parents.contains(.task) || parents.contains(.task2)
      || parents.contains(.recurringTask)
    if needsList { try seedList(db, pList) }
    for p in parents {
      switch p {
      case .list: break
      case .task: try seedTask(db, pTask, list: pList)
      case .task2: try seedTask(db, pTask2, list: pList)
      case .recurringTask: try seedRecurringParent(db)
      case .tag: try seedTag(db, pTag)
      case .habit: try seedHabit(db, pHabit)
      case .event: try seedEvent(db, pEvent)
      case .calendarCutover: try seedCalendarCutover(db)
      }
    }
  }

  private func seedList(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
        + "VALUES (?, 'Parent list', ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id, zeroHlc])
  }

  private func seedTask(_ db: Database, _ id: String, list: String) throws {
    try db.execute(
      sql: "INSERT OR IGNORE INTO tasks (id, title, status, list_id, version, created_at, updated_at) "
        + "VALUES (?, 'Parent task', 'open', ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id, list, zeroHlc])
  }

  /// Seed the exact parent authorization needed for the task probe's generated
  /// successor. This makes every grouped register and both lineage fields carry
  /// a meaningful non-default value while still exercising the real inbound
  /// rollover reconciliation path.
  private func seedRecurringParent(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO tasks (
          id, title, status, list_id, due_date, recurrence,
          recurrence_group_id, canonical_occurrence_date,
          content_version, schedule_version, lifecycle_version, archive_version,
          recurrence_rollover_state, recurrence_successor_id, version,
          created_at, updated_at, completed_at
        ) VALUES (
          ?, 'Recurring parent', 'completed', ?, '2029-01-01',
          '{"FREQ":"DAILY"}', ?, '2029-01-01', ?, ?, ?, ?,
          'authorized', ?, ?,
          '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z',
          '2026-01-01T00:00:00.000Z'
        )
        """,
      arguments: [
        pTask, pList, pRecurrenceGroup, zeroHlc, pParentAuthorization,
        pParentAuthorization, zeroHlc, pRecurringSuccessor, pParentAuthorization,
      ])
  }

  private func seedTag(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT OR IGNORE INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id, "Parent \(id)", "parent-\(id)", zeroHlc])
  }

  private func seedHabit(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT OR IGNORE INTO habits (id, name, frequency_type, lookup_key, version, created_at, updated_at) "
        + "VALUES (?, ?, 'daily', ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
      arguments: [id, "Parent \(id)", "parent-\(id)", zeroHlc])
  }

  private func seedEvent(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT INTO calendar_events (id, title, start_date, all_day, event_type, "
        + "content_version, recurrence_topology_version, version, created_at, updated_at) "
        + "VALUES (?, 'Parent event', '2026-01-01', 1, 'event', ?, ?, ?, "
        + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z') "
        + "ON CONFLICT(id) DO NOTHING",
      arguments: [id, zeroHlc, zeroHlc, zeroHlc])
  }

  private func seedCalendarCutover(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_series_cutovers
          (id, lineage_root_id, cutover_date, state, version, created_at, updated_at)
        VALUES (?, ?, ?, 'active', ?,
                '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
        ON CONFLICT(id) DO NOTHING
        """,
      arguments: [pCutover, pCutoverRoot, pCutoverDate, zeroHlc])
  }

  // MARK: - Probe spec

  private struct ProbeSpec {
    let kind: EntityKind
    let entityId: String
    let table: String
    let pkColumns: [String]
    let pkValues: [String]
    let isEdge: Bool
    var overrides: [String: Seed] = [:]
    var exclusions: Set<String> = []
    var variants: [[String: Seed]] = [[:]]
    var parents: [ParentKind] = []
  }

  // MARK: - Column enumeration + sentinel synthesis

  private func pragmaCols(_ db: Database, _ table: String) throws -> [(name: String, type: String)] {
    try Row.fetchAll(db, sql: "SELECT name, type FROM pragma_table_info('\(table)') ORDER BY cid")
      .filter { !StorageSchema.isDeviceLocalColumn(table: table, column: $0["name"] as String) }
      .map { (name: $0["name"] as String, type: ($0["type"] as String?) ?? "") }
  }

  /// Synthesize a distinctive, constraint-satisfying sentinel for a column.
  /// Precedence: variant patch → entity override → type/name heuristic. The
  /// heuristic covers the common unconstrained shapes so a freshly-added free
  /// column round-trips without a hand-written override.
  private func sentinel(
    _ col: String, type: String, table: String, overrides: [String: Seed],
    variant: [String: Seed]
  ) -> Seed {
    if let v = variant[col] { return v }
    if let o = overrides[col] { return o }
    let t = type.uppercased()
    if t.contains("INT") { return .int(4242) }
    if col.hasSuffix("_at") { return .text("2029-02-03T04:05:06.000Z") }
    if col == "date" || col.hasSuffix("_date") { return .text("2029-01-02") }
    if col.hasSuffix("_time") { return .text("03:04") }
    return .text("PROBE_\(table)_\(col)")
  }

  private func insertRow(
    _ db: Database, table: String, cols: [String], seed: [String: Seed]
  ) throws {
    let colList = cols.joined(separator: ", ")
    let placeholders = cols.map { ":\($0)" }.joined(separator: ", ")
    var args: [String: DatabaseValueConvertible?] = [:]
    for c in cols { args[c] = (seed[c] ?? .null).db }
    try db.execute(
      sql: "INSERT INTO \(table) (\(colList)) VALUES (\(placeholders))",
      arguments: StatementArguments(args))
  }

  private func whereClause(_ spec: ProbeSpec) -> String {
    spec.pkColumns.map { "\($0) = ?" }.joined(separator: " AND ")
  }

  private func pkArgs(_ spec: ProbeSpec) -> StatementArguments {
    StatementArguments(spec.pkValues)
  }

  /// Build a composite edge payload through the same production loader/helper
  /// used by normal writes and full-resync backfill. This must never regress to a
  /// pragma-built test double: such a double can agree with the schema while the
  /// real loader silently omits a field.
  private func productionEdgePayload(_ db: Database, _ spec: ProbeSpec) throws -> JSONValue {
    switch spec.kind {
    case .taskTag:
      return try XCTUnwrap(
        PayloadLoaders.loadTaskTagSyncPayload(
          db, taskId: spec.pkValues[0], tagId: spec.pkValues[1]))
    case .taskDependency:
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT version, created_at FROM task_dependencies "
            + "WHERE task_id = ? AND depends_on_task_id = ?",
          arguments: pkArgs(spec)))
      return PayloadLoaders.taskDependencyPayload(
        taskId: spec.pkValues[0], dependsOnTaskId: spec.pkValues[1],
        version: row["version"], createdAt: row["created_at"])
    case .taskCalendarEventLink:
      return try XCTUnwrap(
        PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
          db, taskId: spec.pkValues[0], calendarEventId: spec.pkValues[1]))
    case .habitCompletion:
      return try XCTUnwrap(
        PayloadLoaders.loadHabitCompletionSyncPayload(
          db, habitId: spec.pkValues[0], completedDate: spec.pkValues[1]))
    default:
      throw StoreError.invariant("\(spec.kind.asString) is not a composite edge probe")
    }
  }

  // MARK: - Runner

  private func runProbe(_ spec: ProbeSpec, file: StaticString = #filePath, line: UInt = #line) throws {
    for (index, variant) in spec.variants.enumerated() {
      try runVariant(spec, variant: variant, index: index, file: file, line: line)
    }
  }

  private func runVariant(
    _ spec: ProbeSpec, variant: [String: Seed], index: Int, file: StaticString, line: UInt
  ) throws {
    let source = try SyncTestSupport.freshStore()
    let peer = try SyncTestSupport.freshStore()

    var overrides = spec.overrides
    if overrides["version"] == nil { overrides["version"] = .text(zeroHlc) }

    var cols: [(name: String, type: String)] = []
    var srcValues: [String: DatabaseValue] = [:]
    var envelope: SyncEnvelope?

    try source.writer.write { db in
      cols = try pragmaCols(db, spec.table)
      try seedParents(db, spec.parents)

      var seed: [String: Seed] = [:]
      for c in cols {
        seed[c.name] = sentinel(
          c.name, type: c.type, table: spec.table, overrides: overrides, variant: variant)
      }
      try insertRow(db, table: spec.table, cols: cols.map { $0.name }, seed: seed)

      if spec.isEdge {
        let payload = try productionEdgePayload(db, spec)
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: spec.kind.asString, entityId: spec.entityId, payload: payload,
          context: OutboxWriteContext(version: contextVersion, deviceId: deviceId))
      } else {
        let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: spec.kind.asString, entityId: spec.entityId)
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: spec.kind.asString, entityId: spec.entityId, payload: payload,
          context: OutboxWriteContext(version: contextVersion, deviceId: deviceId))
      }

      envelope = try Outbox.getPending(db).first {
        $0.envelope.entityType == spec.kind && $0.envelope.entityId == spec.entityId
      }?.envelope

      // Post-enqueue: the row's version is stamped to the context version, so
      // reading the source row here captures the exact state that shipped.
      let srcRow = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT * FROM \(spec.table) WHERE \(whereClause(spec))", arguments: pkArgs(spec)),
        file: file, line: line)
      for c in cols { srcValues[c.name] = srcRow[c.name] }
    }

    let env = try XCTUnwrap(
      envelope, "no outbound envelope produced for \(spec.kind.asString)", file: file, line: line)
    XCTAssertEqual(env.operation, .upsert, file: file, line: line)
    XCTAssertEqual(
      env.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion,
      file: file, line: line)
    XCTAssertEqual(
      try SyncPayloadContractFixture.violations(for: env), [],
      "FINAL OUTBOX PAYLOAD CONTRACT GAP: \(spec.kind.asString) emitted \(env.payload)",
      file: file, line: line)

    var peerValues: [String: DatabaseValue] = [:]
    try peer.writer.write { db in
      try seedParents(db, spec.parents)
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      XCTAssertEqual(
        result, .applied,
        "peer must APPLY the \(spec.kind.asString) envelope (variant \(index)); a deferral/skip "
          + "means the round-trip never landed: \(result)",
        file: file, line: line)
      let peerRow = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT * FROM \(spec.table) WHERE \(whereClause(spec))", arguments: pkArgs(spec)),
        "peer row absent after applying \(spec.kind.asString)", file: file, line: line)
      for c in cols { peerValues[c.name] = peerRow[c.name] }
    }

    for c in cols where !spec.exclusions.contains(c.name) {
      let s = srcValues[c.name] ?? .null
      let p = peerValues[c.name] ?? .null
      XCTAssertEqual(
        p, s,
        "FIELD ROUND-TRIP GAP: \(spec.kind.asString).\(c.name) did not round-trip — the peer value "
          + "(\(p)) != the source sentinel (\(s)) [variant \(index)]. A schema column loses data "
          + "silently across devices if it is dropped at EITHER end: omitted from the OUTBOUND "
          + "payload (for a descriptor-migrated entity, missing from its SyncEntityDescriptor outbound "
          + "columns) OR shipped but not written by the INBOUND applier. Add the column to the "
          + "outbound source (descriptor or builder) AND wire the applier.",
        file: file, line: line)
    }
  }

  // MARK: - Aggregate roots / simple-PK entities (real snapshot outbound path)

  func testRoundTripTask() throws {
    let taskVersion = "1743275000000_0001_feedfacefeedface"
    let instanceKey = try XCTUnwrap(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: pRecurrenceGroup,
        canonicalOccurrenceDate: "2029-01-02"))
    try runProbe(
      ProbeSpec(
        kind: .task, entityId: pRecurringSuccessor, table: "tasks", pkColumns: ["id"],
        pkValues: [pRecurringSuccessor],
        isEdge: false,
        overrides: [
          "id": .text(pRecurringSuccessor), "list_id": .text(pList),
          "status": .text("completed"),
          "priority": .int(2), "estimated_minutes": .int(90), "last_defer_reason": .text("blocked"),
          "recurrence_group_id": .text(pRecurrenceGroup),
          "recurrence_instance_key": .text(instanceKey),
          "spawned_from": .text(pTask),
          "spawned_from_version": .text(pParentAuthorization),
          "content_version": .text("1743271000000_0001_1111111111111111"),
          "schedule_version": .text("1743272000000_0001_2222222222222222"),
          "lifecycle_version": .text("1743273000000_0001_3333333333333333"),
          "archive_version": .text("1743274000000_0001_4444444444444444"),
          "recurrence_rollover_state": .text("ended"),
          "recurrence_successor_id": .null,
          "version": .text(taskVersion),
          // `available_from` is a civil date validated on apply, but its name
          // does not match the `_date` heuristic, so seed a valid date directly.
          "available_from": .text("2029-01-02"),
          // A valid rule so the row applies; `recurrence` requires non-null
          // due_date / recurrence_group_id / canonical_occurrence_date (schema
          // CHECK), all of which the heuristic seeds. Excluded from the value
          // assertion because apply normalizes it to canonical form.
          "recurrence": .text(#"{"FREQ":"DAILY"}"#),
        ],
        exclusions: ["recurrence"],
        parents: [.recurringTask]))
  }

  func testRoundTripList() throws {
    try runProbe(
      ProbeSpec(
        kind: .list, entityId: uuid(2), table: "lists", pkColumns: ["id"], pkValues: [uuid(2)],
        isEdge: false, overrides: ["id": .text(uuid(2))]))
  }

  func testRoundTripHabit() throws {
    try runProbe(
      ProbeSpec(
        kind: .habit, entityId: uuid(3), table: "habits", pkColumns: ["id"], pkValues: [uuid(3)],
        isEdge: false,
        overrides: [
          "id": .text(uuid(3)), "name": .text("Probe Habit"),
          "lookup_key": .text("probe habit"), "archived": .int(1),
          // `icon` is validated as an SF Symbol token / emoji and `color` as a
          // CSS hex on apply; both are stored verbatim, so they still round-trip.
          "icon": .text("star.fill"), "color": .text("#4287f5"),
        ],
        // `per_period_target` and `day_of_month` are cadence-coupled: apply routes
        // them through `HabitCadence.fromFields`, which normalizes each to its
        // cadence's meaningful subset (per_period_target → 1 unless
        // `times_per_week`; day_of_month → NULL unless `monthly`). Probe each
        // under the cadence that preserves it; seed the other to its normalized
        // value so the (correct) canonicalization is not flagged as a gap.
        variants: [
          ["frequency_type": .text("times_per_week"), "per_period_target": .int(5),
           "day_of_month": .null],
          ["frequency_type": .text("monthly"), "day_of_month": .int(15),
           "per_period_target": .int(1)],
        ]))
  }

  func testRoundTripTag() throws {
    try runProbe(
      ProbeSpec(
        kind: .tag, entityId: uuid(4), table: "tags", pkColumns: ["id"], pkValues: [uuid(4)],
        isEdge: false,
        overrides: [
          "id": .text(uuid(4)), "display_name": .text("Probe Tag"),
          "lookup_key": .text("probe tag"),
        ]))
  }

  func testRoundTripCalendarEvent() throws {
    try runProbe(
      ProbeSpec(
        kind: .calendarEvent, entityId: uuid(5), table: "calendar_events", pkColumns: ["id"],
        pkValues: [uuid(5)], isEdge: false,
        overrides: [
          "id": .text(uuid(5)), "event_type": .text("birthday"),
          "timezone": .text("America/Los_Angeles"),
          // Valid calendar URL scheme (validated on apply, stored verbatim).
          "url": .text("https://probe.example.com/e"),
          // `attendees` is a JSON-in-TEXT column (json_valid CHECK); seed an
          // already-canonical array so the parse→re-serialize round-trip is the
          // identity and matches the applied peer column byte-for-byte.
          "attendees": .text(#"[{"email":"probe@example.com"}]"#),
          "occurrence_state": .null,
          "content_version": .text(zeroHlc),
          "recurrence_topology_version": .text(zeroHlc),
          "series_cutover_id": .null,
          "series_id": .null,
          "recurrence_instance_date": .null,
        ],
        exclusions: ["recurrence"],
        // `all_day` couples with start_time/end_time. Occurrence decisions have
        // deterministic ids and are covered by their dedicated sync suite; these
        // variants probe a recurring master through both timing shapes.
        variants: [
          [
            "all_day": .int(1), "start_time": .null, "end_time": .null,
            "series_id": .null, "recurrence_instance_date": .null,
            "recurrence": .text(#"{"FREQ":"DAILY"}"#),
            "recurrence_generation": .text(zeroHlc),
          ],
          [
            "all_day": .int(0), "series_id": .null,
            "recurrence_instance_date": .null,
            "recurrence": .text(#"{"FREQ":"DAILY"}"#),
            "recurrence_generation": .text(zeroHlc),
          ],
        ]))

    // A null marker above proves the field is represented, but cannot catch an
    // outbound/inbound implementation that always drops non-null marker values.
    // Probe one real segment identity behind its active durable boundary too.
    try runProbe(
      ProbeSpec(
        kind: .calendarEvent, entityId: pCutover, table: "calendar_events",
        pkColumns: ["id"], pkValues: [pCutover], isEdge: false,
        overrides: [
          "id": .text(pCutover), "title": .text("Probe cutover segment"),
          "start_date": .text(pCutoverDate), "end_date": .text(pCutoverDate),
          "all_day": .int(1), "start_time": .null, "end_time": .null,
          "event_type": .text("event"), "timezone": .text("America/Los_Angeles"),
          "url": .text("https://probe.example.com/segment"),
          "attendees": .text(#"[{"email":"probe@example.com"}]"#),
          "series_cutover_id": .text(pCutover), "series_id": .null,
          "recurrence_instance_date": .null, "occurrence_state": .null,
          "recurrence": .null, "recurrence_generation": .null,
          "recurrence_topology_version": .text(zeroHlc),
          "content_version": .text(zeroHlc),
        ],
        exclusions: ["recurrence"], parents: [.calendarCutover]))
  }

  func testRoundTripCalendarSeriesCutover() throws {
    try runProbe(
      ProbeSpec(
        kind: .calendarSeriesCutover, entityId: pCutover,
        table: "calendar_series_cutovers", pkColumns: ["id"], pkValues: [pCutover],
        isEdge: false,
        overrides: [
          "id": .text(pCutover), "lineage_root_id": .text(pCutoverRoot),
          "cutover_date": .text(pCutoverDate), "state": .text("active"),
        ]))
  }

  func testRoundTripPreference() throws {
    try runProbe(
      ProbeSpec(
        kind: .preference, entityId: PreferenceKeys.prefWorkingHours, table: "preferences",
        pkColumns: ["key"], pkValues: [PreferenceKeys.prefWorkingHours], isEdge: false,
        overrides: [
          "key": .text(PreferenceKeys.prefWorkingHours),
          // `value` is JSON-in-TEXT; seed already-canonical JSON so the
          // typed preference validation and parse→re-serialize round-trip are
          // both exercised without relying on an invalid generic sentinel.
          "value": .text(#"{"end":"17:37","start":"08:13"}"#),
        ]))
  }

  func testRoundTripMemory() throws {
    try runProbe(
      ProbeSpec(
        kind: .memory, entityId: uuid(6), table: "memories", pkColumns: ["id"], pkValues: [uuid(6)],
        isEdge: false, overrides: ["id": .text(uuid(6))]))
  }

  func testRoundTripDailyReview() throws {
    try runProbe(
      ProbeSpec(
        kind: .dailyReview, entityId: "2029-03-01", table: "daily_reviews", pkColumns: ["date"],
        pkValues: ["2029-03-01"], isEdge: false,
        overrides: [
          "date": .text("2029-03-01"), "mood": .int(4), "energy_level": .int(3),
          "timezone": .text("America/Los_Angeles"),
        ]))
  }

  func testRoundTripCurrentFocus() throws {
    try runProbe(
      ProbeSpec(
        kind: .currentFocus, entityId: "2029-03-02", table: "current_focus", pkColumns: ["date"],
        pkValues: ["2029-03-02"], isEdge: false,
        overrides: [
          "date": .text("2029-03-02"), "timezone": .text("America/Los_Angeles"),
        ]))
  }

  func testRoundTripFocusSchedule() throws {
    try runProbe(
      ProbeSpec(
        kind: .focusSchedule, entityId: "2029-03-03", table: "focus_schedule", pkColumns: ["date"],
        pkValues: ["2029-03-03"], isEdge: false,
        overrides: [
          "date": .text("2029-03-03"), "timezone": .text("America/Los_Angeles"),
        ]))
  }

  func testRoundTripTaskReminder() throws {
    try runProbe(
      ProbeSpec(
        kind: .taskReminder, entityId: uuid(8), table: "task_reminders", pkColumns: ["id"],
        pkValues: [uuid(8)], isEdge: false,
        overrides: [
          "id": .text(uuid(8)), "task_id": .text(pTask),
          "original_tz": .text("America/Los_Angeles"),
        ],
        parents: [.task]))
  }

  func testRoundTripTaskChecklistItem() throws {
    try runProbe(
      ProbeSpec(
        kind: .taskChecklistItem, entityId: uuid(9), table: "task_checklist_items",
        pkColumns: ["id"], pkValues: [uuid(9)], isEdge: false,
        overrides: ["id": .text(uuid(9)), "task_id": .text(pTask)],
        parents: [.task]))
  }

  func testRoundTripHabitReminderPolicy() throws {
    try runProbe(
      ProbeSpec(
        kind: .habitReminderPolicy, entityId: uuid(10), table: "habit_reminder_policies",
        pkColumns: ["id"], pkValues: [uuid(10)], isEdge: false,
        overrides: ["id": .text(uuid(10)), "habit_id": .text(pHabit), "enabled": .int(1)],
        parents: [.habit]))
  }

  // MARK: - Composite edges (production loader, real inbound applier)

  func testRoundTripTaskTag() throws {
    try runProbe(
      ProbeSpec(
        kind: .taskTag, entityId: "\(pTask):\(pTag)", table: "task_tags",
        pkColumns: ["task_id", "tag_id"], pkValues: [pTask, pTag], isEdge: true,
        overrides: ["task_id": .text(pTask), "tag_id": .text(pTag)],
        parents: [.task, .tag]))
  }

  func testRoundTripTaskDependency() throws {
    try runProbe(
      ProbeSpec(
        kind: .taskDependency, entityId: "\(pTask):\(pTask2)", table: "task_dependencies",
        pkColumns: ["task_id", "depends_on_task_id"], pkValues: [pTask, pTask2], isEdge: true,
        overrides: ["task_id": .text(pTask), "depends_on_task_id": .text(pTask2)],
        parents: [.task, .task2]))
  }

  func testRoundTripTaskCalendarEventLink() throws {
    try runProbe(
      ProbeSpec(
        kind: .taskCalendarEventLink, entityId: "\(pTask):\(pEvent)",
        table: "task_calendar_event_links", pkColumns: ["task_id", "calendar_event_id"],
        pkValues: [pTask, pEvent], isEdge: true,
        overrides: ["task_id": .text(pTask), "calendar_event_id": .text(pEvent)],
        parents: [.task, .event]))
  }

  func testRoundTripHabitCompletion() throws {
    try runProbe(
      ProbeSpec(
        kind: .habitCompletion, entityId: "\(pHabit):2029-03-04", table: "habit_completions",
        pkColumns: ["habit_id", "completed_date"], pkValues: [pHabit, "2029-03-04"], isEdge: true,
        overrides: [
          "habit_id": .text(pHabit), "completed_date": .text("2029-03-04"), "value": .int(3),
        ],
        parents: [.habit]))
  }

  // MARK: - Coverage guard

  /// Every syncable kind (except the append-only `ai_changelog` audit stream,
  /// documented above) must have a field round-trip probe, so a future kind
  /// added to `allSyncableTypes` fails here until it is covered.
  func testEverySyncableKindHasARoundTripProbe() {
    let covered: Set<String> = [
      EntityName.task, EntityName.list, EntityName.habit, EntityName.tag,
      EntityName.calendarEvent, EntityName.calendarSeriesCutover,
      EntityName.preference, EntityName.memory,
      EntityName.dailyReview, EntityName.currentFocus,
      EntityName.focusSchedule, EntityName.taskReminder, EntityName.taskChecklistItem,
      EntityName.habitReminderPolicy, EdgeName.taskTag, EdgeName.taskDependency,
      EdgeName.taskCalendarEventLink, EdgeName.habitCompletion,
    ]
    let documentedExclusions: Set<String> = [EntityName.aiChangelog, EntityName.entityRedirect]
    for type in EntityKind.allSyncableTypes {
      if documentedExclusions.contains(type) { continue }
      XCTAssertTrue(
        covered.contains(type),
        "syncable kind '\(type)' has no field round-trip probe — add one so its columns are guarded "
          + "against outbound/inbound field-set asymmetry")
    }
  }
}
