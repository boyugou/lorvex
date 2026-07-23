# MCP Swift-Native Strategy

## Decision

The Apple-native edition uses a Swift-native MCP server/helper. The existing
Rust MCP server is not part of the Apple product architecture and is not a
fallback.

Correctness-heavy domains — database migrations, sync/outbox sequencing,
HLC/version discipline, audit logs, recurrence effects, dependency validation,
and other workflow invariants — live in the pure-Swift `LorvexAppleCore`
package (`LorvexDomain/Store/Workflow/Sync`). The MCP server is an Apple product
surface: tool catalog organization, argument normalization, client
compatibility, preview behavior, result shaping, and assistant-facing
affordances are owned in the Swift MCP modules.

## Target Shape

- `LorvexMCPHost` stays a thin executable entry point.
- Tool catalogs are grouped by domain, matching the original MCP server's
  domain split: tasks, focus, lists, habits, calendar, reviews, memory, and
  system diagnostics.
- Tool handlers are grouped by domain and call the `LorvexCoreServicing`
  boundary rather than reaching directly into a giant registry.
- The boundary has one implementation — `SwiftLorvexCoreService` over the
  `LorvexAppleCore` package — opened on-disk in production and over an
  in-memory GRDB store for fast host smoke tests.
- Core workflow ops live in domain modules within `LorvexAppleCore`
  (`LorvexWorkflow`), not in one dispatcher file.

## Module Rule

MCP-surface concerns (catalogs, handlers, dispatch, result shaping) live in
Swift MCP modules. Data-consistency, sync-correctness, audit, recurrence, and
dependency invariants live in the `LorvexAppleCore` package, reached only
through the `LorvexCoreServicing` boundary.

In practice:

- MCP-surface (own in the Swift MCP modules): tool schema/catalogs, argument
  parsing, preview semantics, result presentation, client config, helper launch
  policy.
- Core-owned (in `LorvexAppleCore`, reached via `LorvexCoreServicing`): task
  batch workflow mutations, deferral analytics, recurrence successor behavior,
  dependency cycle checks, sync outbox effects, local change sequence,
  audit/event logs.

## Module Organization

`Sources/LorvexMCPHost/LorvexMCPHost.swift` is a thin (~80-line) executable
entry point. The MCP surface is split across per-domain `*ToolCatalog.swift`
(schema) and `*ToolHandlers.swift` (implementation) files, with dispatch in
`ToolRegistry*.swift`. A new MCP domain adds its own catalog/handler pair rather
than growing a single registry file.

Task batch work follows this split: `BatchTaskToolCatalog` (schema) with
`BatchTaskCreateToolHandlers` / `BatchTaskUpdateToolHandlers`, and the underlying
batch operation living in the `LorvexAppleCore` workflow module
(`LorvexWorkflow`), reached through the `LorvexCoreServicing` boundary.
