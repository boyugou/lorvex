# Apple Finalization Audit Coverage Map

Last updated: 2026-07-17

This map answers a narrower question than the findings backlog: which Apple
release areas have enough written audit evidence, which have only partial
coverage, and which still deserve a dedicated source audit. “Covered” does not
mean every finding is fixed; it means the area has been inspected deeply enough
to make the remaining work visible.

## Coverage at a Glance

| Area | Coverage | Evidence / remaining boundary |
| --- | --- | --- |
| SQLite schema, migrations, sync payloads, CloudKit convergence | Deep, re-audited through the finalization checkpoint | `docs/design/SCHEMA_OPTIMALITY.md`, sync design docs, CloudKit reference notes, and the finalization archive; code-side schema/sync blockers are closed, while account/device release evidence remains separate |
| CloudKit production schema, encryption, account changes, throttling, backup | Deep | Individual Apple-source notes in this directory; account-side production validation remains owner work |
| App Store packaging, signing, entitlements, provisioning, notarization | Deep at source/config level | Provisioning, App Group, notarization, privacy, and distribution notes; exact signed archives still require release evidence |
| Deployment targets, Apple silicon policy, Xcode/SDK requirements | Deep | `DEPLOYMENT_TARGET_DECISION.md`, `APPLE_SILICON_MACOS_26.md`, upcoming requirements |
| Deprecated APIs and 2025–2026 platform evolution | Deep source scan, must be repeated per SDK | `APPLE_API_DEPRECATION_AUDIT.md`, macOS 26, Swift 6.2, App Intents, Foundation Models, AlarmKit |
| App Intents authentication, confirmation, execution modes | Deep contract audit; implementation is currently changing | Three dedicated App Intent notes and finalization backlog |
| Localization architecture and current catalog quality | Deep static audit | `APPLE_LOCALIZATION_ARCHITECTURE_AUDIT.md`; runtime screenshots/pseudolanguages and professional translation QA remain |
| Privacy manifests, App Privacy answers, diagnostics, analytics | Deep source audit | Privacy, MetricKit, crash reports, analytics notes; final archive privacy report remains required |
| Widgets/complications sensitive content | Focused privacy audit | `WIDGET_SENSITIVE_CONTENT.md`; broader freshness, timeline, and interaction reliability remain partial |
| EventKit disclosure and authorization | Focused | `EVENTKIT_CALENDAR_SOURCES.md` and deprecation scan; destructive edit semantics and provider failure recovery still merit a dedicated audit |
| Local notifications and task/habit reminders | Deep static audit as of this pass | `APPLE_NOTIFICATION_REMINDER_AUDIT.md`; physical-device delivery matrix remains required |
| Local preference registry | Deep static audit | `LOCAL_PREFERENCE_REGISTRY_AUDIT.md`; several accepted/synced keys remain no-op contract debt |
| Background CloudKit pushes | Deep | `BACKGROUND_PUSH_UPDATES.md`; reminder-window refill is a separate uncovered need, now recorded in the notification audit |
| Accessibility | Deep static audit; runtime proof absent | `APPLE_ACCESSIBILITY_MATRIX_AUDIT.md`; gesture parity, Reduced Motion, hit regions, adaptive layout, visual semantics, focus restoration, and App Store declaration gates are inventoried, but the physical-device matrix has not run |
| Deep links, notification taps, `NSUserActivity`, Spotlight/Handoff routing | Deep static audit | `APPLE_EXTERNAL_ENTRYPOINT_ROUTING_AUDIT.md`; device/scene/cross-account evidence and file/App Intent boundaries remain separate |
| Managed App-Group storage authority (no external-DB selection) | Deep static audit | `APPLE_DATABASE_BOOKMARK_MCP_TRUST_AUDIT.md` (historical — audits the removed external-DB/bookmark machinery); storage is now the single managed App-Group database resolved by `DbLocator`, pinned by `ManagedStorageInvariantTests` |
| MCP helper / App Group IPC security boundary | Deep static audit | `APPLE_DATABASE_BOOKMARK_MCP_TRUST_AUDIT.md`; caller authentication is still an unresolved release decision |
| Import/export and archive safety | Deep static audit | `APPLE_IMPORT_EXPORT_ARCHIVE_SAFETY_AUDIT.md` plus its current-status header; version-1 inventory/resource bounds, fail-closed classic-ZIP writing, honest preview semantics, transactional units, and the terminal live-import boundary are implemented. Remaining evidence is physical-device stress/termination behavior; ZIP64 is deliberately unsupported |
| App lifecycle, scene restoration, multi-window state | Deep static audit; runtime proof absent | `APPLE_LIFECYCLE_RESTORATION_TIME_AUDIT.md`; cached time-zone/day rollover, database cutover, draft durability, iPad scene ownership, observer lifetime, restoration, and memory-pressure gates are inventoried |
| Accessibility-aware visual behavior | Deep static audit; runtime proof absent | `APPLE_ACCESSIBILITY_MATRIX_AUDIT.md`; contrast, transparency, motion, keyboard/focus order, and largest text sizes now have a source assessment and required release matrix |
| Energy, memory, launch time, hangs, background budget | Deep static audit; runtime proof absent | `APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md`; local-first ordering, refresh amplification, deadline ownership, MetricKit gaps, deprecation, benchmark limits, and exact-artifact gates are inventoried, but signed-device budgets/traces have not run |
| App Store metadata, screenshots, age rating, support/privacy URLs by locale | Partial | Requirements and support URL are researched; final per-locale metadata and screenshot set are not audited as one artifact |
| StoreKit / purchases | Not applicable unless monetization is added | No current purchase/subscription product contract was identified |

## Highest-Value Next Audits

### 1. Accessibility runtime evidence

The static matrix is now in `APPLE_ACCESSIBILITY_MATRIX_AUDIT.md`. The remaining
work cannot be completed from source: run VoiceOver reading/action order,
keyboard and Full Keyboard Access, Dynamic Type at maximum sizes, Increase
Contrast, Differentiate Without Color, Reduce Motion, Reduce Transparency,
Voice Control, Switch Control, focus restoration, charts/calendar grids,
widgets, Watch, and every destructive confirmation on the exact Release build.

Deliverable: saved Accessibility Inspector/automated audit output plus the
physical-device common-task evidence required before publishing App Store
accessibility nutrition labels.

### 2. Remaining external input and continuation boundary

The navigation half now has a dedicated audit. Continue with paths that convert
outside data into mutation or file/database authority:

- App Intent entity IDs and string parameters;
- imported archives/ICS files and security-scoped URLs.

Check malformed encodings, oversized input, stale/deleted IDs, wrong database or
iCloud account, duplicate delivery, replay, locked-device entry, and whether a
read-only continuation can accidentally reach a mutation. Reuse the routing
ownership table from `APPLE_EXTERNAL_ENTRYPOINT_ROUTING_AUDIT.md` rather than
creating a parallel URL parser inventory.

### 3. Lifecycle, restoration, and multi-window runtime evidence

The source contract and gaps are now documented in
`APPLE_LIFECYCLE_RESTORATION_TIME_AUDIT.md`. Run cold launch, warm launch,
reopen after last window closes, force quit during a write/sync/import, scene
activation storms, duplicate detached windows, database replacement while
windows are open, unsaved drafts during remote sync, memory pressure,
date/timezone rollover, and midnight while the app remains open. Include iPad
multi-window only if the currently absent multiple-scenes capability is enabled.

The existing multi-store coherence document remains a strong invariant; the
static audit identifies a database-cutover path that does not yet satisfy it.

### 4. Signed-build performance and energy

The source and release-evidence boundary is now audited in
`APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md`. The remaining work is to
separate local-first loading and domain-gated refresh, then define approved
budgets for cold/warm launch, first usable screen, SQLite open/migration,
refresh, sync apply, Spotlight rebuild, widget snapshot, memory while several
windows are open, and background push completion. Measure exact Release
archives on the oldest supported iPhone and a baseline Apple-silicon Mac. Use
current `OSSignposter` intervals so Organizer, MetricKit, XCTest, and Instruments
evidence maps back to stable product operations.

### 5. Final App Store artifact and metadata audit

Treat the uploaded archives and App Store Connect record as the subject:

- bundle IDs, versions, architectures, minimum OS, embedded extensions;
- signed entitlements and provisioning profile authorization;
- privacy report versus App Privacy answers;
- encryption declaration, age rating, categories, support/privacy URLs;
- localized name, subtitle, description, keywords, release notes, screenshots,
  and permission explanations;
- install/upgrade/reinstall/restore/TestFlight checks with production CloudKit.

Source-tree verification is necessary but cannot substitute for this pass.

## Suggested Order

1. Stabilize and re-run the schema/sync and App Intent audits after the active
   edit agent finishes.
2. Resolve notification semantics that affect data-contract freeze.
3. Resolve the newly documented file/helper authorization and archive/import
   contract decisions, then run their hostile-input and cutover matrices.
4. Run accessibility and lifecycle/device matrices.
5. Measure signed-build performance.
6. Finish with the exact archive plus App Store Connect metadata review.

This ordering puts irreversible data/sync meanings first, then security and user
data access, then broad product quality, and finally release artifacts that can
only be validated once the implementation is stable.
