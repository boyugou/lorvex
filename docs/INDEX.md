# Documentation index

Project-level (monorepo-wide) docs live here. App-specific docs live under each
app.

## Monorepo-level

- [`../README.md`](../README.md) — what the monorepo is.
- [`../CLAUDE.md`](../CLAUDE.md) — operating manual for agents.
- [`../ROADMAP.md`](../ROADMAP.md) — status by lane (Apple / Shared) and open work.
- [`development/NEW_MACHINE.md`](development/NEW_MACHINE.md) — setting up a development machine, the local files a clone lacks, privacy rules, and releasing.
- [Build 169 release record](releases/1.0.0-169.md) — find a phrase across dated journal entries on Mac.
- [Build 168 release record](releases/1.0.0-168.md) — resume a started task at its remaining checklist on iPhone and iPad.
- [Build 167 release record](releases/1.0.0-167.md) — start a timed task and return to its next checklist item around a meeting on mobile Today.
- [Build 166 release record](releases/1.0.0-166.md) — compare today’s and tomorrow’s remaining time before moving tasks.
- [Build 165 release record](releases/1.0.0-165.md) — plan a subset of unfinished tasks against tomorrow’s agenda on iPhone and iPad.
- [Build 164 release record](releases/1.0.0-164.md) — choose unfinished tasks against tomorrow’s working hours and existing plans on Mac.
- [Build 163 release record](releases/1.0.0-163.md) — recent mobile journal entries, independent field saves and the direct Mac download.
- [Build 162 release record](releases/1.0.0-162.md) — open the current or next appointment from mobile Today.
- [Build 161 release record](releases/1.0.0-161.md) — choose an existing task for an empty mobile Today.
- [Build 160 release record](releases/1.0.0-160.md) — write and autosave a daily note on iPhone and iPad.
- [Build 159 release record](releases/1.0.0-159.md) — mobile daily check-in, VoiceOver, and overlapping saves.
- [Build 158 release record](releases/1.0.0-158.md) — Daily Review agenda order, Mac workspace navigation and download.
- [Build 157 release record](releases/1.0.0-157.md) — scheduling an Inbox task, iPad split layout and Mac download.
- [Build 156 release record](releases/1.0.0-156.md) — mobile capture results, VoiceOver navigation and TestFlight availability.
- [Build 155 release record](releases/1.0.0-155.md) — original titles in quick capture, Mac download and TestFlight availability.
- [Build 154 release record](releases/1.0.0-154.md) — readable week agenda, calendar navigation and TestFlight availability.
- [Build 153 release record](releases/1.0.0-153.md) — adaptive Today, Mac download and TestFlight availability.
- [Build 152 release record](releases/1.0.0-152.md) — first task, existing-plan setup and TestFlight availability.
- [Build 151 release record](releases/1.0.0-151.md) — reading past journal entries and TestFlight availability.
- [Build 150 release record](releases/1.0.0-150.md) — Mac download, TestFlight availability, checksum, and validation.

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
- [`design/SYNC_APPLY_SEMANTICS.md`](design/SYNC_APPLY_SEMANTICS.md) — Sync apply pipeline, HLC conflict resolution, LWW rules, idempotency, and why ai_changelog stays device-local.
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
- [`../apps/apple/docs/development/ENGINEERING_TRAPS.md`](../apps/apple/docs/development/ENGINEERING_TRAPS.md) — platform traps and data-flow facts, each with its rule.
- [`../apps/apple/docs/development/VERIFICATION.md`](../apps/apple/docs/development/VERIFICATION.md) — test quirks, probe suites, oracles, and headless capture recipes.
- [`../apps/apple/docs/release.md`](../apps/apple/docs/release.md) — schema freeze, TestFlight, Mac App Store, and DMG releases.
