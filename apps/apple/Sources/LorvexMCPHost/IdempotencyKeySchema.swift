import MCP

/// Shared input-schema fragment for the optional `idempotency_key` argument
/// advertised by write tools.
///
/// A write's ``ToolDefinition`` binds this advertised property to the runtime
/// idempotency policy. The contract: retrying with the same key and identical
/// arguments replays the original result instead of writing again; reusing the
/// key with different arguments is rejected.
enum IdempotencyKeySchema {
  static let propertyName = "idempotency_key"

  static let property: Value = .object([
    "type": .string("string"),
    "description": .string(
      "Optional client-supplied key; retrying with the same key and identical arguments replays the original result instead of writing again. Reusing the key with different arguments is rejected."
    ),
  ])
}
