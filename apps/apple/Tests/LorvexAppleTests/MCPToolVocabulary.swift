import Foundation
import MCP

@testable import LorvexMCPHost

/// The identifiers an assistant can act on through the registered MCP tools:
/// tool names, input parameter names at any depth, the string values of every
/// `enum`, and the snake_case words the tool descriptions themselves document,
/// which covers response fields (`frequently_deferred`) and the memory keys
/// `write_memory` lists.
///
/// Guidance written for assistants (the server instructions and the Claude Code
/// plugin's skills) may only name these, so a renamed tool, parameter, or enum
/// value fails a test instead of leaving guidance that points at nothing.
enum MCPToolVocabulary {
  static func identifiers() -> Set<String> {
    let tools = ToolRegistry.listTools()
    var known = Set(tools.map(\.name))
    for tool in tools {
      collect(tool.inputSchema, into: &known)
      known.formUnion(snakeCaseIdentifiers(in: tool.description ?? ""))
    }
    return known
  }

  /// Every lowercase snake_case word in `text` with at least one underscore.
  static func snakeCaseIdentifiers(in text: String) -> Set<String> {
    Set(text.matches(of: #/[a-z]+(?:_[a-z]+)+/#).map { String($0.output) })
  }

  private static func collect(_ value: Value, into names: inout Set<String>) {
    switch value {
    case .object(let object):
      if case .object(let properties)? = object["properties"] {
        names.formUnion(properties.keys)
      }
      if case .array(let values)? = object["enum"] {
        names.formUnion(values.compactMap(\.stringValue))
      }
      for child in object.values { collect(child, into: &names) }
    case .array(let array):
      for child in array { collect(child, into: &names) }
    default:
      break
    }
  }
}
