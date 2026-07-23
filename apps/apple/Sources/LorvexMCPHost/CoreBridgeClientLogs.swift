import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadAIChangelog(
    limit: Int?,
    offset: Int?,
    entityType: String?,
    operation: String?,
    entityID: String?,
    since: String?
  ) async throws -> Value {
    let changelog = try await service.loadAIChangelog(
      limit: limit,
      offset: offset,
      entityType: entityType,
      operation: operation,
      entityID: entityID,
      since: since)
    let entries = changelog.entries.map { entry -> Value in
      .object([
        "id": .string(entry.id),
        "timestamp": entry.timestamp.map(Value.string) ?? .null,
        "entity_type": .string(entry.entityType),
        "operation": .string(entry.operation),
        "entity_id": entry.entityId.map(Value.string) ?? .null,
        "summary": .string(entry.summary),
        "initiated_by": entry.initiatedBy.map(Value.string) ?? .null,
        "mcp_tool": entry.mcpTool.map(Value.string) ?? .null,
      ])
    }
    // The changelog snapshot is an offset-paged stream with no precomputed
    // total: when this page isn't truncated, `offset + returned` is the exact
    // total; when it is, the total is unknown, so `total_matching` is null.
    let resolvedOffset = offset ?? 0
    let total = changelog.truncated ? nil : resolvedOffset + entries.count
    return MCPPagination.object(
      domain: ["entries": .array(entries)],
      totalMatching: total, returned: entries.count, limit: limit ?? 50,
      offset: resolvedOffset, nextOffset: changelog.nextOffset, truncated: changelog.truncated)
  }

  func loadRecentLogs(
    limit: Int?,
    offset: Int?,
    since: String?,
    level: String?,
    levels: [String]?,
    source: String?,
    sources: [String]?,
    includeDetails: Bool?,
    redact: Bool?
  ) async throws -> Value {
    // Fold the singular `level`/`source` into the plural filters (nil = no filter).
    let mergedLevels = Self.mergeFilter(level, levels)
    let mergedSources = Self.mergeFilter(source, sources)
    let resolvedLimit = limit ?? 100
    let resolvedOffset = offset ?? 0
    let withDetails = includeDetails ?? false

    let page = try await service.loadRecentLogs(
      limit: resolvedLimit, offset: resolvedOffset, since: since,
      levels: mergedLevels, sources: mergedSources, redact: redact ?? true)

    let entries = page.entries.map { entry -> Value in
      var object: [String: Value] = [
        "id": .string(entry.id),
        "timestamp": entry.timestamp.map(Value.string) ?? .null,
        "source": .string(entry.source),
        "level": .string(entry.level.rawValue),
        "summary": .string(entry.summary),
      ]
      if withDetails {
        object["details"] = entry.details.map(Value.string) ?? .null
      }
      return .object(object)
    }
    let returned = page.entries.count
    let truncated = resolvedOffset + returned < page.totalMatching
    let sourceCounts: Value = .object(page.sourceCounts.mapValues(Value.int))
    return MCPPagination.object(
      domain: [
        "redaction_applied": .bool(page.redactionApplied),
        "details_included": .bool(withDetails),
        "source_counts": sourceCounts,
        "malformed_source_counts": .object([:]),
        "entries": .array(entries),
      ],
      totalMatching: page.totalMatching, returned: returned, limit: resolvedLimit,
      offset: resolvedOffset, nextOffset: truncated ? resolvedOffset + returned : nil,
      truncated: truncated)
  }

  /// Fold a singular filter value into an optional plural list; returns nil
  /// (no filter) when both are absent, deduping while preserving order.
  private static func mergeFilter(_ single: String?, _ many: [String]?) -> [String]? {
    var out: [String] = many ?? []
    if let single, !out.contains(single) { out.append(single) }
    return out.isEmpty ? nil : out
  }
}
