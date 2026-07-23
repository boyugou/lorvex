import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with MCPToolRegistryTests)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xtext(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let t, _, _) = $0 { return t }
    return nil
  }.joined()
}

// MARK: - Task Recurrence

@Suite("MCP Extended — task recurrence")
struct TaskRecurrenceExtendedTests {

  private func makeTask(_ registry: ToolRegistry, title: String) async throws -> String {
    let created = try await xcall(
      registry, tool: "create_task", arguments: ["title": .string(title)])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  @Test("set_task_recurrence returns the task with the correct id")
  func setRecurrenceRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Weekly recurring")
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["freq": .string("weekly"), "interval": .int(1)]),
      ]
    )
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    let id = object?["id"]?.stringValue
    #expect(id == taskID)
    #expect(object?["recurrence"]?.objectValue?["freq"]?.stringValue == "weekly")
    #expect(object?["recurrence"]?.objectValue?["interval"]?.intValue == 1)
  }

  @Test("set_task_recurrence rejects a byday with a non-string element instead of dropping it")
  func setRecurrenceRejectsMalformedByday() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Bad byday")
    // Dropping the non-string element would silently apply a DIFFERENT weekly
    // schedule than the caller requested — the recurrence must be rejected.
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object([
          "freq": .string("weekly"),
          "byday": .array([.string("MO"), .int(3)]),
        ]),
      ]
    )
    #expect(result.isError == true)
    let text = result.content.compactMap {
      if case .text(let value, _, _) = $0 { return value }
      return nil
    }.joined(separator: "\n")
    #expect(text.contains("byday must contain only strings"))
  }

  @Test("set_task_recurrence rejects present wrong-typed scalar fields")
  func setRecurrenceRejectsMalformedScalars() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Bad scalar recurrence")
    for (field, value, expectedMessage) in [
      ("interval", Value.string("2"), "interval must be an integer"),
      ("count", Value.string("5"), "count must be an integer"),
      ("wkst", Value.int(1), "wkst must be a string"),
      ("until", Value.int(20261231), "until must be a string"),
      ("anchor", Value.bool(true), "anchor must be a string"),
    ] {
      let result = try await xcall(
        registry, tool: "set_task_recurrence",
        arguments: [
          "task_id": .string(taskID),
          "recurrence": .object([
            "freq": .string("weekly"),
            field: value,
          ]),
        ])
      #expect(result.isError == true)
      #expect(xtext(result).contains(expectedMessage))
    }
  }

  @Test("remove_task_recurrence clears the rule and exceptions")
  func removeRecurrence() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Recurrence to clear")
    _ = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["freq": .string("weekly"), "interval": .int(1)]),
      ]
    )
    _ = try await xcall(
      registry, tool: "add_task_recurrence_exception",
      arguments: [
        "task_id": .string(taskID),
        "occurrence_date": .string("2026-06-15"),
      ]
    )

    let result = try await xcall(
      registry, tool: "remove_task_recurrence",
      arguments: ["task_id": .string(taskID)]
    )

    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["id"]?.stringValue == taskID)
    #expect(object?["recurrence"] == .null)
    // An exception-free task serializes recurrence_exceptions as null.
    #expect(object?["recurrence_exceptions"] == .null)
  }

  @Test("set_task_recurrence accepts a multi-day bymonthday array")
  func setRecurrenceBymonthdayArray() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Monthly multi-day")
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object([
          "freq": .string("monthly"),
          "bymonthday": .array([.int(1), .int(15)]),
        ]),
      ]
    )
    #expect(result.isError != true)
    let recurrence = result.structuredContent?.objectValue?["recurrence"]?.objectValue
    #expect(recurrence?["bymonthday"]?.arrayValue?.compactMap(\.intValue) == [1, 15])
  }

  @Test("set_task_recurrence tolerates a scalar bymonthday for back-compat")
  func setRecurrenceBymonthdayScalarBackCompat() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Monthly scalar day")
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object([
          "freq": .string("monthly"),
          "bymonthday": .int(15),
        ]),
      ]
    )
    #expect(result.isError != true)
    let recurrence = result.structuredContent?.objectValue?["recurrence"]?.objectValue
    #expect(recurrence?["bymonthday"]?.arrayValue?.compactMap(\.intValue) == [15])
  }

  @Test("ordinal BYDAY reaches runtime validation for its frequency")
  func ordinalBydayUsesFrequencySpecificRuntimeValidation() async throws {
    let registry = try mcpInMemoryRegistry()
    let monthlyID = try await makeTask(registry, title: "First Monday")
    let monthly = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(monthlyID),
        "recurrence": .object([
          "freq": .string("monthly"),
          "byday": .array([.string("1MO")]),
        ]),
      ])
    #expect(monthly.isError != true)
    #expect(
      monthly.structuredContent?.objectValue?["recurrence"]?.objectValue?["byday"]?
        .arrayValue == [.string("1MO")])

    let weeklyID = try await makeTask(registry, title: "Invalid ordinal week")
    let weekly = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(weeklyID),
        "recurrence": .object([
          "freq": .string("weekly"),
          "byday": .array([.string("1MO")]),
        ]),
      ])
    #expect(weekly.isError == true)
    #expect(xtext(weekly).contains("WEEKLY rejects ordinal prefixes"))
  }

  @Test("set_task_recurrence with missing task_id returns structured error")
  func setRecurrenceMissingTaskID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: ["recurrence": .object(["freq": .string("daily")])]
    )
    #expect(result.isError == true)
  }

  @Test("set_task_recurrence with recurrence missing freq returns structured error")
  func setRecurrenceMissingFreq() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Freq-less rule target")
    let result = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["interval": .int(1)]),
      ]
    )
    #expect(result.isError == true)
  }

  @Test("add_task_recurrence_exception adds the date to a recurring task")
  func addRecurrenceException() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Recurring with exception")
    _ = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["freq": .string("daily"), "interval": .int(1)]),
      ]
    )
    let result = try await xcall(
      registry, tool: "add_task_recurrence_exception",
      arguments: [
        "task_id": .string(taskID),
        "occurrence_date": .string("2026-06-15"),
      ]
    )
    #expect(result.isError != true)
    let exceptions = result.structuredContent?.objectValue?["recurrence_exceptions"]?.arrayValue ?? []
    #expect(exceptions.map(\.stringValue).contains("2026-06-15"))
  }

  @Test("add_task_recurrence_exception requires an existing recurrence rule")
  func addExceptionRequiresRecurrenceRule() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Rule-less exception target")
    let result = try await xcall(
      registry, tool: "add_task_recurrence_exception",
      arguments: [
        "task_id": .string(taskID),
        "occurrence_date": .string("2026-06-15"),
      ]
    )
    #expect(result.isError == true)
    #expect(xtext(result).contains("no recurrence rule"))
  }

  @Test("remove_task_recurrence_exception returns non-error result after add")
  func removeRecurrenceException() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Exception to remove")
    _ = try await xcall(
      registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["freq": .string("daily"), "interval": .int(1)]),
      ]
    )
    _ = try await xcall(
      registry, tool: "add_task_recurrence_exception",
      arguments: [
        "task_id": .string(taskID),
        "occurrence_date": .string("2026-06-20"),
      ]
    )
    let result = try await xcall(
      registry, tool: "remove_task_recurrence_exception",
      arguments: [
        "task_id": .string(taskID),
        "occurrence_date": .string("2026-06-20"),
      ]
    )
    #expect(result.isError != true)
    let exceptions = result.structuredContent?.objectValue?["recurrence_exceptions"]?.arrayValue ?? []
    #expect(!exceptions.map(\.stringValue).contains("2026-06-20"))
  }

  @Test("add_task_recurrence_exception with unknown task returns structured error")
  func addExceptionUnknownTask() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "add_task_recurrence_exception",
      arguments: [
        "task_id": .string("no-such-task"),
        "occurrence_date": .string("2026-06-15"),
      ]
    )
    #expect(result.isError == true)
  }
}
