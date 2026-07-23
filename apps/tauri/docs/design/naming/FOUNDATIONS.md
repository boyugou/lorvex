# Naming Foundations

## Purpose

This document defines how Lorvex names concepts across product copy, MCP tools,
CLI commands, schema entities, sync payloads, and runtime state.

The current codebase already has a strong canonical registry in
`lorvex-domain/src/naming/` and `lorvex-domain/src/preference_keys/`, but
the user-facing and operator-facing layers are not fully converged. The result
is local correctness with occasional vocabulary drift.

This document sets the naming system that all future docs and code should follow.

## Current State

Observed in code and docs:

- Canonical entity names are centralized in `lorvex-domain/src/naming/`.
- Canonical preference/device-state keys are centralized in
  `lorvex-domain/src/preference_keys/`.
- User-facing copy already has a separate glossary in
  `docs/design/COPY_GUIDELINES.md`.
- Older architectural docs still contain a mix of:
  - schema nouns
  - product nouns
  - action/tool phrases
  - compatibility language

The main issue is not a lack of names. The issue is that different layers are
sometimes treated as if they should share the same wording.

## Naming Layers

Lorvex should explicitly operate with four naming layers.

### 1. Product Language

Used in:

- UI labels
- onboarding/setup copy
- help docs
- app store materials

Goal:

- human-readable
- short
- low-cognitive-load

Examples:

- `Today's Focus`
- `AI Activity`
- `Quick Capture`

### 2. Operator Language

Used in:

- MCP tools
- CLI commands
- diagnostics
- runtime status
- setup / doctor output

Goal:

- precise
- stable
- machine-friendly

Examples:

- `current_focus`
- `focus_schedule`
- `mcp_host_authority`
- `local_change_seq`

### 3. Canonical Domain Language

Used in:

- schema
- sync entity names
- export/import payloads
- shared domain/runtime code

Goal:

- stable over time
- unambiguous
- implementation-safe

Examples:

- `task`
- `daily_review`
- `focus_schedule`
- `ai_changelog`

### 4. Legacy / Compatibility Language

Used only where needed for compatibility:

- historical tool names
- migration docs
- transitional setup docs

Goal:

- preserve compatibility
- do not define new truth

Examples:

- `propose_daily_schedule` as a legacy action phrase
- older references to `lorvex-mcp-server`

## Rules

### Rule 1: One canonical concept, one canonical domain name

A concept may have UI aliases, but only one canonical domain name.

Good:

- canonical entity: `current_focus`
- UI label: `Today's Focus`

Bad:

- canonical names competing with each other:
  - `current_focus`
  - `today_focus`
  - `daily_plan`

### Rule 2: Umbrella terms are not entities

Names like:

- `Today Plan`
- `Day Plan`
- `Review`

may exist as product umbrella terms without requiring a matching table/entity.

Do not create schema entities just to mirror a documentation phrase.

### Rule 3: UI wording may humanize, but may not change semantics

UI wording can be friendlier than internal wording, but it must preserve the concept boundary.

Allowed:

- `AI Activity` for `ai_changelog`
- `Today's Focus` for `current_focus`

Not allowed:

- using `schedule` to describe the task pool
- calling `notes_for_ai` the same thing as `memory`

### Rule 4: Schema/runtime names are optimized for stability, not prettiness

Canonical entity names should not be renamed lightly just because the UI wants a nicer phrase.

This especially applies to:

- sync entity names
- natural-key tables
- MCP/tool nouns
- preference keys

### Rule 5: Host, surface, owner, and authority are distinct words

These terms must never be used interchangeably.

- `host`
  - runtime container providing a capability
- `surface`
  - operator-facing interaction mode
- `owner`
  - runtime process currently responsible for a background loop or lease
- `authority`
  - canonical external registration choice

Examples:

- App can be a host.
- MCP can be a surface.
- Sync transport can have an owner.
- external MCP can have an authority.

### Rule 6: Relative words require an anchor

Words like:

- `current`
- `today`
- `active`
- `default`

must have a defined anchor.

Examples:

- `current_focus` is anchored to a date.
- `active MCP host` is anchored to external agent registration.
- `today_pool` is anchored to canonical day-boundary logic.

## Anti-Patterns

Avoid these across code and docs:

- using one word for both a pool and a commitment
- using one word for both a product surface and a host runtime
- introducing a product phrase as a new schema name
- treating compatibility tool names as canonical architecture
- renaming synced entities for copy reasons
- letting docs use broader terms than the code actually implements

## Naming Decision Process

When introducing or revising a term:

1. Determine its layer:
   - Product
   - Operator
   - Canonical
   - Legacy
2. Determine whether it names:
   - entity
   - collection
   - projection
   - host
   - surface
   - lease/authority/runtime state
3. Check whether an equivalent canonical term already exists.
4. Prefer aliasing at the UI/copy layer over renaming the canonical layer.

## Registry Sources

Current source-of-truth registries already present in code:

- `lorvex-domain/src/naming/`
- `lorvex-domain/src/preference_keys/`
- `docs/design/COPY_GUIDELINES.md`

These naming docs do not replace the code registries. They explain how to use them consistently.

## Current Gaps

The main naming gaps still visible in the repo are:

- planning words are mostly correct in code, but not fully normalized in product copy
- App-hosted and CLI-hosted MCP language still coexists in setup/runtime docs
- some docs use legacy action phrases as if they were domain concepts
- review/memory language still overlaps in informal discussion

## Migration Guidance

Default migration order:

1. update naming docs
2. update user-facing copy
3. update MCP descriptions and setup docs
4. only then consider API aliases
5. avoid schema renames unless absolutely necessary
