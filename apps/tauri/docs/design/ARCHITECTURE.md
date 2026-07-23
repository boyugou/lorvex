# Architecture
---

## What Lorvex Is

Lorvex is an **AI-native planning system** with a **first-class standalone app experience**.

That means two things are true at the same time:

1. AI-assisted operation is a core part of the product, not an optional gimmick.
2. The app itself must still be strong, coherent, and genuinely useful even when MCP is unavailable.

Lorvex does **not** ship an embedded model runtime inside the GUI. Instead:

- the app is the human workspace
- MCP is a first-class operator surface on capable desktop runtimes
- shared data, sync, and semantic ownership are the architectural center

The architecture exists to support that product shape. It is not the product headline.

---

## Top-Level System Model

### Product model

Lorvex is not:

- "a normal task manager with some AI on the side"
- "an MCP server with a thin GUI attached"
- "one primary desktop runtime plus secondary clients"

Lorvex is:

- an AI-native planning system
- with one canonical data model
- shared across multiple runtimes
- with different capability profiles

### Runtime model

The target runtime model is **peer runtimes with different capabilities**:

- **desktop runtimes**: can host MCP, expose tray/menu-bar surfaces, floating windows, heavier multi-window workflows
- **mobile runtimes**: cannot host MCP, but still run the same canonical schema and sync semantics with a reduced product shape

Desktop is not semantically privileged. Mobile is not a passive mirror.

### Surface model

Lorvex has multiple first-class surfaces:

1. **App GUI** — Today, Lists, Calendar, Review, Memory
2. **MCP** — assistant-operated planning, restructuring, triage, maintenance, review prep
3. **Widget / glance surfaces** — widgets, menu bar, notifications, quick status surfaces
4. **Capture surfaces** — quick capture, share sheet, shortcuts, URL scheme, mobile capture
5. **Background/system surfaces** — sync loops, reminder delivery, provider refresh, maintenance

No single surface owns the product. All of them depend on the same core semantics.

---

## The Architectural Center

The architectural center of Lorvex is:

- one canonical SQLite data model per device
- one shared semantic core for mutations and reads
- one sync protocol for cross-device convergence

This is what lets all surfaces stay consistent.

### Consequences

- Desktop GUI and MCP are peers over the same semantic owners.
- Future mobile runtimes should not invent alternate data models or alternate merge rules.
- Native integrations such as Windows Appointments, Linux calendar/ICS, and Android CalendarContract must attach through provider mirrors or transport adapters, not bypass canonical ownership.
- Export/import, sync, and audit are distinct subsystems with different responsibilities.

---

## Current Runtime Picture

Today the most complete runtime is:

- desktop app
- plus MCP-capable assistant
- plus local SQLite
- plus optional sync transport

That is the **strongest current operator experience**, not the definition of the entire product.

The Tauri product-facing line is Windows/Linux desktop. Its macOS build is a
developer/reference runtime, not the future Apple customer channel. iOS and
iPadOS now belong to the Swift app under `apps/apple`; Android remains the
only planned Tauri mobile runtime.

#### Android runtime constraints (target shape)

The future Android shell should observe deliberate restrictions that diverge
from the desktop runtime:

- **No local MCP hosting.** MCP hosting remains a desktop/operator capability.
- **OS-constrained background work.** Sync and reminders must honor Android
  background execution policy instead of assuming desktop-style long-running
  loops.
- **Provider mirrors stay canonical.** Native Android calendar reads, if added,
  must mirror into provider tables rather than writing canonical event truth
  directly.

---

## Architecture Layers

### 1. Product/runtime layer

Defines:

- what each runtime is allowed to do
- which surfaces exist on which runtime
- which platform affordances are available

This is where desktop vs mobile differences belong.

### 2. Core data and semantics layer

Defines:

- canonical entities and relationships
- validation and naming rules
- shared mutation ownership
- shared business reads
- sync envelope semantics

This layer should not depend on any particular UI or platform shell.

### 3. Transport and platform adapter layer

Defines:

- filesystem/filesystem-bridge sync
- future file-provider / cloud-drive sync
- native calendar readers
- biometrics, widgets, tray integrations, etc.

These are adapters over the core, not the place where truth or product hierarchy is decided.

---

## Crate/Runtime Split

At a high level:

```text
lorvex-domain
  pure types, value objects, naming, validation, merge rules

lorvex-runtime
  cross-surface operating model: DB locator, device identity, sync ownership,
  MCP host authority, local change sequence

lorvex-sync-payload
  forward-compat payload shadow + attendee shadow types shared by store
  (export/import + calendar enrichment) and sync (apply pipeline + redirect
  merge). Depends only on lorvex-domain so the sync layer can sit above the
  storage layer without forming a cycle through these shadow primitives.

lorvex-store
  schema, repositories, shared operations, projections, blob/filesystem
  bookkeeping, per-entity payload loaders that produce canonical JSON
  payloads from local rows

lorvex-workflow
  cross-surface workflow operations: changelog, task lifecycle, deferral, recurrence
  config, habit reminder ops, status side effects, memory ops, reseed,
  dependency_validation, task_enrichment, note_summary, timezone,
  calendar_event, calendar_subscription, calendar_normalization,
  calendar_recurrence_scope, daily_review_date, list_reorganize, mutation +
  mutation_extras (canonical mutation executor + flush trait that every
  surface drives), overview, reminder_anchor, weekly_review, and the
  task_* family (task_create, task_update, task_response, task_archive,
  task_permanent_delete, task_checklist, task_recurrence, task_reminders,
  task_ai_notes, task_bookkeeping, task_batch_create,
  task_batch_cancel, task_batch_update, task_lifecycle_undo) — the shared
  mutation primitives that every consumer surface (mcp-server, app/src-tauri,
  lorvex-cli, sync apply) calls so they stay convergent

lorvex-sync
  sync envelopes, checkpoints, merge/apply orchestration, conflict handling,
  aggregate-payload composition (current_focus / focus_schedule / daily_review /
  calendar_event roots that embed materialized child rows)

lorvex-cli
  agent-first CLI companion (queries, mutations, TUI, MCP install, setup/doctor)

mcp-server
  operator-facing tool surface

app/src-tauri
  GUI-facing IPC surface + platform integrations
```

- **DB locator.** Runtime database path resolution reports structured diagnostic
  state through callers and health-check payloads; it must not depend on stderr
  as a fallback reporting channel.

The important rule is not the exact crate count. The important rule is:

> correctness, convergence, and shared semantics belong in shared core; UI shell and platform integration stay at the boundary.

---

## MCP's Role

MCP is a first-class part of Lorvex's value proposition.

It is where:

- AI-assisted capture
- planning
- restructuring
- review preparation
- memory management
- task pattern analysis
- bulk maintenance

become dramatically better than a manual-only system.

But MCP is **not** the architectural center. The center is the shared model that MCP, the app, and future runtimes all use.

The correct mental model is:

- **desktop + MCP** = best operator experience
- **standalone app** = always real and valuable
- **shared core** = what keeps both honest

---

## Sync Model

Lorvex uses per-device local storage plus cross-device sync. The important properties are:

- each runtime owns its own local database
- sync moves canonical envelopes, not live SQLite files
- no transport backend becomes the source of truth
- platform-specific transport availability does not change product semantics

Today:

- Tauri desktop runtimes currently support a filesystem bridge
- future Tauri sync providers should reuse the same envelope/apply semantics

Future transports may include file-provider or cloud-drive adapters. Those are transport backends, not separate product modes.

---

## Platform-Native Integrations

Platform-native features should be modeled as adapters over the same core:

- macOS reference build ships no native-calendar adapter; EventKit belongs to the Apple Swift app outside the Tauri tree
- Windows calendar via the Windows Appointments API
- Android calendar is a future target with no native-calendar adapter contract yet
- Linux calendar via local `.ics`/provider scanning
- Apple Swift runtimes own WidgetKit and Apple mobile adapters outside the Tauri tree
- tray/menu bar/desktop overlays on desktop runtimes

Current Rust implementation detail:

- the Windows Appointments adapter is bound through Microsoft's Rust for Windows ecosystem, using the `windows` crate today

Native platform data must not silently become canonical synced truth. Mirror/provider layers exist to preserve that boundary.

---

## What This Architecture Optimizes For

1. **AI-native operation** without treating the GUI as disposable
2. **Standalone product quality** on every runtime
3. **Cross-runtime semantic consistency**
4. **Optional sync** without introducing a central authoritative backend
5. **Clear trust boundaries** for AI actions, sync, and native-provider data

---

## What This Architecture Rejects

1. Primary-runtime / secondary-client product hierarchy
2. A single privileged write surface
3. Per-runtime duplicate business logic
4. Sync built around direct SQLite-file replication
5. Native provider data leaking into canonical truth
6. AI features implemented as hidden, unverifiable side effects inside the GUI

---

## Read Next

- [PLATFORM_CAPABILITY_MATRIX.md](PLATFORM_CAPABILITY_MATRIX.md)
- [DATA_MODEL.md](DATA_MODEL.md)
- [MULTI_SURFACE_ARCHITECTURE.md](MULTI_SURFACE_ARCHITECTURE.md)
