import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

struct SyncPayloadArbitraryJSON: Decodable {
  private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  let value: JSONValue

  init(from decoder: Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
      var object: [String: JSONValue] = [:]
      for key in keyed.allKeys {
        object[key.stringValue] = try keyed.decode(
          SyncPayloadArbitraryJSON.self, forKey: key
        ).value
      }
      value = .object(object)
      return
    }
    if var unkeyed = try? decoder.unkeyedContainer() {
      var array: [JSONValue] = []
      while !unkeyed.isAtEnd {
        array.append(try unkeyed.decode(SyncPayloadArbitraryJSON.self).value)
      }
      value = .array(array)
      return
    }

    let scalar = try decoder.singleValueContainer()
    if scalar.decodeNil() {
      value = .null
    } else if let decoded = try? scalar.decode(Bool.self) {
      value = .bool(decoded)
    } else if let decoded = try? scalar.decode(Int64.self) {
      value = .int(decoded)
    } else if let decoded = try? scalar.decode(UInt64.self) {
      value = .uint(decoded)
    } else if let decoded = try? scalar.decode(Double.self) {
      value = .double(decoded)
    } else if let decoded = try? scalar.decode(String.self) {
      value = .string(decoded)
    } else {
      throw DecodingError.typeMismatch(
        JSONValue.self,
        DecodingError.Context(
          codingPath: decoder.codingPath, debugDescription: "unsupported JSON value"))
    }
  }
}

/// Executable rolling-version checks for every additive field recorded in
/// `schema/sync_payload/NNN.json:field_evolution`.
///
/// The Python verifier freezes the declared absence semantics. These probes bind
/// those declarations to the real current appliers and outbound snapshot builders:
/// an old-schema insert must materialize the declared default, and a later
/// old-schema update must preserve a value written by the current schema.
final class SyncPayloadEvolutionRuntimeContractTests: XCTestCase {
  private enum ProbeError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
      switch self {
      case .failure(let message): return message
      }
    }
  }

  private let firstUpdateVersion = "1770000000000_0001_e701e701e701e701"
  private let legacyUpdateVersion = "1770000000001_0001_e702e702e702e702"
  private let probeDeviceID = "payload-evolution-probe"

  func testArbitraryLegacyDefaultDecoderAndProbeGeneratorAreLive() throws {
    let encodedEntry = #"""
      {
        "introduced_in": 2,
        "legacy_insert_default": {"flags": [true, 3], "note": null},
        "legacy_update": "preserve",
        "meaning": "Decoder probe."
      }
      """#
    let entry = try JSONDecoder().decode(
      SyncPayloadContractFixture.FieldEvolution.self,
      from: Data(encodedEntry.utf8))
    XCTAssertEqual(
      entry.legacyInsertDefault,
      .object(["flags": .array([.bool(true), .int(3)]), "note": .null]))

    let field = try JSONDecoder().decode(
      SyncPayloadContractFixture.Field.self,
      from: Data(#"{"types":["string"]}"#.utf8))
    let probe = try XCTUnwrap(distinctProbe(from: .string("original"), field: field))
    XCTAssertNotEqual(probe, .string("original"))
    XCTAssertEqual(
      SyncPayloadContractFixture.valueViolations(probe, field: field, context: "probe"), [])
  }

  func testCurrentSchemaMissingRequiredFieldIsRejectedBeforeMutation() throws {
    let contract = try SyncPayloadContractFixture.load()
    let envelopes = try goldenByType(contract: contract)
    let task = try requireEnvelope(envelopes, entityType: EntityName.task)
    let incompleteTask = try removingField(task, fieldName: "available_from")
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db,
          registry: EntityApplierRegistry(
            appliers: EntityApplierRegistry.defaultEntityAppliers()),
          envelope: incompleteTask)
      ) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("available_from"))
      }
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [task.entityId]),
        0)
    }
  }

  func testProductionIntroductionMapExactlyMatchesCurrentManifest() throws {
    let contract = try SyncPayloadContractFixture.load()
    let manifestEntries = contract.fieldEvolution.map { qualifiedName, entry in
      "\(qualifiedName)@\(entry.introducedIn)"
    }.sorted()
    let runtimeEntries = SyncPayloadEvolution.fieldIntroductions.map {
      "\($0.entityType.asString).\($0.fieldName)@\($0.introducedIn)"
    }.sorted()

    XCTAssertEqual(
      Set(runtimeEntries).count, runtimeEntries.count,
      "SyncPayloadEvolution.fieldIntroductions must not contain duplicates")
    XCTAssertEqual(
      runtimeEntries, manifestEntries,
      "the production re-emit map must exactly match field_evolution introduction metadata")
  }

  func testCollisionAdapterCoverageExactlyMatchesCollisionFieldEvolution() throws {
    let contract = try SyncPayloadContractFixture.load()
    let manifestFields = contract.fieldEvolution.keys.filter { qualifiedName in
      guard let entityName = qualifiedName.split(separator: ".", maxSplits: 1).first,
        let entityType = EntityKind.parse(String(entityName))
      else { return false }
      return SyncPayloadEvolution.crossIDCollisionEntityTypes.contains(entityType)
    }.sorted()
    let adapterFields = PayloadEvolutionCollisionAdapterRegistry.registered.flatMap { adapter in
      adapter.coveredFields.map { "\(adapter.entityType.asString).\($0)" }
    }.sorted()

    XCTAssertEqual(
      Set(adapterFields).count, adapterFields.count,
      "a collision-evolved field must have exactly one executable adapter")
    XCTAssertEqual(
      adapterFields, manifestFields,
      "executable cross-id collision adapter coverage must exactly match field_evolution")
  }

  func testEveryHistoricalInsertMaterializesDeclaredLegacyDefault() throws {
    let current = try SyncPayloadContractFixture.load()
    for qualifiedName in current.fieldEvolution.keys.sorted() {
      let entry = try XCTUnwrap(current.fieldEvolution[qualifiedName])
      let (entityType, fieldName) = try split(qualifiedName)
      let historicalVersion = entry.introducedIn - 1
      let historicalContract = try SyncPayloadContractFixture.load(version: historicalVersion)
      let historical = try goldenByType(contract: historicalContract)
      let target = try requireEnvelope(historical, entityType: entityType)
      try requireFieldAbsent(target, fieldName: fieldName, context: qualifiedName)

      let store = try SyncTestSupport.freshStore()
      try store.writer.write { db in
        try applyGoldenState(db, contract: historicalContract, envelopes: historical)
        let snapshot = try snapshot(db, reference: target)
        guard case .object(let object) = snapshot else {
          throw ProbeError.failure("\(qualifiedName): current outbound snapshot is not an object")
        }
        XCTAssertEqual(
          object[fieldName], entry.legacyInsertDefault,
          "\(qualifiedName): applying payload schema v\(historicalVersion) to an absent row must "
            + "materialize legacy_insert_default in the current outbound snapshot")
      }
    }
  }

  func testEveryHistoricalUpdatePreservesCurrentDistinctValue() throws {
    let current = try SyncPayloadContractFixture.load()
    for qualifiedName in current.fieldEvolution.keys.sorted() {
      let entry = try XCTUnwrap(current.fieldEvolution[qualifiedName])
      XCTAssertEqual(entry.legacyUpdate, "preserve", "\(qualifiedName): unsupported evolution mode")
      let (entityType, fieldName) = try split(qualifiedName)
      let entity = try XCTUnwrap(current.entities[entityType])
      let field = try XCTUnwrap(entity.fields[fieldName])
      XCTAssertEqual(
        SyncPayloadContractFixture.valueViolations(
          entry.legacyInsertDefault, field: field, context: "\(qualifiedName).legacy_insert_default"
        ),
        [])
      guard let probe = distinctProbe(from: entry.legacyInsertDefault, field: field) else {
        throw ProbeError.failure(
          "\(qualifiedName): no deterministic valid value distinct from legacy_insert_default; "
            + "extend the typed probe generator before releasing this field")
      }

      let historicalVersion = entry.introducedIn - 1
      let historicalContract = try SyncPayloadContractFixture.load(version: historicalVersion)
      let historical = try goldenByType(contract: historicalContract)
      let target = try requireEnvelope(historical, entityType: entityType)
      try requireFieldAbsent(target, fieldName: fieldName, context: qualifiedName)
      let store = try SyncTestSupport.freshStore()

      try store.writer.write { db in
        try activateAccount(db)
        if entityType != EntityName.aiChangelog {
          try applyGoldenState(
            db, contract: historicalContract, envelopes: historical, accountAlreadyActive: true)
        }

        let currentEnvelope = try rewrite(
          target, payloadSchemaVersion: current.payloadSchemaVersion,
          version: firstUpdateVersion, fieldName: fieldName, fieldValue: probe)
        try requireApplied(db, envelope: currentEnvelope, context: "\(qualifiedName) current write")
        try assertSnapshotField(
          db, reference: currentEnvelope, fieldName: fieldName, expected: probe,
          context: "\(qualifiedName) current write")

        let legacyEnvelope = try rewrite(
          target, payloadSchemaVersion: historicalVersion,
          version: legacyUpdateVersion, fieldName: nil, fieldValue: nil)
        try requireApplied(db, envelope: legacyEnvelope, context: "\(qualifiedName) legacy update")
        try assertSnapshotField(
          db, reference: currentEnvelope, fieldName: fieldName, expected: probe,
          context: "\(qualifiedName) legacy update must preserve the current value")
      }
    }
  }

  // MARK: - Version-ladder execution

  private func split(_ qualifiedName: String) throws -> (String, String) {
    let pieces = qualifiedName.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 2 else {
      throw ProbeError.failure("invalid field_evolution key \(qualifiedName)")
    }
    return (String(pieces[0]), String(pieces[1]))
  }

  private func goldenByType(
    contract: SyncPayloadContractFixture.Contract
  ) throws -> [String: SyncEnvelope] {
    let envelopes = try SyncPayloadContractFixture.goldenEnvelopes(contract: contract)
    let grouped = Dictionary(grouping: envelopes, by: { $0.entityType.asString })
    guard grouped.values.allSatisfy({ $0.count == 1 }) else {
      throw ProbeError.failure(
        "payload contract v\(contract.payloadSchemaVersion) golden fixture is not one-per-entity")
    }
    return grouped.mapValues { $0[0] }
  }

  private func requireEnvelope(
    _ envelopes: [String: SyncEnvelope], entityType: String
  ) throws -> SyncEnvelope {
    guard let envelope = envelopes[entityType] else {
      throw ProbeError.failure("historical golden fixture has no \(entityType) upsert")
    }
    return envelope
  }

  private func requireFieldAbsent(
    _ envelope: SyncEnvelope, fieldName: String, context: String
  ) throws {
    guard case .object(let object)? = JSONValue.parse(envelope.payload) else {
      throw ProbeError.failure("\(context): historical golden payload is not an object")
    }
    guard object[fieldName] == nil else {
      throw ProbeError.failure(
        "\(context): field is already present before its declared introduced_in version")
    }
  }

  private func activateAccount(_ db: Database) throws {
    _ = try AuditRetentionFrontier.activateAccount(
      db, accountIdentifier: "payload-evolution-account", zoneName: "LorvexZone-evolution")
  }

  private func applyGoldenState(
    _ db: Database, contract: SyncPayloadContractFixture.Contract,
    envelopes: [String: SyncEnvelope], accountAlreadyActive: Bool = false
  ) throws {
    if !accountAlreadyActive { try activateAccount(db) }
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    let orderedTypes = EntityKind.topologicalEntityOrder.filter {
      contract.entities[$0] != nil
    }
    guard Set(orderedTypes).union([EntityName.aiChangelog]) == Set(contract.entities.keys) else {
      throw ProbeError.failure(
        "payload contract v\(contract.payloadSchemaVersion) contains an entity with no apply order")
    }
    for entityType in orderedTypes {
      let envelope = try requireEnvelope(envelopes, entityType: entityType)
      if entityType == EdgeName.taskDependency {
        try seedDependencyTarget(db, dependency: envelope, envelopes: envelopes)
      }
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
      guard result == .applied else {
        throw ProbeError.failure(
          "historical payload contract v\(contract.payloadSchemaVersion) \(entityType) "
            + "did not apply while preparing an evolution probe: \(result)")
      }
    }
    let audit = try requireEnvelope(envelopes, entityType: EntityName.aiChangelog)
    let auditResult = try Apply.applyEnvelope(db, registry: registry, envelope: audit)
    guard auditResult == .applied else {
      throw ProbeError.failure("historical audit envelope did not apply: \(auditResult)")
    }
  }

  private func seedDependencyTarget(
    _ db: Database, dependency: SyncEnvelope, envelopes: [String: SyncEnvelope]
  ) throws {
    guard case .object(let dependencyPayload)? = JSONValue.parse(dependency.payload),
      case .string(let targetID)? = dependencyPayload["depends_on_task_id"],
      let task = envelopes[EntityName.task],
      case .object(let taskPayload)? = JSONValue.parse(task.payload),
      case .string(let listID)? = taskPayload["list_id"]
    else {
      throw ProbeError.failure("task_dependency golden cannot seed its FK-only target")
    }
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO tasks
          (id, list_id, title, status, version, created_at, updated_at)
        VALUES (?, ?, 'Evolution dependency target', 'open', ?, ?, ?)
        """,
      arguments: [
        targetID, listID, "0000000000000_0000_0000000000000000",
        "2026-07-15T12:34:56.000Z", "2026-07-15T12:34:56.000Z",
      ])
  }

  private func rewrite(
    _ envelope: SyncEnvelope, payloadSchemaVersion: UInt32, version: String,
    fieldName: String?, fieldValue: JSONValue?
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      throw ProbeError.failure("cannot rewrite non-object golden payload")
    }
    object["version"] = .string(version)
    if let fieldName, let fieldValue { object[fieldName] = fieldValue }
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId, operation: .upsert,
      version: try Hlc.parseCanonical(version), payloadSchemaVersion: payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)), deviceId: probeDeviceID)
  }

  private func removingField(
    _ envelope: SyncEnvelope, fieldName: String
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      throw ProbeError.failure("cannot remove a field from a non-object golden payload")
    }
    object[fieldName] = nil
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)), deviceId: envelope.deviceId)
  }

  private func requireApplied(
    _ db: Database, envelope: SyncEnvelope, context: String
  ) throws {
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
    guard result == .applied else {
      throw ProbeError.failure("\(context) did not apply: \(result)")
    }
  }

  private func assertSnapshotField(
    _ db: Database, reference: SyncEnvelope, fieldName: String, expected: JSONValue,
    context: String
  ) throws {
    guard case .object(let object) = try snapshot(db, reference: reference) else {
      throw ProbeError.failure("\(context): current outbound snapshot is not an object")
    }
    XCTAssertEqual(object[fieldName], expected, "\(context)")
  }

  private func snapshot(_ db: Database, reference: SyncEnvelope) throws -> JSONValue {
    switch reference.entityType {
    case .aiChangelog:
      return try auditSnapshot(db, entityID: reference.entityId)
    case .entityRedirect:
      guard case .object(let payload)? = JSONValue.parse(reference.payload),
        case .string(let sourceType)? = payload["source_type"],
        case .string(let sourceID)? = payload["source_id"],
        let record = try EntityRedirect.get(db, sourceType: sourceType, sourceId: sourceID)
      else {
        throw ProbeError.failure("entity_redirect snapshot source is absent")
      }
      let envelope = try EntityRedirect.makeEnvelope(record: record, deviceId: probeDeviceID)
      guard let parsed = JSONValue.parse(envelope.payload) else {
        throw ProbeError.failure("entity_redirect builder emitted invalid JSON")
      }
      return parsed
    default:
      return try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: reference.entityType.asString, entityId: reference.entityId)
    }
  }

  private func auditSnapshot(_ db: Database, entityID: String) throws -> JSONValue {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, timestamp, operation, entity_type, entity_id, summary,
                 initiated_by, mcp_tool, source_device_id, before_json, after_json,
                 retention_epoch, retention_account_identifier
          FROM ai_changelog WHERE id = ?
          """, arguments: [entityID])
    else { throw ProbeError.failure("ai_changelog snapshot source is absent") }
    let entityIDs = try String.fetchAll(
      db,
      sql: "SELECT entity_id FROM ai_changelog_entities WHERE changelog_id = ? ORDER BY entity_id",
      arguments: [entityID])
    return try ChangelogWrite.buildChangelogSyncPayload(
      ChangelogWrite.ChangelogRow(
        id: row["id"], timestamp: row["timestamp"], operation: row["operation"],
        entityType: row["entity_type"], entityId: row["entity_id"], entityIds: entityIDs,
        summary: row["summary"], initiatedBy: row["initiated_by"], mcpTool: row["mcp_tool"],
        sourceDeviceId: row["source_device_id"] ?? "", beforeJson: row["before_json"],
        afterJson: row["after_json"], retentionEpoch: row["retention_epoch"],
        retentionAccountIdentifier: row["retention_account_identifier"]))
  }

  // MARK: - Deterministic typed probe values

  private func distinctProbe(
    from baseline: JSONValue, field: SyncPayloadContractFixture.Field
  ) -> JSONValue? {
    candidates(field: field, depth: 0).first { candidate in
      candidate != baseline
        && SyncPayloadContractFixture.valueViolations(
          candidate, field: field, context: "evolution probe"
        ).isEmpty
    }
  }

  private func candidates(
    field: SyncPayloadContractFixture.Field, depth: Int
  ) -> [JSONValue] {
    guard depth < 6 else { return [] }
    var result: [JSONValue] = []
    func append(_ value: JSONValue) {
      guard !result.contains(value) else { return }
      if SyncPayloadContractFixture.valueViolations(
        value, field: field, context: "candidate"
      ).isEmpty {
        result.append(value)
      }
    }

    for type in field.types {
      switch type {
      case "null": append(.null)
      case "boolean":
        append(.bool(false))
        append(.bool(true))
      case "integer":
        for value in integerCandidates(field) { append(.int(value)) }
      case "number":
        for value in numberCandidates(field) { append(.double(value)) }
      case "string":
        for value in stringCandidates(field) { append(.string(value)) }
      case "array": arrayCandidates(field, depth: depth).forEach(append)
      case "object": objectCandidates(field, depth: depth).forEach(append)
      default: break
      }
    }
    return result
  }

  private func integerCandidates(_ field: SyncPayloadContractFixture.Field) -> [Int64] {
    let fixed: [Int64] = [-2, -1, 0, 1, 2, 42, 1_440]
    return fixed.filter { value in
      let number = Double(value)
      return (field.minimum == nil || number >= field.minimum!)
        && (field.maximum == nil || number <= field.maximum!)
    }
  }

  private func numberCandidates(_ field: SyncPayloadContractFixture.Field) -> [Double] {
    let fixed = [-2.5, -1.5, 0.0, 0.5, 1.5, 42.5, 1_440.0]
    return fixed.filter { value in
      (field.minimum == nil || value >= field.minimum!)
        && (field.maximum == nil || value <= field.maximum!)
    }
  }

  private func stringCandidates(_ field: SyncPayloadContractFixture.Field) -> [String] {
    if let values = field.enumValues { return values }
    switch field.format {
    case "civil-date": return ["2026-01-02", "2027-03-04"]
    case "hh-mm": return ["09:17", "18:43"]
    case "rfc3339-utc": return ["2026-01-02T03:04:05.006Z", "2027-03-04T05:06:07.008Z"]
    case "hlc": return [firstUpdateVersion, legacyUpdateVersion]
    case "uuid":
      return [
        "0000e701-0000-7000-8000-000000000001", "0000e702-0000-7000-8000-000000000002",
      ]
    case "uuid-or-inbox":
      return ["inbox", "0000e703-0000-7000-8000-000000000003"]
    case "iana-time-zone": return ["UTC", "America/Los_Angeles"]
    case "calendar-url": return ["https://example.invalid/a", "webcal://example.invalid/b"]
    case "json-string": return ["true", "{\"probe\":1}"]
    case "json-array-string": return ["[]", "[1]"]
    case "json-object-string": return ["{}", "{\"probe\":true}"]
    default: return ["lorvex-evolution-probe-a", "lorvex-evolution-probe-b"]
    }
  }

  private func arrayCandidates(
    _ field: SyncPayloadContractFixture.Field, depth: Int
  ) -> [JSONValue] {
    let minimum = max(0, field.minItems ?? 0)
    let maximum = field.maxItems ?? max(minimum + 2, 2)
    guard minimum <= maximum else { return [] }
    let itemValues: [JSONValue]
    if let item = field.items {
      itemValues = candidates(field: item, depth: depth + 1)
    } else {
      itemValues = [.string("probe-a"), .string("probe-b"), .int(1)]
    }
    var result: [JSONValue] = []
    for count in [minimum, max(minimum, 1), min(maximum, minimum + 1)] where count <= maximum {
      if count == 0 {
        result.append(.array([]))
        continue
      }
      guard !itemValues.isEmpty else { continue }
      if field.uniqueItems == true, itemValues.count < count { continue }
      let values = (0..<count).map { itemValues[field.uniqueItems == true ? $0 : 0] }
      result.append(.array(values))
    }
    return result
  }

  private func objectCandidates(
    _ field: SyncPayloadContractFixture.Field, depth: Int
  ) -> [JSONValue] {
    let properties = field.properties ?? [:]
    let required = Set(field.requiredProperties ?? [])
    var base: [String: JSONValue] = [:]
    for key in required.sorted() {
      guard let child = properties[key],
        let value = candidates(field: child, depth: depth + 1).first
      else { return [] }
      base[key] = value
    }
    var result: [JSONValue] = [.object(base)]
    for key in properties.keys.sorted() {
      guard let child = properties[key] else { continue }
      for value in candidates(field: child, depth: depth + 1).prefix(2) {
        var variant = base
        variant[key] = value
        result.append(.object(variant))
      }
    }
    if field.additionalProperties == true {
      var variant = base
      variant["contract_probe"] = .string("distinct")
      result.append(.object(variant))
    }
    return result
  }
}
