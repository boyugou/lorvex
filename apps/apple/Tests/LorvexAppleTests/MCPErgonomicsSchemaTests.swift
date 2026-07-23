import MCP
import Testing

@testable import LorvexMCPHost

/// Schema- and description-level contracts for the MCP ergonomics pass: the
/// public input schemas advertise one name per concept (`tags`, not `tags_set`),
/// reserve the word "defer" for the planned-date push, make the focus write
/// `date` optional, and expose the `checklist` / `include_stats` additions.
///
/// These assert against the frozen catalog schemas via `ToolDefinitionRegistry`,
/// which the manifest lock (`verify_mcp_tool_manifest.py`) mirrors.
@Suite("MCP ergonomics — schema and description contracts")
struct MCPErgonomicsSchemaTests {
  private func tool(_ name: String) -> Tool? {
    ToolDefinitionRegistry.byName[name]?.tool
  }

  private func properties(_ name: String) -> [String: Value] {
    tool(name)?.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
  }

  private func required(_ name: String) -> [String] {
    tool(name)?.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
  }

  private func description(_ name: String) -> String {
    tool(name)?.description ?? ""
  }

  /// Item-level properties of a batch tool's array argument.
  private func batchItemProperties(_ name: String, arrayKey: String) -> [String: Value] {
    properties(name)[arrayKey]?.objectValue?["items"]?.objectValue?["properties"]?.objectValue ?? [:]
  }

  private func paramDescription(_ tool: String, _ param: String) -> String {
    properties(tool)[param]?.objectValue?["description"]?.stringValue ?? ""
  }

  /// Every user-visible string a tool advertises — its description plus every
  /// string reachable in its input schema — for a whole-surface vocabulary scan.
  private func advertisedText(_ tool: Tool) -> String {
    var parts: [String] = [tool.description ?? ""]
    Self.collectStrings(tool.inputSchema, into: &parts)
    return parts.joined(separator: "\n")
  }

  private static func collectStrings(_ value: Value, into parts: inout [String]) {
    switch value {
    case .string(let text): parts.append(text)
    case .array(let array): array.forEach { collectStrings($0, into: &parts) }
    case .object(let dict): dict.values.forEach { collectStrings($0, into: &parts) }
    default: break
    }
  }

  // MARK: - R1: one public name for the tags param

  @Test("R1: create_task / update_task expose tags, not tags_set")
  func r1SingleTagsNameOnSingleTools() {
    for name in ["create_task", "update_task"] {
      #expect(properties(name)["tags"] != nil, "\(name) should expose tags")
      #expect(properties(name)["tags_set"] == nil, "\(name) should not expose tags_set")
    }
  }

  @Test("R1: batch create/update item schemas expose tags, not tags_set")
  func r1SingleTagsNameOnBatchTools() {
    let createItems = batchItemProperties("batch_create_tasks", arrayKey: "tasks")
    #expect(createItems["tags"] != nil)
    #expect(createItems["tags_set"] == nil)

    let updateItems = batchItemProperties("batch_update_tasks", arrayKey: "updates")
    #expect(updateItems["tags"] != nil)
    #expect(updateItems["tags_set"] == nil)
  }

  @Test("R1: no tool description mentions tags_set")
  func r1NoTagsSetInDescriptions() {
    for definition in ToolDefinitionRegistry.all {
      #expect(
        !advertisedText(definition.tool).contains("tags_set"),
        "\(definition.tool.name) still advertises tags_set")
    }
  }

  // MARK: - E1: the word "defer" is reserved for the planned-date push

  @Test("E1: no tool advertises the defer-until vocabulary")
  func e1NoDeferUntilVocabulary() {
    for definition in ToolDefinitionRegistry.all {
      #expect(
        !advertisedText(definition.tool).lowercased().contains("defer-until"),
        "\(definition.tool.name) still uses the defer-until vocabulary")
    }
  }

  @Test("E1: available_from descriptions steer away from defer_task")
  func e1AvailableFromSteering() {
    for name in ["create_task", "update_task"] {
      let text = paramDescription(name, "available_from")
      #expect(text.contains("not-before"), "\(name) available_from should read as not-before")
      #expect(text.contains("defer_task"), "\(name) available_from should name defer_task")
    }
    let batchCreateAF =
      batchItemProperties("batch_create_tasks", arrayKey: "tasks")["available_from"]?
      .objectValue?["description"]?.stringValue ?? ""
    #expect(batchCreateAF.contains("not-before"))
  }

  @Test("E1: defer tools steer callers to available_from for hide-only intent")
  func e1DeferSteering() {
    for name in ["defer_task", "batch_defer_tasks"] {
      #expect(
        description(name).contains("available_from"),
        "\(name) should point at available_from for hide-only rescheduling")
    }
  }

  // MARK: - E5: focus write tools default date to today

  @Test("E5: date is optional on the four focus write tools")
  func e5FocusDateOptional() {
    for name in [
      "set_current_focus", "add_to_current_focus", "remove_from_current_focus",
      "clear_current_focus",
    ] {
      #expect(!required(name).contains("date"), "\(name) should not require date")
      #expect(properties(name)["date"] != nil, "\(name) should still document date")
      #expect(
        paramDescription(name, "date").contains("today"),
        "\(name) date should document the today default")
    }
  }

  @Test("E5: save_focus_schedule keeps date required")
  func e5ScheduleStillRequiresDate() {
    #expect(required("save_focus_schedule").contains("date"))
  }

  // MARK: - G1: checklist at create

  @Test("G1: checklist param present on create_task and batch_create_tasks")
  func g1ChecklistParam() {
    let create = properties("create_task")["checklist"]?.objectValue
    #expect(create?["type"]?.stringValue == "array")
    #expect(create?["items"]?.objectValue?["type"]?.stringValue == "string")

    let batchItem = batchItemProperties("batch_create_tasks", arrayKey: "tasks")["checklist"]?
      .objectValue
    #expect(batchItem?["type"]?.stringValue == "array")
  }

  // MARK: - G2: all-habit stats

  @Test("G2: include_stats present on get_habits and cross-referenced both ways")
  func g2IncludeStats() {
    #expect(
      properties("get_habits")["include_stats"]?.objectValue?["type"]?.stringValue == "boolean")
    #expect(description("get_habits").contains("include_stats"))
    #expect(description("get_habit_stats").contains("include_stats"))
  }
}
