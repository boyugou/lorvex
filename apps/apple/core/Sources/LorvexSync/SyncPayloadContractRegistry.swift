import Foundation
import LorvexDomain

/// Fail-closed production errors for the numbered sync-payload contract.
enum SyncPayloadContractError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingResource(version: UInt32)
  case invalidManifest(version: UInt32, detail: String)
  case violations([String])

  var description: String {
    switch self {
    case .missingResource(let version):
      return "bundled sync payload contract \(Self.fileName(version)) is missing"
    case .invalidManifest(let version, let detail):
      return "bundled sync payload contract \(Self.fileName(version)) is invalid: \(detail)"
    case .violations(let violations):
      return violations.joined(separator: "; ")
    }
  }

  private static func fileName(_ version: UInt32) -> String {
    String(format: "%03u.json", version)
  }
}

/// Runtime registry and recursive validator for the immutable numbered payload
/// manifests. This is the single typed trust boundary shared by inbound Apply,
/// final outbox enqueue, import writers, and contract tests.
enum SyncPayloadContractRegistry {
  private static let loadedContracts: Result<
    [UInt32: SyncPayloadContractManifest], SyncPayloadContractError
  > = {
    do {
      var contracts: [UInt32: SyncPayloadContractManifest] = [:]
      for version in UInt32(1)...LorvexVersion.payloadSchemaVersion {
        contracts[version] = try loadBundledContract(version: version)
      }
      return .success(contracts)
    } catch let error as SyncPayloadContractError {
      return .failure(error)
    } catch {
      return .failure(
        .invalidManifest(
          version: LorvexVersion.payloadSchemaVersion, detail: String(describing: error)))
    }
  }()

  static func contract(version: UInt32) throws -> SyncPayloadContractManifest {
    let contracts = try loadedContracts.get()
    guard let contract = contracts[version] else {
      throw SyncPayloadContractError.missingResource(version: version)
    }
    return contract
  }

  /// Validate one final envelope. Historical/current versions are exact.
  /// Future versions must satisfy the complete current contract as a floor and
  /// may add only unknown top-level keys, which payload shadow can preserve.
  static func validate(_ envelope: SyncEnvelope) throws {
    let violations = try violations(for: envelope)
    if !violations.isEmpty {
      throw SyncPayloadContractError.violations(violations)
    }
  }

  static func violations(for envelope: SyncEnvelope) throws -> [String] {
    guard envelope.payloadSchemaVersion > 0 else {
      return ["payload_schema_version 0 is unsupported; versions start at 1"]
    }
    let isFuture = envelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion
    let contractVersion = isFuture
      ? LorvexVersion.payloadSchemaVersion : envelope.payloadSchemaVersion
    let contract = try contract(version: contractVersion)
    return violations(
      for: envelope, contract: contract, allowUnknownTopLevelFields: isFuture)
  }

  /// Explicit-contract seam used by the independent authority/golden tests.
  static func violations(
    for envelope: SyncEnvelope, contract: SyncPayloadContractManifest,
    allowUnknownTopLevelFields: Bool = false
  ) -> [String] {
    if !allowUnknownTopLevelFields,
      envelope.payloadSchemaVersion != contract.payloadSchemaVersion
    {
      return [
        "envelope payload schema version \(envelope.payloadSchemaVersion) does not match "
          + "manifest \(contract.payloadSchemaVersion)"
      ]
    }
    guard let entity = contract.entities[envelope.entityType.asString] else {
      return ["manifest has no entity \(envelope.entityType.asString)"]
    }
    guard case .object(let object)? = JSONValue.parse(envelope.payload) else {
      return ["final payload is not a JSON object"]
    }
    let actual = Set(object.keys)
    var violations: [String]

    switch envelope.operation {
    case .upsert:
      violations = shapeViolations(
        actual: actual, object: object, required: entity.operations.upsert.requiredKeys,
        optional: entity.operations.upsert.optionalKeys, markerKey: nil,
        fields: entity.fields, context: envelope.entityType.asString,
        allowUnknownTopLevelFields: allowUnknownTopLevelFields)
      if object["version"] != .string(envelope.version.description) {
        violations.append(
          "upsert payload.version must equal envelope version \(envelope.version.description)")
      }
    case .delete:
      guard !entity.operations.delete.shapes.isEmpty else {
        return ["delete is not supported for \(envelope.entityType.asString)"]
      }
      let candidates = entity.operations.delete.shapes.map { shape in
        shapeViolations(
          actual: actual, object: object, required: shape.requiredKeys,
          optional: shape.optionalKeys, markerKey: shape.markerKey,
          fields: entity.fields, context: "\(envelope.entityType.asString).\(shape.name)",
          allowUnknownTopLevelFields: allowUnknownTopLevelFields)
      }
      if let match = candidates.first(where: { $0.isEmpty }) {
        violations = match
      } else {
        let names = entity.operations.delete.shapes.map(\.name).joined(separator: ", ")
        violations = [
          "delete keys \(actual.sorted()) match no operation-specific shape [\(names)]"
        ]
      }
    }

    if allowUnknownTopLevelFields {
      let reserved = Set(contract.shadowReservedKeys[envelope.entityType.asString] ?? [])
      let forbidden = actual.intersection(reserved)
      if !forbidden.isEmpty {
        violations.append(
          "future payload uses permanently reserved top-level keys \(forbidden.sorted())")
      }
    }
    violations.append(contentsOf: identityViolations(envelope: envelope, object: object))
    violations.append(contentsOf: semanticViolations(envelope: envelope, object: object))
    return violations
  }

  static func valueViolations(
    _ value: JSONValue, field: SyncPayloadFieldContract, context: String
  ) -> [String] {
    let type: String
    switch value {
    case .null: type = "null"
    case .bool: type = "boolean"
    case .int, .uint: type = "integer"
    case .double: type = "number"
    case .string: type = "string"
    case .array: type = "array"
    case .object: type = "object"
    }
    guard field.types.contains(type) else {
      return ["\(context) has JSON type \(type); allowed types are \(field.types)"]
    }
    if value == .null { return [] }

    var violations: [String] = []
    if let values = field.enumValues, case .string(let raw) = value,
      !values.contains(raw)
    {
      violations.append("\(context) value \(raw) is outside enum \(values)")
    }
    if let format = field.format, case .string(let raw) = value,
      !matchesFormat(raw, format: format)
    {
      violations.append("\(context) value \(raw) violates format \(format)")
    }
    let numeric: Double?
    switch value {
    case .int(let number): numeric = Double(number)
    case .uint(let number): numeric = Double(number)
    case .double(let number): numeric = number
    default: numeric = nil
    }
    if let numeric, let minimum = field.minimum, numeric < minimum {
      violations.append("\(context) value \(numeric) is below minimum \(minimum)")
    }
    if let numeric, let maximum = field.maximum, numeric > maximum {
      violations.append("\(context) value \(numeric) exceeds maximum \(maximum)")
    }
    if case .array(let items) = value {
      if let minimum = field.minItems, items.count < minimum {
        violations.append("\(context) has fewer than \(minimum) items")
      }
      if let maximum = field.maxItems, items.count > maximum {
        violations.append("\(context) has more than \(maximum) items")
      }
      if field.uniqueItems == true,
        items.indices.contains(where: { items[..<$0].contains(items[$0]) })
      {
        violations.append("\(context) items must be unique")
      }
      if let itemContract = field.items {
        for (index, item) in items.enumerated() {
          violations.append(
            contentsOf: valueViolations(
              item, field: itemContract, context: "\(context)[\(index)]"))
        }
      }
    }
    if case .object(let object) = value, let properties = field.properties {
      let required = Set(field.requiredProperties ?? [])
      let actual = Set(object.keys)
      let missing = required.subtracting(actual)
      if !missing.isEmpty {
        violations.append("\(context) is missing required properties \(missing.sorted())")
      }
      let extra = actual.subtracting(properties.keys)
      if !extra.isEmpty, field.additionalProperties == false {
        violations.append("\(context) has unexpected properties \(extra.sorted())")
      }
      for key in actual.intersection(properties.keys).sorted() {
        guard let nestedValue = object[key], let nestedField = properties[key] else { continue }
        violations.append(
          contentsOf: valueViolations(
            nestedValue, field: nestedField, context: "\(context).\(key)"))
      }
    }
    return violations
  }

  private static func loadBundledContract(version: UInt32) throws
    -> SyncPayloadContractManifest
  {
    do {
      let contract = try JSONDecoder().decode(
        SyncPayloadContractManifest.self,
        from: try SyncPayloadContractResources.data(version: version))
      guard contract.contractFormat == 3 else {
        throw SyncPayloadContractError.invalidManifest(
          version: version, detail: "unsupported contract_format \(contract.contractFormat)")
      }
      guard contract.payloadSchemaVersion == version else {
        throw SyncPayloadContractError.invalidManifest(
          version: version,
          detail: "declares payload_schema_version \(contract.payloadSchemaVersion)")
      }
      return contract
    } catch let error as SyncPayloadContractError {
      throw error
    } catch {
      throw SyncPayloadContractError.invalidManifest(
        version: version, detail: String(describing: error))
    }
  }

  private static func shapeViolations(
    actual: Set<String>, object: [String: JSONValue], required: [String], optional: [String],
    markerKey: String?, fields: [String: SyncPayloadFieldContract], context: String,
    allowUnknownTopLevelFields: Bool
  ) -> [String] {
    let required = Set(required)
    let allowed = required.union(optional)
    var violations: [String] = []
    let missing = required.subtracting(actual)
    if !missing.isEmpty { violations.append("missing required keys \(missing.sorted())") }
    let extra = actual.subtracting(allowed)
    if !extra.isEmpty, !allowUnknownTopLevelFields {
      violations.append("unexpected keys \(extra.sorted())")
    }
    if let markerKey, object[markerKey] != .bool(true) {
      violations.append("marker \(markerKey) must equal true")
    }
    for key in actual.intersection(fields.keys).sorted() {
      guard let field = fields[key], let value = object[key] else { continue }
      violations.append(
        contentsOf: valueViolations(value, field: field, context: "\(context).\(key)"))
    }
    return violations
  }

  private static func matchesFormat(_ value: String, format: String) -> Bool {
    switch format {
    case "civil-date":
      if case .success = ValidationFormat.validateDateFormat(value) { return true }
      return false
    case "hh-mm":
      if case .success = ValidationFormat.validateTimeFormat(value) { return true }
      return false
    case "rfc3339-utc":
      return value.utf8.count == 24 && SyncTimestamp.parse(value)?.asString == value
    case "hlc":
      return (try? Hlc.parseCanonical(value))?.description == value
    case "uuid":
      return SyncEntityId.isCanonicalUuid(value)
    case "uuid-or-inbox":
      return value == ListId.inboxSentinel || SyncEntityId.isCanonicalUuid(value)
    case "iana-time-zone":
      return TimeZone(identifier: value) != nil
    case "calendar-url":
      if case .success(let canonical) = ValidationFormat.validateCalendarURL(value) {
        return canonical == value
      }
      return false
    case "json-string":
      return JSONValue.parse(value) != nil
    case "json-array-string":
      if case .array? = JSONValue.parse(value) { return true }
      return false
    case "json-object-string":
      if case .object? = JSONValue.parse(value) { return true }
      return false
    default:
      return false
    }
  }

  private static func identityViolations(
    envelope: SyncEnvelope, object: [String: JSONValue]
  ) -> [String] {
    func mismatch(_ field: String, _ expected: String) -> [String] {
      guard case .string(let actual)? = object[field], actual != expected else { return [] }
      return ["\(envelope.entityType.asString) payload.\(field) must equal entity_id component "
        + "\(expected)"]
    }

    switch envelope.entityType {
    case .task, .list, .habit, .tag, .calendarEvent, .calendarSeriesCutover, .memory,
      .taskReminder, .taskChecklistItem, .habitReminderPolicy:
      return mismatch("id", envelope.entityId)
    case .preference:
      return mismatch("key", envelope.entityId)
    case .dailyReview, .currentFocus, .focusSchedule:
      return mismatch("date", envelope.entityId)
    case .taskTag, .taskDependency, .taskCalendarEventLink, .habitCompletion:
      guard case .success(let pair) = CompositeEdge.splitCompositeEdgeId(envelope.entityId) else {
        return ["\(envelope.entityType.asString) entity_id is not a canonical composite identity"]
      }
      let fields: (String, String)
      switch envelope.entityType {
      case .taskTag: fields = ("task_id", "tag_id")
      case .taskDependency: fields = ("task_id", "depends_on_task_id")
      case .taskCalendarEventLink: fields = ("task_id", "calendar_event_id")
      case .habitCompletion: fields = ("habit_id", "completed_date")
      default: return []
      }
      return mismatch(fields.0, pair.0) + mismatch(fields.1, pair.1)
    case .entityRedirect:
      guard case .string(let sourceType)? = object["source_type"],
        case .string(let sourceID)? = object["source_id"]
      else { return [] }
      let expected = SyncRecordName.opaque(entityType: sourceType, entityId: sourceID)
      if expected != envelope.entityId {
        return ["entity_redirect entity_id must equal the source identity digest \(expected)"]
      }
      return []
    case .aiChangelog:
      return []
    case .deviceState, .importSession:
      return ["\(envelope.entityType.asString) has no sync payload contract"]
    }
  }

  private static func semanticViolations(
    envelope: SyncEnvelope, object: [String: JSONValue]
  ) -> [String] {
    guard envelope.operation == .upsert, envelope.entityType == .taskReminder else { return [] }
    let localTimeIsNull = object["original_local_time"] == .null
    let timezoneIsNull = object["original_tz"] == .null
    if localTimeIsNull != timezoneIsNull {
      return [
        "task_reminder original_local_time and original_tz must both be null or both be present"
      ]
    }
    return []
  }
}

/// Public, read-only trust boundary used by the CloudKit transport before it
/// chooses an HLC conflict branch. A structurally decodable CKRecord can still
/// violate the numbered payload contract; callers must classify that server
/// slot as corrupt rather than apply it or park it as honest future data.
public enum SyncPayloadTransportValidationError: LocalizedError, Sendable, Equatable {
  case contractUnavailable(String)

  public var errorDescription: String? {
    switch self {
    case .contractUnavailable(let detail):
      return "Bundled sync payload validation is unavailable: \(detail)"
    }
  }
}

public enum SyncPayloadTransportValidation {
  /// Returns every peer-payload violation. An empty result is valid. Bundled
  /// contract loading failures still throw: those are local infrastructure
  /// failures and are never evidence that the remote slot is corrupt.
  public static func violations(for envelope: SyncEnvelope) throws -> [String] {
    do {
      return try SyncPayloadContractRegistry.violations(for: envelope)
    } catch {
      throw SyncPayloadTransportValidationError.contractUnavailable(
        String(describing: error))
    }
  }
}
