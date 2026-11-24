import Foundation
import MCP

/// A JSON value decoded as written: every string stays a `.string`.
///
/// `MCP.Value`'s own decoder turns a string whose whole value is a data URL
/// (`data:,hello`) into `.data`, so a task title or tool argument of that shape
/// would change in transit. This decoder tries the same kinds in the same order
/// (null, Bool, Int, Double, String, array, object), so numbers decode exactly
/// as `MCP.Value` decodes them, and never guesses at strings. Encoding writes
/// the wrapped `Value` unchanged.
struct LiteralValue: Codable, Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = .null
    } else if let bool = try? container.decode(Bool.self) {
      value = .bool(bool)
    } else if let int = try? container.decode(Int.self) {
      value = .int(int)
    } else if let double = try? container.decode(Double.self) {
      value = .double(double)
    } else if let string = try? container.decode(String.self) {
      value = .string(string)
    } else if let array = try? container.decode([LiteralValue].self) {
      value = .array(array.map(\.value))
    } else if let object = try? container.decode([String: LiteralValue].self) {
      value = .object(object.mapValues(\.value))
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Not a JSON value")
    }
  }

  func encode(to encoder: Encoder) throws {
    try value.encode(to: encoder)
  }

  /// `data` parsed as one JSON value, strings kept as written.
  static func decode(_ data: Data) throws -> Value {
    try JSONDecoder().decode(LiteralValue.self, from: data).value
  }
}

/// A JSON-RPC request id, echoed back exactly as the client wrote it.
enum JSONRPCID: Hashable, Sendable, Encodable {
  case string(String)
  case number(Int)

  /// The id `value` names, or nil when it is not a string or an integer.
  init?(_ value: Value) {
    switch value {
    case .string(let string): self = .string(string)
    case .int(let number): self = .number(number)
    default: return nil
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let string): try container.encode(string)
    case .number(let number): try container.encode(number)
    }
  }
}

/// A JSON-RPC error a request is answered with.
struct MCPWireError: Error, Sendable, Equatable {
  let code: Int
  let message: String
  let data: Value?

  init(code: Int, message: String, data: Value? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }

  static func parseError(_ detail: String) -> Self {
    Self(code: -32700, message: "Parse error: \(detail)")
  }

  static func invalidRequest(_ detail: String) -> Self {
    Self(code: -32600, message: "Invalid Request: \(detail)")
  }

  static func methodNotFound(_ method: String) -> Self {
    Self(code: -32601, message: "Method not found: \(method)")
  }

  static func invalidParams(_ detail: String) -> Self {
    Self(code: -32602, message: "Invalid params: \(detail)")
  }

  static func internalError(_ detail: String) -> Self {
    Self(code: -32603, message: "Internal error: \(detail)")
  }

  /// MCP 2026-07-28's `UnsupportedProtocolVersionError`.
  static func unsupportedProtocolVersion(requested: String, supported: [String]) -> Self {
    Self(
      code: -32022, message: "Unsupported protocol version",
      data: .object([
        "supported": .array(supported.map(Value.string)),
        "requested": .string(requested),
      ]))
  }
}

/// JSON-RPC frames as Lorvex writes them: compact JSON with sorted keys and
/// unescaped slashes. JSON encoding escapes newlines inside strings, so each
/// frame is a single line.
enum MCPWire {
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  /// The success response to request `id`, carrying `result`, the result
  /// object already encoded with ``encoder()``.
  static func resultFrame(id: JSONRPCID, result: Data) -> Data {
    var frame = Data(#"{"id":"#.utf8)
    frame.append(encodedID(id))
    frame.append(Data(#","jsonrpc":"2.0","result":"#.utf8))
    frame.append(result)
    frame.append(UInt8(ascii: "}"))
    return frame
  }

  /// The error response to request `id`, or to a message whose id could not
  /// be read when `id` is nil. MCP's error response leaves `id` out in that
  /// case (`id?: RequestId`) rather than writing JSON-RPC's `null`, which a
  /// client that validates against MCP's schema would reject.
  static func errorFrame(id: JSONRPCID?, _ error: MCPWireError) -> Data {
    let frame = ErrorFrame(id: id, error: .init(error))
    // Every field is a string, an integer or an encodable `Value`.
    return (try? encoder().encode(frame))
      ?? Data(#"{"error":{"code":-32603,"message":"Internal error"},"jsonrpc":"2.0"}"#.utf8)
  }

  /// `frames` as one JSON array, the response to a batch.
  static func batchFrame(_ frames: [Data]) -> Data {
    var batch = Data("[".utf8)
    for (index, frame) in frames.enumerated() {
      if index > 0 { batch.append(UInt8(ascii: ",")) }
      batch.append(frame)
    }
    batch.append(UInt8(ascii: "]"))
    return batch
  }

  private static func encodedID(_ id: JSONRPCID) -> Data {
    switch id {
    case .number(let number):
      return Data(String(number).utf8)
    case .string:
      return (try? encoder().encode(id)) ?? Data(#""""#.utf8)
    }
  }

  private struct ErrorFrame: Encodable {
    struct Body: Encodable {
      let code: Int
      let message: String
      let data: Value?

      init(_ error: MCPWireError) {
        code = error.code
        message = error.message
        data = error.data
      }
    }

    let id: JSONRPCID?
    let error: Body

    enum CodingKeys: String, CodingKey { case error, id, jsonrpc }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(error, forKey: .error)
      try container.encodeIfPresent(id, forKey: .id)
      try container.encode("2.0", forKey: .jsonrpc)
    }
  }
}

/// One JSON-RPC message from the client, sorted by kind.
enum MCPIncomingMessage: Sendable {
  case request(id: JSONRPCID, method: String, params: [String: Value]?)
  case notification(method: String, params: [String: Value]?)
  /// A response to a request; Lorvex sends none, so these are ignored.
  case response
  /// A JSON value that is not a valid message, answered with this error.
  case invalid(id: JSONRPCID?, MCPWireError)

  /// Sorts one decoded JSON value (one element of a batch, or a whole line).
  init(_ value: Value) {
    guard case .object(let object) = value else {
      self = .invalid(id: nil, .invalidRequest("a message must be a JSON object"))
      return
    }
    let id = object["id"].flatMap(JSONRPCID.init)
    guard object["jsonrpc"] == .string("2.0") else {
      self = .invalid(id: id, .invalidRequest(#"jsonrpc must be "2.0""#))
      return
    }
    guard let methodValue = object["method"] else {
      if object["result"] != nil || object["error"] != nil {
        self = .response
      } else {
        self = .invalid(id: id, .invalidRequest("a message needs a method"))
      }
      return
    }
    guard case .string(let method) = methodValue else {
      self = .invalid(id: id, .invalidRequest("method must be a string"))
      return
    }
    let isNotification = object["id"] == nil
    let params: [String: Value]?
    switch object["params"] {
    case nil, .null?:
      params = nil
    case .object(let fields)?:
      params = fields
    default:
      // A notification gets no reply, even a malformed one.
      self =
        isNotification
        ? .notification(method: method, params: nil)
        : .invalid(id: id, .invalidParams("params must be an object"))
      return
    }
    if isNotification {
      self = .notification(method: method, params: params)
    } else if let id {
      self = .request(id: id, method: method, params: params)
    } else {
      self = .invalid(id: nil, .invalidRequest("id must be a string or an integer"))
    }
  }
}
