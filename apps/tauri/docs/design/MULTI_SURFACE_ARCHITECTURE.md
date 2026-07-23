# Multi-Surface Architecture

**Status:** Canonical design document

## Product Model

Lorvex is one product with two hosts and multiple surfaces:

| Host | Primary Purpose | Surfaces |
|------|----------------|----------|
| **Lorvex App** | Human GUI + privileged desktop platform host | GUI, embedded MCP for direct desktop builds |
| **Lorvex CLI** | Always-on agent runtime | MCP serve, shell commands, TUI |

- **App** is the flagship human planning experience and platform capability host for the Tauri desktop line (Windows calendar, Linux calendar/ICS, notifications, tray, desktop shell).
- **CLI** is an always-on agent runtime centered on the local DB and MCP tools. TUI is a secondary inspection surface that influences architecture, not product priority.

## Architecture Layers

```
┌─────────────────────────────────────────────────┐
│ Surfaces                                         │
│  App GUI │ CLI MCP │ CLI TUI │ CLI commands      │
├─────────────────────────────────────────────────┤
│ Hosts                                            │
│  App (Tauri)  │  CLI (Rust binary)               │
├─────────────────────────────────────────────────┤
│ Shared Runtime (lorvex-runtime)                  │
│  DB locator │ device identity │ local_change_seq │
│  sync owner lease │ capability profiles          │
│  MCP host authority │ setup/bootstrap            │
├─────────────────────────────────────────────────┤
│ Sync (lorvex-sync)                               │
│  outbox/inbox │ merge/apply │ backend adapters   │
├─────────────────────────────────────────────────┤
│ Workflow (lorvex-workflow)                       │
│  changelog │ lifecycle │ deferral │ recurrence   │
│  status side-effects │ focus │ memory │ timezone │
├─────────────────────────────────────────────────┤
│ Store (lorvex-store)                             │
│  schema │ repos │ projections │ transactions     │
├─────────────────────────────────────────────────┤
│ Domain (lorvex-domain)                           │
│  planning semantics │ lifecycle │ validation     │
├─────────────────────────────────────────────────┤
│ Platform Capability Hosts                        │
│  Windows calendar │ Linux ICS                    │
│  notifications │ tray │ desktop shell            │
└─────────────────────────────────────────────────┘
```

## Same-Machine Coexistence

All surfaces on the same machine share one canonical local SQLite DB (WAL mode). There is no inter-surface sync protocol.

### Local Visibility

- Every mutation bumps `local_change_seq` (monotonic counter in `local_counters`)
- Each surface polls or watches `local_change_seq` to detect sibling writes
- App uses event_bus + data_changed events (intra-process)
- CLI TUI uses `--watch` with 250ms polling
- MCP reads are always fresh from the DB
- No IPC, named pipes, or inter-process messaging

### Sync Ownership

Remote sync backends use lease-based ownership:

- **Tauri desktop:** Filesystem bridge sync uses `local_sync_owner` lease. Only one process owns the sync at a time.
- **Future providers:** New non-Apple providers should use the same lease/apply model instead of adding one-off ownership rules.

## MCP Host Authority

At any time, exactly **one** Lorvex MCP endpoint is exposed to external agents (Claude Code, Codex, OpenClaw). There are never two simultaneous registrations.

The active host choice is persisted in the singleton `mcp_host_authority` table (`host` = `"cli"` or `"app"`, priority, recorded host path, and update timestamp). Both App and CLI read this table to understand the current authority. CLI claims `"cli"` during `lorvex setup --install-mcp-for` and `lorvex mcp install`; normal claims are priority-ordered so CLI outranks App when both are installed. The App has a separate explicit reclaim path: when its embedded MCP helper resolves and the standalone CLI binary is not detected, it stores `"app"` only if there is no authority yet, or if the existing CLI authority recorded a CLI executable path that is now missing/non-executable. A custom CLI install with a still-valid recorded path keeps authority even if it lives outside the detector's well-known paths.

### Selection Rules

| Installed | Active MCP Host | Notes |
|-----------|----------------|-------|
| App only | App | App's embedded MCP binary serves stdio when bundled |
| CLI only | CLI | `lorvex mcp serve` |
| Both App + CLI | CLI (recommended) | CLI setup offers to take over; App stops external MCP |

- When CLI is installed alongside App, `lorvex setup` or `lorvex mcp install` should migrate the MCP config from App's binary to CLI's.
- When CLI is removed or absent, opening App MCP status reclaims authority for the App if the embedded MCP helper is available and the recorded CLI executable path is gone.
- App can still internally use MCP semantics for its own GUI operations.
- The MCP config in Claude Code / Codex points to exactly one binary path.

### Direct Desktop App + No CLI

The direct desktop app should remain usable without a separate CLI install. When
the embedded MCP helper is bundled and available, it can serve MCP via stdio.
Apple App Store distribution is owned by the Swift app under `apps/apple`, not
by this Tauri host.

## Capability Profiles

Each surface has a capability profile that determines which features are available:

| Capability | desktop_app | desktop_cli_agent | desktop_cli_tui |
|-----------|------------|-------------------|-----------------|
| Full GUI | yes | no | no |
| MCP capable | yes (embedded) | yes (primary) | no |
| Sync owner | yes | yes | no |
| Local DB read/write | yes | yes | yes |
| Sync outbox write | yes | yes | yes |
| TUI dashboard | no | no | yes |
| Shell/JSON output | no | yes | yes |
| Calendar subscription management (`lorvex subscription {list,add,remove,refresh,toggle}`) | yes (Settings UI) | yes | no |

## Code Organization

```
lorvex-domain/       Pure domain logic (no unconditional IO/storage deps; feature-gated rusqlite typed-id bindings)
lorvex-store/        SQLite storage layer: connections, migrations, repositories, projections, blob storage
lorvex-workflow/     Shared cross-surface workflow operations: canonical SQL mutations + business rules for App, CLI, MCP, and sync apply
lorvex-sync/         Sync protocol layer: envelope/outbox/tombstone/pending-inbox/apply pipeline; calls workflow for shared apply-side mutations
lorvex-runtime/      Shared operating model (DB, identity, leases, capabilities)
lorvex-mcp-derive/   Internal proc-macro support for MCP contract validation; compile-time codegen only, consumed by mcp-server
lorvex-cli/          CLI host (commands/, mcp/, tui/, render/)
mcp-server/          MCP transport (shared between App and CLI)
app/src-tauri/       App host (GUI shell + privileged platform adapters)
```

Ownership boundary:

- `lorvex-domain` owns pure semantics and validation primitives; it has no unconditional IO/storage dependency.
- `lorvex-store` owns persistence primitives and read/write repositories, but not cross-surface business workflows.
- `lorvex-workflow` owns mutations that must behave identically across surfaces: changelog logging, task lifecycle transitions, deferral, recurrence configuration, habit reminder policy updates, status side effects, memory operations, reseed flows, dependency validation, task enrichment, note summaries, focus operations, and timezone helpers.
- `lorvex-sync` owns transport-independent sync records and conflict/apply orchestration. When sync apply needs a normal domain mutation, it routes through `lorvex-workflow` instead of reimplementing App/MCP/CLI behavior. The apply pipeline contract — wire envelope, dispatch table, LWW rules, FK retry, tombstone redirect, conflict log, idempotency cache — is documented in [SYNC_APPLY_SEMANTICS.md](SYNC_APPLY_SEMANTICS.md).
- `lorvex-mcp-derive` has no runtime ownership. It is an internal proc-macro crate for MCP contract validation derives used by `mcp-server`.

## Design Principles

1. **No surface owns the truth.** The canonical state is in the shared local DB, not in any process.
2. **Mixed mode is a first-class scenario.** App + CLI running simultaneously is expected, not exceptional.
3. **One external MCP endpoint.** Never two Lorvex MCP registrations in the same agent config.
4. **CLI is agent-first.** Its primary value is as an always-on MCP runtime, not as a terminal app.
5. **TUI influences architecture, not product priority.** Its existence ensures the runtime layer is correctly shared, but it is not the driving product surface.
6. **Platform privileges stay with App.** Windows calendar, Linux calendar, notifications, tray, and other OS integrations are App-owned in the Tauri line.
