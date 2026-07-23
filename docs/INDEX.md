# Documentation index

Project-level (monorepo-wide) docs live here. App-specific docs live under each
app.

## Monorepo-level

- [`../README.md`](../README.md) — what the monorepo is.
- [`../CLAUDE.md`](../CLAUDE.md) — operating manual for agents.
- [`../ROADMAP.md`](../ROADMAP.md) — status by lane (Apple / Tauri / Shared).
- [`APPLE_DEVELOPER.md`](APPLE_DEVELOPER.md) — Apple Developer portal, code
  signing, notarization, and CloudKit setup (non-secret identifiers only).

## Platform ownership

- **Apple Swift** (`../apps/apple`) owns every Apple ecosystem distribution and
  capability: macOS App Store, direct macOS builds, iOS, iPadOS, watchOS,
  visionOS, WidgetKit, App Intents, EventKit, CloudKit/iCloud, and other
  Apple-native integration work.
- **Tauri** (`../apps/tauri`) owns Windows/Linux desktop. Its macOS build is a
  developer/reference build for Mac-only contributors, not the future Mac App
  Store, iCloud, iOS, or iPadOS path. Android is a future non-Apple mobile
  exploration and should get its own design.
- Historical Tauri CloudKit/iCloud material, including old-schema containers,
  is legacy context and can be abandoned unless a future migration design
  explicitly revives it.

## Shared design & vision

Shared behavioral contracts. Apple Swift is the canonical product
implementation; companion implementations use these docs and shared fixtures to
converge without serving as Apple's oracle.

- [`vision/DESIGN_PHILOSOPHY.md`](vision/DESIGN_PHILOSOPHY.md) — AI-native product philosophy, the control-model inversion, and design principles.
- [`design/AI_OPERATING_MODEL.md`](design/AI_OPERATING_MODEL.md) — How an AI assistant uses MCP tools: the Chief of Staff mental model, operational patterns, and session protocol.
- [`design/CALENDAR_BEHAVIOR.md`](design/CALENDAR_BEHAVIOR.md) — Three-family calendar ownership model (tasks / canonical events / provider mirrors) and interaction rules.
- [`design/SORT_KEYS.md`](design/SORT_KEYS.md) — Canonical task sort key (`priority_effective ASC, due_date ASC NULLS LAST, id ASC`) and allowed per-view deviations.
- [`design/SYNC_APPLY_SEMANTICS.md`](design/SYNC_APPLY_SEMANTICS.md) — Sync apply pipeline, HLC conflict resolution, LWW rules, idempotency, and ai_changelog semantics.
- [`design/SCHEMA_OPTIMALITY.md`](design/SCHEMA_OPTIMALITY.md) — The two-regime schema invariant behind the post-launch schema-freeze gate.

## Shared artifacts

- [`../schema/README.md`](../schema/README.md) — SQLite schema authority + parity.
- [`../spec/README.md`](../spec/README.md) — cross-language behavior contract.
- [`../cloudkit/README.md`](../cloudkit/README.md) — the Apple app's
  authoritative CloudKit record-type deploy contract (`schema.ckdb`).
  Production CloudKit/iCloud ownership is Apple Swift-only; only the Tauri-era
  containers are historical, and Tauri must not add new iCloud/CloudKit
  implementation work.

## Design specs

Cross-cutting architecture and design decisions:

- [`superpowers/specs/pure-swift-core-and-monorepo-design.md`](superpowers/specs/pure-swift-core-and-monorepo-design.md) — Apple core port to pure Swift + monorepo structure.

## Per-app docs

- **Apple:** `../apps/apple/docs/` (surface design, UX polish, setup, reference, architecture, execution) and `../apps/apple/CLAUDE.md`.
- **Tauri:** `../apps/tauri/docs/` and `../apps/tauri/CLAUDE.md`.
