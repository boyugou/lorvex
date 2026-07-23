import CryptoKit
import Foundation
import MCP

/// In-memory idempotency cache for MCP write operations.
///
/// Caches successful write responses keyed by `(tool_name, idempotency_key)` with a
/// 24-hour TTL. Semantics:
///
/// - **Same key + same payload checksum** — replay the cached response. The
///   caller sees an indistinguishable result from the original write.
/// - **Same key + different payload checksum** — reject with
///   `IdempotencyCacheError.checksumMismatch`. The server must not treat this
///   as a fresh write; the caller must generate a new key for a different
///   intent.
/// - **Key not in cache** — miss; caller proceeds with the live write and
///   stores the result via `store(_:forTool:key:checksum:)`.
///
/// The cache is local to the current MCP host process and is used only when an
/// injected backend has no durable idempotency service. Production registries
/// always consult the Swift core's generation-scoped `mcp_idempotency` table;
/// caching those responses here would let a factory reset or storage cutover
/// replay a success from the database generation that was replaced.
actor IdempotencyCache {
  /// Payload stored per cache entry.
  struct Entry {
    let requestChecksum: String
    let cachedResult: CachedResult
    let expiresAt: Date
  }

  /// A cached MCP tool response (text content + optional structured content).
  struct CachedResult: Sendable {
    let textContent: String
    let structuredContent: (any Sendable)?
  }

  enum IdempotencyCacheError: Error {
    /// A key was reused with a different payload checksum.
    case checksumMismatch(tool: String, key: String)
  }

  private var entries: [String: Entry] = [:]
  private let ttl: TimeInterval

  /// Creates a cache with the given TTL. Default is 24 hours.
  init(ttl: TimeInterval = 86400) {
    self.ttl = ttl
  }

  /// Looks up a prior result for `(tool, key)`.
  ///
  /// Returns the cached result when the entry exists, is unexpired, and
  /// `checksum` matches the stored checksum.
  /// Throws `IdempotencyCacheError.checksumMismatch` when the entry exists
  /// but the checksum differs.
  /// Returns `nil` on a clean miss.
  func lookup(tool: String, key: String, checksum: String) throws -> CachedResult? {
    let cacheKey = compositeKey(tool: tool, key: key)
    guard let entry = entries[cacheKey] else { return nil }
    guard entry.expiresAt > Date() else {
      entries.removeValue(forKey: cacheKey)
      return nil
    }
    guard entry.requestChecksum == checksum else {
      throw IdempotencyCacheError.checksumMismatch(tool: tool, key: key)
    }
    return entry.cachedResult
  }

  /// Stores a successful write result.
  func store(
    _ result: CachedResult,
    forTool tool: String,
    key: String,
    checksum: String
  ) {
    let cacheKey = compositeKey(tool: tool, key: key)
    entries[cacheKey] = Entry(
      requestChecksum: checksum,
      cachedResult: result,
      expiresAt: Date(timeIntervalSinceNow: ttl)
    )
  }

  // MARK: - Checksum helper

  /// Computes a SHA-256 checksum of an MCP tool-argument dictionary.
  ///
  /// `MCP.Value` is `Codable` but not a Foundation JSON type, so it is encoded
  /// through `JSONEncoder` with `.sortedKeys` for a stable, order-independent
  /// canonical form. Returns a hex string, or an empty string when encoding
  /// fails (e.g. a non-finite `Double`). The dispatch treats an empty checksum as
  /// never-hit / never-store: it has no dedup identity, so the write runs live
  /// and no idempotency record — in-memory or durable — is created for it.
  static func checksum(for arguments: [String: Value]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(arguments) else { return "" }
    let digest = SHA256.hash(data: data)
    let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
    var hex = [UInt8]()
    hex.reserveCapacity(SHA256.Digest.byteCount * 2)
    for byte in digest {
      hex.append(hexDigits[Int(byte >> 4)])
      hex.append(hexDigits[Int(byte & 0x0F)])
    }
    return String(decoding: hex, as: UTF8.self)
  }

  // MARK: - Private

  private func compositeKey(tool: String, key: String) -> String {
    "\(tool)\0\(key)"
  }
}

// MARK: - CallTool.Result <-> CachedResult

extension CallTool.Result {
  /// Snapshots a successful write result for the idempotency cache: the joined
  /// text content plus the structured content (an `MCP.Value`, which is
  /// `Sendable`). Non-text content blocks are not retained — write tools return
  /// text + structured payloads.
  func toCachedResult() -> IdempotencyCache.CachedResult {
    let text = content.compactMap { block -> String? in
      if case .text(let value, _, _) = block { return value }
      return nil
    }.joined()
    return IdempotencyCache.CachedResult(textContent: text, structuredContent: structuredContent)
  }
}

extension IdempotencyCache.CachedResult {
  /// Rebuilds a non-error success result from a cached entry, faithful to how
  /// handlers construct results (single text block + optional structured
  /// `MCP.Value`). The replay is indistinguishable from the original response.
  func toCallToolResult() -> CallTool.Result {
    CallTool.Result(
      content: [.text(text: textContent, annotations: nil, _meta: nil)],
      structuredContent: structuredContent as? Value,
      isError: false
    )
  }
}

// MARK: - Durable payload (cross-restart replay)

extension IdempotencyCache.CachedResult {
  /// Envelope persisted in the core's `mcp_idempotency.response_payload`. That
  /// column is a single TEXT field, so both the text block and the structured
  /// content are encoded here — otherwise a cross-restart replay would return
  /// text only and drop the IDs/objects clients need (the schema promises the
  /// original response is replayed in full, not just its text).
  private struct DurableEnvelope: Codable {
    let text: String
    let structured: Value?
  }

  /// Serialize for the durable idempotency record. Falls back to the bare text
  /// if encoding the structured content fails, so a record is always written.
  func durablePayload() -> String {
    let envelope = DurableEnvelope(text: textContent, structured: structuredContent as? Value)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(envelope), let json = String(data: data, encoding: .utf8) {
      return json
    }
    return textContent
  }

  /// Reconstruct from a durable record. A current record is the JSON envelope;
  /// any payload that is not a valid envelope is treated as text-only.
  static func fromDurablePayload(_ payload: String) -> IdempotencyCache.CachedResult {
    if let data = payload.data(using: .utf8),
      let envelope = try? JSONDecoder().decode(DurableEnvelope.self, from: data)
    {
      return IdempotencyCache.CachedResult(
        textContent: envelope.text, structuredContent: envelope.structured)
    }
    return IdempotencyCache.CachedResult(textContent: payload, structuredContent: nil)
  }
}
