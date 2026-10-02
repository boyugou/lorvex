# Documentation index

Project-level (monorepo-wide) docs live here. App-specific docs live under each
app.

## Monorepo-level

- [`../README.md`](../README.md) — what the monorepo is.
- [`../CLAUDE.md`](../CLAUDE.md) — operating manual for agents.
- [`../ROADMAP.md`](../ROADMAP.md) — status by lane (Apple / Shared).

## Platform ownership

- **Apple Swift** (`../apps/apple`) owns every distribution and capability:
  macOS App Store, direct macOS builds, iOS, iPadOS, watchOS, WidgetKit, App
  Intents, EventKit, CloudKit/iCloud, and other Apple-native integration work.
  The former cross-platform Tauri line was removed on 2026-09-17.

## Design & vision

Behavioral contracts and product philosophy for the Apple app.

- [`vision/DESIGN_PHILOSOPHY.md`](vision/DESIGN_PHILOSOPHY.md) — AI-native product philosophy, the control-model inversion, and design principles.
- [`design/AI_OPERATING_MODEL.md`](design/AI_OPERATING_MODEL.md) — Assistant operating model: how guidance reaches an assistant (server instructions, plugin skills, tool descriptions), the chief-of-staff model, operational patterns, and session protocol.
- [`design/CALENDAR_BEHAVIOR.md`](design/CALENDAR_BEHAVIOR.md) — Three-family calendar ownership model (tasks / canonical events / provider mirrors) and interaction rules.
- [`design/SORT_KEYS.md`](design/SORT_KEYS.md) — Canonical task sort key (`priority_effective ASC, due_date ASC NULLS LAST, id ASC`) and allowed per-view deviations.
- [`design/SYNC_APPLY_SEMANTICS.md`](design/SYNC_APPLY_SEMANTICS.md) — Sync apply pipeline, HLC conflict resolution, LWW rules, idempotency, and ai_changelog semantics.
- [`design/SCHEMA_OPTIMALITY.md`](design/SCHEMA_OPTIMALITY.md) — The two-regime schema invariant behind the post-launch schema-freeze gate.
- [`design/EXPORT_IMPORT_PARITY.md`](design/EXPORT_IMPORT_PARITY.md) — The version-1 data export/import contract behind Settings → Data: portable category documents, the Apple-native task-graph member, JSON and ZIP containers, and retained per-version decoders.

## Shared artifacts

- [`../schema/README.md`](../schema/README.md) — SQLite schema authority + parity.
- [`../spec/README.md`](../spec/README.md) — cross-language behavior contract.
- [`../cloudkit/README.md`](../cloudkit/README.md) — the Apple app's
  authoritative CloudKit record-type deploy contract (`schema.ckdb`).

## Assistant integration

- [`../plugins/lorvex/README.md`](../plugins/lorvex/README.md) — the Claude Code
  plugin: MCP launcher, skills, install, and updates.
- [`../apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md`](../apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md)
  — connecting any MCP client to the helper inside the app.

## Decision records

Why the repository is shaped the way it is:

- [`decisions/pure-swift-core-port.md`](decisions/pure-swift-core-port.md) — the Apple core's port to pure Swift and the monorepo structure.
- [`decisions/today-one-list.md`](decisions/today-one-list.md) — Today as one list: the concepts that replace Focus, the page, glances, and the assistant's planning flow.
- [`decisions/cksyncengine-transport.md`](decisions/cksyncengine-transport.md) — The CloudKit transport on `CKSyncEngine`: what stays (record format, apply layer, outbox), what goes with the custom zone-generation protocol, and the schema migration that retires its tables.

## App docs

- `../apps/apple/docs/` (surface design, design system, setup, reference, architecture, execution) and `../apps/apple/CLAUDE.md`.
