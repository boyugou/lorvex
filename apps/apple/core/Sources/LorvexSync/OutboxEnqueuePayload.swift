import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension OutboxEnqueue {

  // MARK: - Snapshot reading

  /// Read the current snapshot of an entity from the DB as a JSON value.
  ///
  /// Routing by entity type:
  /// - Aggregate roots with dedicated composition (`current_focus`,
  ///   `focus_schedule`, `daily_review`, `calendar_event`) go through
  ///   ``PayloadBuild/buildAggregatePayload(_:entityType:entityId:)`` — the SOLE
  ///   payload source for these kinds. A missing parent header resolves to
  ///   ``EnqueueError/entityNotFound(entityType:entityId:)`` (never a
  ///   fall-through to the bare-columns reader, which would ship a child-less
  ///   envelope).
  /// - `preference` / `habit` use their dedicated store-owned loaders
  ///   (`preferences.value` is JSON-in-TEXT; a habit's `weekly` weekday set lives
  ///   in the `habit_weekdays` child — not a `habits` column the generic reader
  ///   could see — and its `lookup_key` is a peer-re-derived local column the wire
  ///   shape omits).
  /// - Everything else falls back to the generic reader. Migrated entities use
  ///   their descriptor's outbound projection (excluding derived-local storage);
  ///   legacy entities use `pragma_table_info`. Both paths apply SQLite-bool →
  ///   JSON-bool coercion and reject invalid UTF-8.
  public static func readEntityPayloadSnapshot(
    _ db: Database, entityType: String, entityId: String
  ) throws -> JSONValue {
    if let kind = EntityKind.parse(entityType), kind.isEdge {
      return try readCompositeEdgePayloadSnapshot(db, kind: kind, entityId: entityId)
    }

    if let kind = EntityKind.parse(entityType),
      PayloadBuild.kindNeedsDedicatedComposition(kind)
    {
      let built = try mapStore {
        try PayloadBuild.buildAggregatePayload(db, entityType: entityType, entityId: entityId)
      }
      guard let payload = built else {
        throw EnqueueError.entityNotFound(entityType: entityType, entityId: entityId)
      }
      return try aggregatePayloadCarryingStoredVersion(
        db, kind: kind, entityId: entityId, payload: payload)
    }

    if entityType == EntityName.preference {
      guard
        let payload = try mapStore({
          try PayloadLoaders.loadPreferenceSyncPayload(db, key: entityId)
        })
      else {
        throw EnqueueError.entityNotFound(entityType: entityType, entityId: entityId)
      }
      return payload
    }

    if entityType == EntityName.task {
      let payload = try readGenericEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
      guard case .object(var object) = payload else { return payload }
      let exceptionsJSON = try mapStore {
        try RecurrenceExceptionsRepo.loadTaskExceptionsJSON(db, taskId: entityId)
      }
      object["recurrence_exceptions"] = exceptionsJSON.map(JSONValue.string) ?? .null
      return .object(object)
    }

    if entityType == EntityName.habit {
      guard
        let payload = try mapStore({
          try PayloadLoaders.loadHabitSyncPayload(db, habitId: entityId)
        })
      else {
        throw EnqueueError.entityNotFound(entityType: entityType, entityId: entityId)
      }
      return payload
    }

    return try readGenericEntityPayloadSnapshot(db, entityType: entityType, entityId: entityId)
  }

  /// Attach an aggregate root's stored HLC to its composed snapshot.
  ///
  /// ``PayloadBuild`` deliberately composes business fields and embedded child
  /// collections without transport metadata. The shared snapshot reader also
  /// serves pre-delete capture, though: after the parent row is removed there is
  /// no other place to recover a peer-authored future version. Preserving it here
  /// lets the delete enqueue detect a losing local stamp and replay the whole
  /// mutation in the detached HLC lane. Upsert enqueue always replaces this key
  /// with its caller-supplied version, so the captured value cannot leak as stale
  /// transport metadata.
  private static func aggregatePayloadCarryingStoredVersion(
    _ db: Database, kind: EntityKind, entityId: String, payload: JSONValue
  ) throws -> JSONValue {
    guard let (table, pk) = kind.tablePk else {
      throw EnqueueError.unknownEntityType(kind.asString)
    }
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(pk)
    guard case .object(var object) = payload,
      let version = try String.fetchOne(
        db, sql: "SELECT version FROM \(table) WHERE \(pk) = ?", arguments: [entityId])
    else {
      throw EnqueueError.entityNotFound(entityType: kind.asString, entityId: entityId)
    }
    object["version"] = .string(version)
    return .object(object)
  }

  /// Read one composite-key edge through the same dedicated loader used by its
  /// ordinary write funnel. Edge kinds intentionally have no `tablePk`, so they
  /// cannot fall through to the generic single-primary-key reader.
  private static func readCompositeEdgePayloadSnapshot(
    _ db: Database, kind: EntityKind, entityId: String
  ) throws -> JSONValue {
    let left: String
    let right: String
    switch CompositeEdge.splitCompositeEdgeId(entityId) {
    case .success(let pair):
      (left, right) = pair
    case .failure(let error):
      throw EnqueueError.store(.validation(error.description))
    }

    let payload: JSONValue?
    do {
      switch kind {
      case .taskTag:
        payload = try PayloadLoaders.loadTaskTagSyncPayload(
          db, taskId: left, tagId: right)
      case .taskDependency:
        payload = try Row.fetchOne(
          db,
          sql: "SELECT version, created_at FROM task_dependencies "
            + "WHERE task_id = ? AND depends_on_task_id = ?",
          arguments: [left, right]
        ).map {
          PayloadLoaders.taskDependencyPayload(
            taskId: left, dependsOnTaskId: right,
            version: $0["version"], createdAt: $0["created_at"])
        }
      case .taskCalendarEventLink:
        payload = try PayloadLoaders.loadTaskCalendarEventLinkSyncPayload(
          db, taskId: left, calendarEventId: right)
      case .habitCompletion:
        payload = try PayloadLoaders.loadHabitCompletionSyncPayload(
          db, habitId: left, completedDate: right)
      default:
        throw EnqueueError.unknownEntityType(kind.asString)
      }
    } catch let error as EnqueueError {
      throw error
    } catch let error as StoreError {
      throw EnqueueError.store(error)
    } catch {
      throw EnqueueError.sqlite(error)
    }
    guard let payload else {
      throw EnqueueError.entityNotFound(entityType: kind.asString, entityId: entityId)
    }
    return payload
  }

  private static func readGenericEntityPayloadSnapshot(
    _ db: Database, entityType: String, entityId: String
  ) throws -> JSONValue {
    let (table, pkCol) = try entityTypeToTable(entityType)
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(pkCol)

    // A migrated entity's outbound column set derives from its
    // ``SyncEntityDescriptor`` outbound columns instead of raw
    // `pragma_table_info`. A descriptor may also contain derived-local storage
    // columns used only by the inbound applier; those never enter this SELECT.
    // The shadow layer still classifies them as locally understood so a peer
    // cannot make this runtime preserve and re-emit one as an unknown key. The
    // device-local filter still applies (a descriptor column classified
    // device-local is never shipped).
    // Entities without a descriptor keep the pragma-driven reader.
    let sourceColumns: [String]
    if let descriptor = SyncEntityDescriptor.descriptor(for: entityType) {
      sourceColumns = descriptor.outboundColumns
    } else {
      sourceColumns = try pragmaTableColumns(db, table: table)
    }
    let columns = sourceColumns.filter {
      !StorageSchema.isDeviceLocalColumn(table: table, column: $0)
    }
    if columns.isEmpty {
      throw EnqueueError.unknownEntityType("(table \(table) has no columns)")
    }
    for col in columns {
      ValidationSQL.assertSafeSQLIdentifier(col)
    }
    let colList = columns.joined(separator: ", ")
    let selectSql = "SELECT \(colList) FROM \(table) WHERE \(pkCol) = ?"

    guard let row = try fetchRow(db, sql: selectSql, arguments: [entityId]) else {
      throw EnqueueError.entityNotFound(entityType: entityType, entityId: entityId)
    }
    var obj: [String: JSONValue] = [:]
    for col in columns {
      obj[col] = try sqliteColumnValueToJSON(table: table, column: col, dbValue: row[col])
    }
    return .object(obj)
  }

  /// Resolve an entity type string to its `(table, pkColumn)` pair via
  /// ``EntityKind/tablePk``. Unknown / composite kinds surface
  /// ``EnqueueError/unknownEntityType(_:)``.
  static func entityTypeToTable(_ entityType: String) throws -> (String, String) {
    guard let kind = EntityKind.parse(entityType), let pair = kind.tablePk else {
      throw EnqueueError.unknownEntityType(entityType)
    }
    return pair
  }

  private static func pragmaTableColumns(_ db: Database, table: String) throws -> [String] {
    ValidationSQL.assertSafeSQLIdentifier(table)
    do {
      return try String.fetchAll(
        db, sql: "SELECT name FROM pragma_table_info('\(table)') ORDER BY cid")
    } catch { throw EnqueueError.sqlite(error) }
  }

  private static func fetchRow(
    _ db: Database, sql: String, arguments: StatementArguments
  ) throws -> Row? {
    do {
      return try Row.fetchOne(db, sql: sql, arguments: arguments)
    } catch { throw EnqueueError.sqlite(error) }
  }

  /// Convert one SQLite column value to its canonical JSON form. SQLite-bool
  /// columns coerce 0/1 → JSON bool (any other integer is a serialization
  /// error); TEXT must be valid UTF-8 (GRDB decodes it as `String`, so a row
  /// written with invalid bytes through the BLOB path would surface as a typed
  /// store error before it could poison a peer envelope); BLOB is hex-encoded.
  private static func sqliteColumnValueToJSON(
    table: String, column: String, dbValue: DatabaseValue
  ) throws -> JSONValue {
    if StorageSchema.isSqliteBoolColumn(table: table, column: column) {
      switch dbValue.storage {
      case .null:
        return .null
      case .int64(let n):
        if n == 0 { return .bool(false) }
        if n == 1 { return .bool(true) }
        throw EnqueueError.store(
          .serialization("\(table).\(column) must be 0 or 1 before sync enqueue, got \(n)"))
      default:
        throw EnqueueError.store(
          .serialization(
            "\(table).\(column) must be a SQLite integer boolean before sync enqueue"))
      }
    }

    switch dbValue.storage {
    case .null:
      return .null
    case .int64(let n):
      return .int(n)
    case .double(let d):
      return SerdeSupport.sqliteRealToJson(d)
    case .string(let s):
      return .string(s)
    case .blob(let data):
      let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
      var hex = [UInt8]()
      hex.reserveCapacity(data.count * 2)
      for b in data {
        hex.append(hexDigits[Int(b >> 4)])
        hex.append(hexDigits[Int(b & 0x0F)])
      }
      return .string(String(decoding: hex, as: UTF8.self))
    }
  }

  // MARK: - Public upsert / delete entry points

  /// Enqueue an Upsert envelope for `payload`. Version-stamps the row, clears
  /// any stale local tombstone, merges the payload with its forward-compat
  /// shadow, injects the canonical `version`, and builds + coalesces the
  /// envelope.
  public static func enqueuePayloadUpsert(
    _ db: Database,
    entityType: String,
    entityId: String,
    payload: JSONValue,
    context: OutboxWriteContext
  ) throws {
    _ = try enqueuePayloadInternal(
      db, entityType: entityType, entityId: entityId, operation: .upsert,
      payload: payload, context: context)
  }

  /// Enqueue a Delete envelope for `payload` (the caller-supplied pre-delete
  /// snapshot — Delete never re-reads the row, which is typically already gone).
  /// Removes the payload shadow, coalesces the Delete envelope, and mints a
  /// local tombstone when the Delete actually entered the outbox.
  public static func enqueuePayloadDelete(
    _ db: Database,
    entityType: String,
    entityId: String,
    payload: JSONValue,
    context: OutboxWriteContext
  ) throws {
    _ = try enqueuePayloadInternal(
      db, entityType: entityType, entityId: entityId, operation: .delete,
      payload: payload, context: context)
  }

  /// Full-resync-only variant that exposes whether coalescing inserted a fresh
  /// unsynced row. Ordinary write funnels intentionally use the Void APIs above;
  /// recovery reporting needs this result so it never counts a preserved
  /// equal/newer queued row as a new emission.
  static func enqueuePayloadUpsertReportingInsertion(
    _ db: Database, entityType: String, entityId: String, payload: JSONValue,
    context: OutboxWriteContext
  ) throws -> Bool {
    try enqueuePayloadInternal(
      db, entityType: entityType, entityId: entityId, operation: .upsert,
      payload: payload, context: context) != nil
  }

  /// Delete twin of ``enqueuePayloadUpsertReportingInsertion``.
  static func enqueuePayloadDeleteReportingInsertion(
    _ db: Database, entityType: String, entityId: String, payload: JSONValue,
    context: OutboxWriteContext
  ) throws -> Bool {
    try enqueuePayloadInternal(
      db, entityType: entityType, entityId: entityId, operation: .delete,
      payload: payload, context: context) != nil
  }

  /// Emit the ordinary delete record for an identity that already has a
  /// permanent alias. Normal caller-authored deletes against an alias are
  /// dropped; aggregate merge and full-resync recovery use this narrow bypass to
  /// replace a stale loser upsert in the shared domain-record namespace.
  @discardableResult
  static func enqueueAliasSourceDelete(
    _ db: Database, entityType: String, entityId: String, version: String,
    deviceId: String
  ) throws -> Bool {
    try StoreTransactions.withSavepoint(db, "enqueue_alias_source_delete") { db in
      try enqueuePayloadInternalBody(
        db, entityType: entityType, entityId: entityId, operation: .delete,
        payload: .object([:]), context: OutboxWriteContext(version: version, deviceId: deviceId),
        resolveRedirects: false) != nil
    }
  }

  // MARK: - Internal pipeline

  private static func enqueuePayloadInternal(
    _ db: Database,
    entityType: String,
    entityId: String,
    operation: SyncOperation,
    payload: JSONValue,
    context: OutboxWriteContext
  ) throws -> Int64? {
    // The five writes (version stamp, shadow merge/remove, coalesce's
    // SELECT/DELETE/INSERT, tombstone mint) must all
    // commit or all roll back. GRDB's `write` block is already an open
    // transaction; the SAVEPOINT nests cleanly and gives all-or-nothing
    // atomicity.
    return try StoreTransactions.withSavepoint(db, "enqueue_payload") { db in
      try enqueuePayloadInternalBody(
        db, entityType: entityType, entityId: entityId, operation: operation,
        payload: payload, context: context, resolveRedirects: true)
    }
  }

  private static func enqueuePayloadInternalBody(
    _ db: Database,
    entityType: String,
    entityId: String,
    operation: SyncOperation,
    payload: JSONValue,
    context: OutboxWriteContext,
    resolveRedirects: Bool
  ) throws -> Int64? {
    // Validate every ordering/routing value before the first read that can lead
    // to a write. In particular, schema-level canonical-HLC CHECKs must never
    // fire after `VersionStamp` has already touched a row; callers receive the
    // stable typed enqueue error and the savepoint remains mutation-free.
    guard let entityKind = EntityKind.parse(entityType) else {
      throw EnqueueError.unknownEntityType(entityType)
    }
    if entityKind == .preference,
      PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId)
    {
      throw EnqueueError.unsupportedOperation(
        entityType: entityType, operation: operation.asString)
    }
    let typedVersion: Hlc
    do {
      typedVersion = try Hlc.parseCanonical(context.version)
    } catch {
      throw EnqueueError.taintedVersion(
        entityType: entityKind, entityId: entityId, version: context.version)
    }
    guard Hlc.isOperationallyAcceptableWire(typedVersion) else {
      throw EnqueueError.operationalHlcCeilingExceeded(
        entityType: entityType, entityId: entityId, version: context.version)
    }
    if entityType == EntityName.entityRedirect {
      throw EnqueueError.unsupportedOperation(
        entityType: entityType, operation: operation.asString)
    }

    if resolveRedirects, entityType != EntityName.entityRedirect {
      let redirect: EntityRedirect.Record?
      do {
        redirect = try EntityRedirect.get(db, sourceType: entityType, sourceId: entityId)
      } catch {
        throw EnqueueError.sqlite(error)
      }
      if let redirect {
        if operation == .delete {
          // A delete authored against a loser identity must never be routed onto
          // the winner and must never erase the permanent alias.
          return nil
        }
        return try enqueueRedirectedLocalUpsert(
          db, entityType: entityType, entityId: entityId, payload: payload,
          context: context, redirect: redirect)
      }
    }

    // A pending/staged future record owns this exact CloudKit slot. Throwing
    // here rolls the caller's canonical mutation and this enqueue back together.
    try FutureRecordHold.requireWriteAllowed(
      db, entityType: entityType, entityId: entityId)
    // 0. Losing-delete guard (SYNC17-HIGH-2). A hard DELETE of a future-stamped
    //    row typically removes the row BEFORE this enqueue (calendar/list bare
    //    DELETE, or the LWW-gated store delete), so the version-stamp step below
    //    hits the benign `entityNotFound` arm and never detects the supersession.
    //    The caller-supplied pre-delete snapshot preserves the row's `version`; if
    //    it DOMINATES the freshly-minted `context.version`, this delete envelope +
    //    tombstone would lose LWW on push (the server's future upsert re-applies)
    //    and the row RESURRECTS. Surface the supersession so the write-surface
    //    retry advances the local clock past the row version and re-runs the whole
    //    delete with a dominating stamp.
    if operation == .delete,
      case .object(let obj) = payload,
      case .string(let payloadVersionStr)? = obj["version"],
      let payloadVersion = try? Hlc.parseCanonical(payloadVersionStr),
      payloadVersion > typedVersion
    {
      throw EnqueueError.versionSuperseded(
        entityType: entityType, entityId: entityId,
        attemptedVersion: context.version, existingVersion: payloadVersionStr)
    }

    // 1. Version-stamp the row. For Delete the row is typically already gone, so
    //    an `entityNotFound` stamp result is expected and benign. `superseded`
    //    lifts into `versionSuperseded` with `attemptedVersion` from the context
    //    (the typed VersionStampError does not carry it).
    do {
      try VersionStamp.stampEntityVersion(
        db, entityType: entityType, entityId: entityId, version: context.version)
    } catch let err as VersionStamp.VersionStampError {
      switch err {
      case .entityNotFound where operation == .delete:
        break
      case .superseded(let et, let id, let existing):
        throw EnqueueError.versionSuperseded(
          entityType: et, entityId: id, attemptedVersion: context.version,
          existingVersion: existing)
      default:
        throw EnqueueError.versionStamp(err)
      }
    } catch {
      throw EnqueueError.sqlite(error)
    }

    // 2. Upsert only: clear any stale local tombstone so a coalesced
    //    UPSERT → DELETE → UPSERT sequence cannot leave a dead tombstone that a
    //    later inbound apply uses to drop a peer's concurrent edit.
    //
    //    The step-1 version_stamp gate compares only against the row's OWN
    //    version, so for a fresh re-INSERT of a natural-key entity (the row was
    //    absent, then just inserted at a local mint) it never consults the death
    //    version of a peer tombstone that DOMINATES this mint. Removing that
    //    tombstone here and shipping the upsert below it would lose LWW on push —
    //    the server's delete wins and the re-create reverts, permanently for a
    //    near-ceiling delete stamp. Mirror the step-0 losing-delete guard: if a
    //    tombstone exists whose death version the incoming upsert
    //    does NOT dominate, surface the supersession so `runWriteAttempt` advances
    //    the clock past it and re-runs; the fresh mint then dominates and the
    //    removal is legitimate. Identity aliases live in a separate permanent
    //    ledger and are handled before this ordinary delete gate.
    if operation == .upsert {
      do {
        if let ts = try Tombstone.getTombstone(db, entityType: entityType, entityId: entityId),
          !canonicalPreferringDominates(incoming: context.version, existing: ts.version)
        {
          throw EnqueueError.versionSuperseded(
            entityType: entityType, entityId: entityId,
            attemptedVersion: context.version, existingVersion: ts.version)
        }
        _ = try Tombstone.removeTombstone(db, entityType: entityType, entityId: entityId)
      } catch let err as EnqueueError {
        throw err
      } catch {
        throw EnqueueError.sqlite(error)
      }
    }

    // 3. Payload transform.
    //    Delete → remove the shadow, payload unchanged.
    //    Upsert → overlay the live payload onto the shadow's forward-compat keys.
    let transformed: JSONValue
    var mergedShadow: PayloadShadow.Row? = nil
    switch operation {
    case .delete:
      // `createTombstone` below also calls `removeShadow`; both
      // fire. The DELETE is idempotent, so the second is a no-op.
      try mapStoreVoid {
        try PayloadShadow.removeShadow(db, entityType: entityType, entityID: entityId)
      }
      transformed = payload
    case .upsert:
      let mergeResult = try mapStore {
        try PayloadShadow.mergePayloadWithShadowReporting(
          db, entityType: entityType, entityID: entityId, knownPayload: payload)
      }
      transformed = mergeResult.payload
      mergedShadow = mergeResult.mergedShadow
      // A-8: the merged shadow still carries the older version it was stashed at
      // while the live row advanced to `context.version`. Bump the shadow's
      // base_version to the row version so a later local schema upgrade promotes
      // its forward-compat keys (the equal-version fill branch) instead of
      // reaping the shadow as obsolete (`live > base`) and losing them.
      if mergedShadow != nil {
        try mapStoreVoid {
          try PayloadShadow.advanceShadowBaseVersion(
            db, entityType: entityType, entityID: entityId, newBaseVersion: context.version)
        }
      }
    }

    // 4. Inject the canonical `version` into the payload object. Upsert always
    //    overwrites; Delete only fills it when the caller's payload lacks one
    //    (preserving the pre-delete row version when present).
    let versioned: JSONValue
    if case .object(var obj) = transformed {
      if operation == .upsert || obj["version"] == nil {
        obj["version"] = .string(context.version)
      }
      versioned = .object(obj)
    } else {
      versioned = transformed
    }

    let isDelete = operation == .delete
    // 5. Validate operation legality. Entity kind and canonical HLC were parsed
    //    before all mutation at the top of this function.
    if (entityKind == .aiChangelog || entityKind == .calendarSeriesCutover),
      operation == .delete
    {
      throw EnqueueError.unsupportedOperation(
        entityType: entityType, operation: operation.asString)
    }
    let canonicalPayload: String
    do {
      canonicalPayload = try SyncCanonicalize.canonicalizeJSON(versioned)
    } catch let err as SyncCanonicalize.SyncCanonError {
      throw EnqueueError.canonicalization(err)
    }

    // A-7: when a forward-compat shadow contributed unknown keys to this
    // outbound payload, stamp the envelope at the shadow's (higher) schema so a
    // same-schema peer takes the parse-forward-compat path and re-stashes those
    // keys, rather than parsing fully and reaping its own shadow (dropping the
    // keys). `max` keeps the local schema when it already meets/exceeds it.
    let effectiveSchemaVersion: UInt32
    if let mergedShadow {
      let shadowSchemaVersion = try mapStore {
        try PayloadShadow.requireWirePayloadSchemaVersion(
          mergedShadow, context: "outbound payload shadow")
      }
      effectiveSchemaVersion = max(LorvexVersion.payloadSchemaVersion, shadowSchemaVersion)
    } else {
      effectiveSchemaVersion = LorvexVersion.payloadSchemaVersion
    }

    let envelope = SyncEnvelope(
      entityType: entityKind,
      entityId: entityId,
      operation: operation,
      version: typedVersion,
      payloadSchemaVersion: effectiveSchemaVersion,
      payload: canonicalPayload,
      deviceId: context.deviceId)

    // 6. Coalesced outbox insert. Returns the new row id, or nil when the
    //    incoming envelope was stale and an existing queued row was preserved.
    let outboxId: Int64?
    do {
      outboxId = try Outbox.enqueueCoalesced(
        db, envelope, registerIntent: context.registerIntent)
    } catch let err as Outbox.OutboxError {
      throw EnqueueError(err)
    }

    // 7. Mint a local tombstone only when the Delete envelope actually entered
    //    the outbox. A Delete the coalescer rejected (in favor of a newer queued
    //    row) must not write a contradicting tombstone.
    if isDelete, outboxId != nil {
      let deletedAt = SyncTimestampFormat.syncTimestampNow()
      try mapStoreVoid {
        try Tombstone.createTombstone(
          db, entityType: entityType, entityId: entityId, version: context.version,
          deletedAt: deletedAt)
      }
    }
    return outboxId
  }

  private static func enqueueRedirectedLocalUpsert(
    _ db: Database, entityType: String, entityId: String, payload: JSONValue,
    context: OutboxWriteContext, redirect: EntityRedirect.Record
  ) throws -> Int64? {
    let chase: ApplyRedirect.ChaseResult
    do {
      chase = try ApplyRedirect.chaseRedirectChain(
        db, initialEntityType: entityType, initialEntityId: entityId)
    } catch { throw EnqueueError.store(.invariant("entity redirect chase failed: \(error)")) }
    guard chase.finalType == entityType, let kind = EntityKind.parse(entityType) else {
      throw EnqueueError.store(.invariant("entity redirect changed entity type"))
    }

    try FutureRecordHold.requireWriteAllowed(
      db, entityType: entityType, entityId: chase.finalId)

    if try EntityRedirect.entityExists(db, kind: kind, entityId: entityId) {
      do {
        try EntityRedirect.mergeLiveSource(
          db, kind: kind, sourceId: entityId, targetId: chase.finalId,
          redirectVersion: context.version, applyTs: SyncTimestampFormat.syncTimestampNow())
      } catch { throw EnqueueError.store(.invariant("stale alias source merge failed: \(error)")) }
      return nil
    }

    var remappedPayload = payload
    _ = ApplyRedirect.remapPayloadIdentityFields(
      entityType: entityType, payload: &remappedPayload,
      originalId: entityId, targetId: chase.finalId)
    let canonical: String
    do {
      canonical = try SyncCanonicalize.canonicalizeJSON(remappedPayload)
    } catch let error as SyncCanonicalize.SyncCanonError {
      throw EnqueueError.canonicalization(error)
    }
    guard let version = try? Hlc.parseCanonical(context.version) else {
      throw EnqueueError.taintedVersion(
        entityType: kind, entityId: chase.finalId, version: context.version)
    }
    let remappedEnvelope = SyncEnvelope(
      entityType: kind, entityId: chase.finalId, operation: .upsert, version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: canonical, deviceId: context.deviceId)
    let result: ApplyResult
    do {
      result = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: remappedEnvelope)
    } catch {
      throw EnqueueError.store(.invariant("redirected local upsert apply failed: \(error)"))
    }
    switch result {
    case .applied, .remapped:
      return try enqueuePayloadInternalBody(
        db, entityType: entityType, entityId: chase.finalId, operation: .upsert,
        payload: remappedPayload, context: context, resolveRedirects: true)
    case .skipped:
      return nil
    case .deferred(let reason):
      throw EnqueueError.store(.invariant("redirected local upsert deferred: \(reason.message)"))
    case .repairRequired, .upsertRejectedByRetention:
      throw EnqueueError.store(.invariant("redirected local upsert reached an invalid outcome"))
    }
  }

  // MARK: - Store-error lifting

  /// Run a `StoreError`/`PayloadError`-throwing store call and lift the error
  /// into the enqueue surface. `StoreError` → ``EnqueueError/store(_:)``;
  /// `PayloadError` maps `.sql` → ``EnqueueError/sqlite(_:)`` and the
  /// validation/invariant/serialization arms → ``EnqueueError/store(_:)``. Any
  /// other thrown error is a SQLite error.
  private static func mapStore<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let err as StoreError {
      throw EnqueueError.store(err)
    } catch let err as PayloadError {
      switch err {
      case .sql(let e):
        throw EnqueueError.sqlite(e)
      case .validation(let m):
        throw EnqueueError.store(.validation(m))
      case .invariant(let m):
        throw EnqueueError.store(.invariant(m))
      case .serialization(let m):
        throw EnqueueError.store(.serialization(m))
      }
    } catch {
      throw EnqueueError.sqlite(error)
    }
  }

  private static func mapStoreVoid(_ body: () throws -> Void) throws {
    try mapStore(body)
  }
}
