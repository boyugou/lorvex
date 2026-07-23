# Memory and Notes Naming

## Scope

This document defines naming for:

- memory
- notes_for_ai
- memory revisions
- AI Activity / ai_changelog

## Current State In Code

### Memory

Observed in:

- `lorvex-domain/src/memory/`
- `app/src-tauri/src/commands/memory/`
- `mcp-server/src/memory/`

Current code reality:

- `memory` is a key/value durable knowledge layer
- `notes_for_ai` is a reserved human-owned memory key
- memory changes produce `memory_revision` rows

- annotations are separate entities
- images are separate entities

### AI Activity / ai_changelog

Observed in:

- `app/src-tauri/src/commands/diagnostics/changelog.rs`
- `mcp-server/src/system/logs/ai_changelog.rs`
- `lorvex-domain/src/naming/`
- `docs/design/COPY_GUIDELINES.md`

Current code reality:

- canonical internal noun is `ai_changelog`
- human-facing label is `AI Activity`

## Current State vs Target State

### Current State

The current repo already has four different systems that are easy to blur together in casual discussion:

- `memory`
  - durable key/value knowledge entries
- `notes_for_ai`
  - a special human-owned memory key inside the memory system
  - a separate human writing surface with annotations and images
- `ai_changelog`
  - an audit stream shown as `AI Activity`

This means the naming problem is not that the repo lacks structure. It is that several user-facing words like "notes", "memory", and "activity" can be used too loosely.

### Target State

The target state should preserve the current structural distinction and make it explicit in docs and copy:

- `memory` remains the durable structured knowledge layer
- `notes_for_ai` remains a special human-owned part of that memory system
- `AI Activity` remains the human-facing label for the audit stream

## Canonical Distinctions

### Memory

Canonical meaning:

- durable structured knowledge for AI and system context

Canonical nouns:

- `memory`
- `memory entry`
- `memory revision`

Do not use `notes` as the canonical umbrella for memory.

### notes_for_ai

Canonical meaning:

- a reserved human-owned memory section

Canonical name:

- `notes_for_ai`

UI language may humanize this, but the internal key should remain stable.

Current code reality to preserve:

- `notes_for_ai` is not a separate storage system
- it is stored through the memory stack
- it is intentionally protected from generic AI write/delete flows

### AI Activity

Canonical internal name:

- `ai_changelog`

Preferred UI name:

- `AI Activity`

Avoid using `changelog` as the primary user-facing label.

Current code reality to preserve:

- internal/runtime/entity naming remains `ai_changelog`
- app diagnostics read from `ai_changelog`
- MCP exposes `get_ai_changelog`

Target consistency rule:

- user-facing copy should say `AI Activity`
- internal/runtime/schema/sync naming should say `ai_changelog`

## Boundary Rules

Use these boundaries consistently:

- `memory` answers: what durable structured context should AI/system retain?
- `notes_for_ai` answers: what human-authored durable context should AI read?
- `AI Activity` answers: what actions happened?

If a document cannot answer which of those questions it is talking about, its wording is too vague.

## Final Model

Use this four-part mental model:

1. `memory`
   - structured durable knowledge
2. `notes_for_ai`
   - human-owned memory section
   - human working note surface
4. `ai_changelog` / `AI Activity`
   - audit/history stream

## Final Decision

The memory/notes vocabulary should be treated as:

- `memory` = durable structured knowledge
- `notes_for_ai` = reserved human-owned memory key
- `AI Activity` = user-facing label for `ai_changelog`
- user-facing copy and internal/runtime naming should intentionally diverge only for `AI Activity` vs `ai_changelog`, not for the other concepts
