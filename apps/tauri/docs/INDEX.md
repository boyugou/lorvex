# Lorvex Documentation

*Reading guide and doc map*

---

## Start Here

| Doc | Purpose |
|-----|---------|
| [ROADMAP.md](../ROADMAP.md) | **Current status, active workstreams, and what to work on next.** Read this first. |
| [CLAUDE.md](../CLAUDE.md) | Agent instructions, coding standards, project development norms. |

---

## How to Read These Docs

**New to the project?** Vision → Design Philosophy → Architecture → Features.

**Building?** ROADMAP (status) → Architecture → Platform Capability Matrix → Data Model → the relevant design doc.

**Evaluating the product?** Pitch (EN) → Vision → Competitive Landscape.

---

## vision/ — Strategy (stable, low-frequency updates)

The "north star" documents. Read these to understand what Lorvex is, why it exists, and how AI-native automation and the app's own product experience fit together.

| Doc | What It Covers |
|-----|----------------|
| [VISION.md](vision/VISION.md) | Product vision, Lorvex's product category, and what makes its AI-native approach distinct |
| [DESIGN_PHILOSOPHY.md](vision/DESIGN_PHILOSOPHY.md) | Core paradigm, AI-native product principles, and how automation complements a strong standalone app |
| [PITCH_EN.md](vision/PITCH_EN.md) | Product pitch (English) — positioning, tagline, narrative |
| [COMPETITIVE_LANDSCAPE.md](vision/COMPETITIVE_LANDSCAPE.md) | The product-category map and the design lessons Lorvex draws from each category |

---

## design/ — Technical Design (update when architecture changes)

Technical design documents describing the system architecture, data model, UX patterns, and the runtime/sync strategy that supports the product experience.

| Doc | What It Covers |
|-----|----------------|
| [ARCHITECTURE.md](design/ARCHITECTURE.md) | System architecture, peer runtime model, MCP/operator surfaces, and data flow |
| [DATA_MODEL.md](design/DATA_MODEL.md) | SQLite schema, table definitions, relationships, migration strategy |
| [FEATURES.md](design/FEATURES.md) | Feature tiers with `[STATUS]` tags — see which features are shipped, partial, or planned |
| [CALENDAR_BEHAVIOR.md](design/CALENDAR_BEHAVIOR.md) | Calendar ownership and interaction rules for canonical events versus external provider mirrors |
| [PLATFORM_CAPABILITY_MATRIX.md](design/PLATFORM_CAPABILITY_MATRIX.md) | Per-platform capability surface — what runs where, what's gated by feature flags, what's stubbed |
| [MULTI_SURFACE_ARCHITECTURE.md](design/MULTI_SURFACE_ARCHITECTURE.md) | Multi-surface (Tauri / MCP / CLI) architecture and the operating-model split between them |
| [UX.md](design/UX.md) | UI design system, component patterns, interaction flows, visual language |
| [UX_PATTERNS.md](design/UX_PATTERNS.md) | Cross-surface UX pattern catalog (toasts, sheets, picker overlays) |
| [DESIGN_TOKENS.md](design/DESIGN_TOKENS.md) | Canonical reference for every CSS custom property + `@utility` block — colors, surfaces, accent-tint ladder, focus rings, easing, animations, glass profiles |
| [PER_VIEW_CONTENT_STRATEGY.md](design/PER_VIEW_CONTENT_STRATEGY.md) | Per-view content strategy — what each task list view emphasizes and the empty-state copy |
| [COMMAND_PALETTE.md](design/COMMAND_PALETTE.md) | Command palette spec — search modes, command set, fuzzy matching |
| [CLAUDE_OPERATING_MODEL.md](design/CLAUDE_OPERATING_MODEL.md) | How AI assistant should behave as the AI operator — MCP tool usage patterns, planning heuristics |
| [MCP_TOOLS.md](design/MCP_TOOLS.md) | Complete MCP tool reference — semantics and usage patterns (mutable counts live in generated `reference/REPO_FACTS.md`) |
| [TIMEZONE_SEMANTICS.md](design/TIMEZONE_SEMANTICS.md) | Canonical timezone model for tasks vs events and local-day boundary rules for MCP "today" operations |
| [COPY_GUIDELINES.md](design/COPY_GUIDELINES.md) | Canonical product wording, locale terminology glossary, and copy checklist |
| [naming/INDEX.md](design/naming/INDEX.md) | Canonical naming system across product copy, MCP/CLI surfaces, schema entities, and runtime terminology |
| [SECURITY_MESSAGING.md](design/SECURITY_MESSAGING.md) | Canonical security/trust claims, terminology, and reusable copy templates |
| [SYNC_APPLY_SEMANTICS.md](design/SYNC_APPLY_SEMANTICS.md) | Sync apply pipeline contract — wire envelope, apply dispatch, LWW rules, FK retry, tombstone redirect, conflict log, idempotency cache |
| [MACOS_MENU_BAR.md](design/MACOS_MENU_BAR.md) | macOS menu bar popover design spec |
| [DISTRIBUTION.md](design/DISTRIBUTION.md) | Signed-build distribution flow — Apple notarization, Windows Authenticode, CI signing-secret pipeline |

---

## execution/ — Delivery Governance

Operational docs for keeping planning and implementation in sync.

| Doc | What It Covers |
|-----|----------------|
| [CI_RELEASE_TRIGGER_POLICY.md](execution/CI_RELEASE_TRIGGER_POLICY.md) | Canonical trigger policy for PR CI, main-push verification, and tag-gated release workflows |
| [ISSUE_LIFECYCLE.md](execution/ISSUE_LIFECYCLE.md) | Canonical issue-state transitions, evidence requirements, and closeout rules |
| [MODULE_CONTRACT_MATRIX.md](execution/MODULE_CONTRACT_MATRIX.md) | Durable sidebar/module contract matrix with static validation path |
| [SYNC_RECOVERY_PLAYBOOK.md](execution/SYNC_RECOVERY_PLAYBOOK.md) | Step-by-step sync failure triage and recovery workflow |
| [MCP_E2E_VALIDATION.md](execution/MCP_E2E_VALIDATION.md) | Canonical assistant workflow scripts, MCP error taxonomy, and release gate checklist |
| [SCALE_RESILIENCE_CHECKLIST.md](execution/SCALE_RESILIENCE_CHECKLIST.md) | Reproducible 1k/10k dataset seeding + MCP context-budget and UI smoke validation checklist |
| [MENUBAR_REGRESSION_CHECKLIST.md](execution/MENUBAR_REGRESSION_CHECKLIST.md) | Menu bar icon/popover interaction regression checks for release gating |
| [SETTINGS_REGRESSION_CHECKLIST.md](execution/SETTINGS_REGRESSION_CHECKLIST.md) | Settings interaction reliability and auto-save regression checklist |
| [THEME_QA_CHECKLIST.md](execution/THEME_QA_CHECKLIST.md) | Theme release-gate checklist covering contrast, desktop chrome, overlays, switching regressions, and bounded-surface experiments |
| [TEST_FLAKINESS.md](execution/TEST_FLAKINESS.md) | Test-flakiness governance — how to triage, mark, and retire flaky tests |

---

## Other Docs

| Doc | What It Covers |
|-----|----------------|
| [../README.md](../README.md) | Top-level product overview, quick start, and install-path chooser |
| [setup/GETTING_STARTED.md](setup/GETTING_STARTED.md) | Fast install + first-run path for installed app users and source-checkout users |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Contributor setup, verification commands, and development workflow norms |
| [CLAUDE_PROMPT.md](CLAUDE_PROMPT.md) | Prompt card for users to paste into an MCP-capable AI assistant client |
| [setup/ASSISTANT_MCP_SETUP.md](setup/ASSISTANT_MCP_SETUP.md) | MCP client setup for Claude Desktop, Claude Code, and Codex |
| [reference/REPO_FACTS.md](reference/REPO_FACTS.md) | Generated mutable repo facts (MCP tool counts, per-tool-file breakdown, migration inventory, IPC and locale totals) |
| [setup/FIRST_RUN_OFFLINE.md](setup/FIRST_RUN_OFFLINE.md) | First-run UX when the device is offline — local-only mode, deferred sync setup |
| [reference/PLATFORM_THEME_DESIGN.md](reference/PLATFORM_THEME_DESIGN.md) | Platform theme design reference (light/dark, accent palette, contrast tokens) |
| [archive/README.md](archive/README.md) | Historical archive entrypoint. Not part of the current implementation contract. |

---

## Archive

Historical reasoning and milestone-era proposals live behind a single entrypoint:

- [archive/README.md](archive/README.md)

Archived materials are not current implementation contract and are not part of the primary reading path.

<!--
  The curated reading map above (Start Here, vision/, design/,
  execution/, Other Docs, Archive) is hand-edited. The block below
  between DOC_INVENTORY:START and DOC_INVENTORY:END is generated by
  `scripts/generate/docs_index.mjs` and rewritten in place every
  `npm run docs:index` / `npm run verify:docs-index`.

  The generator's `replaceBlock()` (in scripts/generate/docs_index.mjs)
  splices ONLY between the two HTML comment markers — it preserves the
  prefix (curated map) and suffix verbatim. Do not delete or move these
  markers, and never edit content between them by hand.
-->

<!-- DOC_INVENTORY:START -->
## Auto-Generated Inventory

This section is generated by `scripts/generate/docs_index.mjs`. Do not edit manually.

### (root)

| File | Title |
|---|---|
| [CLAUDE_PROMPT.md](CLAUDE_PROMPT.md) | Assistant Prompt for Lorvex |
| [INDEX.md](INDEX.md) | Lorvex Documentation |

### vision/

| File | Title |
|---|---|
| [vision/COMPETITIVE_LANDSCAPE.md](vision/COMPETITIVE_LANDSCAPE.md) | Product Category Landscape |
| [vision/DESIGN_PHILOSOPHY.md](vision/DESIGN_PHILOSOPHY.md) | Design Philosophy |
| [vision/PITCH_EN.md](vision/PITCH_EN.md) | Product Pitch (English) |
| [vision/VISION.md](vision/VISION.md) | Product Vision |

### design/

| File | Title |
|---|---|
| [design/ARCHITECTURE.md](design/ARCHITECTURE.md) | Architecture |
| [design/CALENDAR_BEHAVIOR.md](design/CALENDAR_BEHAVIOR.md) | Calendar Behavior |
| [design/CLAUDE_OPERATING_MODEL.md](design/CLAUDE_OPERATING_MODEL.md) | AI Assistant Operating Model |
| [design/COMMAND_PALETTE.md](design/COMMAND_PALETTE.md) | Command Palette & Search (⌘K) |
| [design/COPY_GUIDELINES.md](design/COPY_GUIDELINES.md) | Copy Guidelines |
| [design/DATA_MODEL.md](design/DATA_MODEL.md) | Data Model |
| [design/DESIGN_TOKENS.md](design/DESIGN_TOKENS.md) | Design Tokens |
| [design/DISTRIBUTION.md](design/DISTRIBUTION.md) | Distribution Guide |
| [design/FEATURES.md](design/FEATURES.md) | Features |
| [design/MACOS_MENU_BAR.md](design/MACOS_MENU_BAR.md) | macOS App Menu Bar — Design Spec |
| [design/MCP_TOOLS.md](design/MCP_TOOLS.md) | MCP Tools Reference |
| [design/MULTI_SURFACE_ARCHITECTURE.md](design/MULTI_SURFACE_ARCHITECTURE.md) | Multi-Surface Architecture |
| [design/naming/AI_SURFACES.md](design/naming/AI_SURFACES.md) | AI Surfaces Naming |
| [design/naming/CALENDAR_TIME.md](design/naming/CALENDAR_TIME.md) | Calendar and Time Naming |
| [design/naming/FOUNDATIONS.md](design/naming/FOUNDATIONS.md) | Naming Foundations |
| [design/naming/INDEX.md](design/naming/INDEX.md) | Naming System Index |
| [design/naming/MEMORY_NOTES.md](design/naming/MEMORY_NOTES.md) | Memory and Notes Naming |
| [design/naming/PLANNING.md](design/naming/PLANNING.md) | Planning Naming |
| [design/naming/SYNC_RUNTIME.md](design/naming/SYNC_RUNTIME.md) | Sync and Runtime Naming |
| [design/naming/TASK_SYSTEM.md](design/naming/TASK_SYSTEM.md) | Task System Naming |
| [design/PER_VIEW_CONTENT_STRATEGY.md](design/PER_VIEW_CONTENT_STRATEGY.md) | Per-View Content Strategy |
| [design/PLATFORM_CAPABILITY_MATRIX.md](design/PLATFORM_CAPABILITY_MATRIX.md) | Platform Capability Matrix |
| [design/SECURITY_MESSAGING.md](design/SECURITY_MESSAGING.md) | Security Messaging Guide |
| [design/SYNC_APPLY_SEMANTICS.md](design/SYNC_APPLY_SEMANTICS.md) | Sync Apply Semantics |
| [design/TIMEZONE_SEMANTICS.md](design/TIMEZONE_SEMANTICS.md) | Timezone Semantics |
| [design/UX_PATTERNS.md](design/UX_PATTERNS.md) | UX Patterns — Uniform Edit Hierarchy |
| [design/UX.md](design/UX.md) | UX Design |

### execution/

| File | Title |
|---|---|
| [execution/CI_RELEASE_TRIGGER_POLICY.md](execution/CI_RELEASE_TRIGGER_POLICY.md) | CI and Release Trigger Policy |
| [execution/ISSUE_LIFECYCLE.md](execution/ISSUE_LIFECYCLE.md) | GitHub Issue Lifecycle Standard |
| [execution/MCP_E2E_VALIDATION.md](execution/MCP_E2E_VALIDATION.md) | MCP End-to-End Validation (Assistant Workflows) |
| [execution/MENUBAR_REGRESSION_CHECKLIST.md](execution/MENUBAR_REGRESSION_CHECKLIST.md) | Menu Bar Regression Checklist |
| [execution/MODULE_CONTRACT_MATRIX.md](execution/MODULE_CONTRACT_MATRIX.md) | Module Contract Matrix |
| [execution/SCALE_RESILIENCE_CHECKLIST.md](execution/SCALE_RESILIENCE_CHECKLIST.md) | Scale Resilience Checklist (1k / 10k Tasks) |
| [execution/SETTINGS_REGRESSION_CHECKLIST.md](execution/SETTINGS_REGRESSION_CHECKLIST.md) | Settings Regression Checklist |
| [execution/SYNC_RECOVERY_PLAYBOOK.md](execution/SYNC_RECOVERY_PLAYBOOK.md) | Sync Recovery Playbook |
| [execution/templates/evidence_note.md](execution/templates/evidence_note.md) | Evidence Note Template |
| [execution/TEST_FLAKINESS.md](execution/TEST_FLAKINESS.md) | Test-Flakiness Playbook |
| [execution/THEME_QA_CHECKLIST.md](execution/THEME_QA_CHECKLIST.md) | Theme QA Checklist |

### reference/

| File | Title |
|---|---|
| [reference/PLATFORM_THEME_DESIGN.md](reference/PLATFORM_THEME_DESIGN.md) | Platform Theme Design Reference |
| [reference/REPO_FACTS.md](reference/REPO_FACTS.md) | Repository Facts (Generated) |

### setup/

| File | Title |
|---|---|
| [setup/ASSISTANT_MCP_SETUP.md](setup/ASSISTANT_MCP_SETUP.md) | Connecting Your AI Assistant to Lorvex |
| [setup/DEEP_LINK_URL_SCHEME.md](setup/DEEP_LINK_URL_SCHEME.md) | Lorvex Deep Link URL Scheme |
| [setup/FIRST_RUN_OFFLINE.md](setup/FIRST_RUN_OFFLINE.md) | First Run Without Network |
| [setup/GETTING_STARTED.md](setup/GETTING_STARTED.md) | Getting Started with Lorvex |
<!-- DOC_INVENTORY:END -->
