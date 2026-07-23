import Foundation
import LorvexDomain

/// Decoded, immutable representation of one numbered sync-payload manifest.
///
/// Production and tests intentionally share these types. The JSON files in
/// `schema/sync_payload/` remain the authority; byte-identical SwiftPM resource
/// copies make that authority executable at the inbound and outbound runtime
/// boundaries without depending on a source checkout.
struct SyncPayloadContractManifest: Decodable, Sendable {
  let contractFormat: Int
  let entities: [String: SyncPayloadEntityContract]
  let fieldEvolution: [String: SyncPayloadFieldEvolution]
  let goldenFixture: String
  let goldenFixtureSHA256: String
  let payloadSchemaVersion: UInt32
  let shadowReservedKeys: [String: [String]]

  enum CodingKeys: String, CodingKey {
    case contractFormat = "contract_format"
    case entities
    case fieldEvolution = "field_evolution"
    case goldenFixture = "golden_fixture"
    case goldenFixtureSHA256 = "golden_fixture_sha256"
    case payloadSchemaVersion = "payload_schema_version"
    case shadowReservedKeys = "shadow_reserved_keys"
  }
}

struct SyncPayloadEntityContract: Decodable, Sendable {
  let fields: [String: SyncPayloadFieldContract]
  let operations: SyncPayloadOperationContracts
  let syntheticKeys: [String]

  enum CodingKeys: String, CodingKey {
    case operations
    case fields
    case syntheticKeys = "synthetic_keys"
  }
}

struct SyncPayloadOperationContracts: Decodable, Sendable {
  let delete: SyncPayloadDeleteContract
  let upsert: SyncPayloadUpsertContract
}

struct SyncPayloadUpsertContract: Decodable, Sendable {
  let requiredKeys: [String]
  let optionalKeys: [String]

  enum CodingKeys: String, CodingKey {
    case requiredKeys = "required_keys"
    case optionalKeys = "optional_keys"
  }
}

struct SyncPayloadDeleteContract: Decodable, Sendable {
  let shapes: [SyncPayloadDeleteShape]
}

struct SyncPayloadDeleteShape: Decodable, Sendable {
  let name: String
  let markerKey: String?
  let requiredKeys: [String]
  let optionalKeys: [String]

  enum CodingKeys: String, CodingKey {
    case name
    case markerKey = "marker_key"
    case requiredKeys = "required_keys"
    case optionalKeys = "optional_keys"
  }
}

/// Recursive field contract. Immutable after decoding; unchecked Sendable is
/// safe because the class has no mutable state and exists only to support the
/// recursive `items`/`properties` graph that a Swift value type cannot contain.
final class SyncPayloadFieldContract: Decodable, @unchecked Sendable {
  let additionalProperties: Bool?
  let enumValues: [String]?
  let format: String?
  let items: SyncPayloadFieldContract?
  let maximum: Double?
  let maxItems: Int?
  let minimum: Double?
  let minItems: Int?
  let properties: [String: SyncPayloadFieldContract]?
  let requiredProperties: [String]?
  let types: [String]
  let unit: String?
  let uniqueItems: Bool?

  enum CodingKeys: String, CodingKey {
    case additionalProperties = "additional_properties"
    case enumValues = "enum"
    case format
    case items
    case maximum
    case maxItems = "max_items"
    case minimum
    case minItems = "min_items"
    case properties
    case requiredProperties = "required_properties"
    case types
    case unit
    case uniqueItems = "unique_items"
  }
}

struct SyncPayloadFieldEvolution: Decodable, Sendable {
  let introducedIn: UInt32
  let legacyInsertDefault: JSONValue
  let legacyUpdate: String
  let meaning: String

  enum CodingKeys: String, CodingKey {
    case introducedIn = "introduced_in"
    case legacyInsertDefault = "legacy_insert_default"
    case legacyUpdate = "legacy_update"
    case meaning
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    introducedIn = try container.decode(UInt32.self, forKey: .introducedIn)
    legacyInsertDefault = try container.decode(
      SyncPayloadArbitraryJSON.self, forKey: .legacyInsertDefault
    ).value
    legacyUpdate = try container.decode(String.self, forKey: .legacyUpdate)
    meaning = try container.decode(String.self, forKey: .meaning)
  }
}

/// JSON decoder used only for manifest-declared historical defaults. It keeps
/// the domain representation's integer/unsigned/double distinction intact.
private struct SyncPayloadArbitraryJSON: Decodable {
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
