# CLAUDE.md — Lorvex Apple

This app lives at `apps/apple` inside the Lorvex monorepo; start from the root
`CLAUDE.md`. The Apple-native implementation is the canonical product surface
for app behavior, workflow rules, sync semantics, and MCP tool contracts.

This is the Apple-native Lorvex app: SwiftUI/AppKit/SwiftPM, targeting macOS,
iOS, iPadOS, visionOS, watchOS, and CarPlay, plus WidgetKit, App Intents,
Shortcuts, Spotlight, CloudKit, and EventKit surfaces. The shared SQLite schema
(Apple-owned authority) and the `spec/` behavior contracts remain the cross-app
reference; the Tauri tree is no longer the behavioral oracle for Apple work, and
cross-platform data movement is AI-reconciled best-effort, not a formal
interchange format.
This repo does not try to preserve the Tauri/React UI; Apple surfaces should
feel native to their platforms.

**License:** Apache-2.0

---

## Tech Stack

- **Language/UI:** Swift 6, SwiftUI, AppKit (macOS)
- **Build system:** SwiftPM (Package.swift, no Xcode project required for core
  dev; XcodeGen generates the Xcode project for simulator/device builds)
- **MCP host:** `LorvexMCPHost` executable using the official Swift SDK
  (`modelcontextprotocol/swift-sdk`)
- **Markdown:** `swiftlang/swift-markdown` — never hand-write a parser
- **Core:** `LorvexAppleCore` SwiftPM package (`core/`) — pure-Swift domain,
  SQLite storage (GRDB), workflow, and sync (`LorvexDomain`, `LorvexStore`,
  `LorvexWorkflow`, `LorvexSync`, `LorvexRuntime`). Surfaces talk to it through
  `LorvexCoreServicing`, backed by `SwiftLorvexCoreService`
- **No in-app AI runtime.** No Anthropic SDK. Lorvex is a task manager + MCP
  server; intelligence comes from external MCP-capable clients.

## Module Layout

```
Sources/
├── LorvexCore/             # Shared models, protocol, factory — platform-neutral
│   ├── Models/             # Domain types (LorvexTask, TodaySnapshot, …)
│   └── Services/           # LorvexCoreServicing protocol + SwiftLorvexCoreService
├── LorvexCloudSync/        # CloudKit sync engine (account status, push, checkpoints)
├── LorvexMarkdownUI/        # swift-markdown → SwiftUI rendering
├── LorvexApple/            # macOS app shell (SwiftUI + AppKit)
│   ├── App/                # Entry point, AppDelegate
│   ├── Stores/             # AppStore + extensions (one concern per file)
│   ├── Views/              # SwiftUI views (one workspace/component per file)
│   ├── Support/            # Commands, menus, routing, scheduling
│   └── Intents/            # App Intents
├── LorvexMobile/           # iOS/iPadOS/visionOS surface (reuses LorvexCore)
├── LorvexMobileApp/        # iOS @main entry
├── LorvexMCPHost/          # MCP stdio server (LorvexMCPHost executable)
│   ├── *ToolCatalog.swift  # Tool schema definitions
│   ├── *ToolHandlers.swift # Tool implementation
│   └── *ToolDefinitions.swift # Typed schema/handler/policy registry
├── LorvexVisionApp/        # visionOS @main entry
├── LorvexWatch/            # watchOS shared store + WatchConnectivity client
├── LorvexWatchApp/         # watchOS @main entry
├── LorvexWatchComplication/# watchOS complications (WidgetKit on watchOS)
├── LorvexCarPlay/          # CarPlay scene delegate + templates
├── LorvexSystemIntents/    # Shared App Intents (Shortcuts, Siri, Spotlight)
├── LorvexWidgetKitSupport/ # Shared widget snapshot/timeline infrastructure
├── LorvexWidgetViews/      # Reusable SwiftUI widget views
├── LorvexWidgetIntents/    # Interactive widget AppIntents (iOS 17+)
├── LorvexWidgetExtension/  # WidgetKit TimelineProvider + container
├── LorvexWidgetBundle/     # @main WidgetBundle entry
└── LorvexFocusWidget/      # Standalone focus widget

core/                       # LorvexAppleCore SwiftPM package (pure-Swift core)
                            #   LorvexDomain · LorvexStore (GRDB/SQLite) ·
                            #   LorvexWorkflow · LorvexSync · LorvexRuntime
```

`LorvexCore` depends on `core/` (path package). `SwiftLorvexCoreService` runs
the package against an on-disk GRDB store; previews and tests run the same
service over an in-memory GRDB store (`SwiftLorvexCoreService.inMemory()`,
seeded via `LorvexPreviewCoreFactory`), so there is no parallel fake
implementation to drift from production behavior.

Sync is multi-master: macOS and iOS each hold a full on-disk DB and sync
peer-to-peer via CloudKit (HLC clocks + last-writer-wins), so no single device is
authoritative. The watch is the exception — it has no DB and is a read-only
snapshot client of its paired iPhone, forwarding mutations via WatchConnectivity
(`LorvexWatchMutation`); the phone applies them and pushes a fresh snapshot (so
"the phone is the source of truth" holds for the watch only). CarPlay and widgets
read the App-Group-shared snapshot file written by the host app on the same
device.

---

## Core Design Rules

1. **AI-first.** The MCP host (`LorvexMCPHost`) is the primary write interface.
   The SwiftUI app is primarily a read surface with minimal human actions.
2. **Every MCP mutation must pass through the canonical `ai_changelog` funnel.**
   `SwiftLorvexCoreService`'s write surface writes the `ai_changelog` row inside
   each mutation's transaction (`ChangelogWrite` in `LorvexWorkflow`). The sole
   privacy exception is the user's explicit `off` retention policy, which stops
   recording and clears retained entries. Any new write path must still route
   through the canonical funnel; it may not invent an independent bypass.
3. **Canonical task sort key: `priority_effective ASC, due_date ASC NULLS LAST, id ASC`.**
   All task list queries must honour this key. Per-view deviations (e.g.
   date-first for the scheduled timeline view) are permitted only when documented
   in `../../docs/design/SORT_KEYS.md`.
4. **`ai_notes` is AI-only. Never human-editable in the UI.**
   The `aiNotesContent(task:)` view in `TaskDetailNotesSection.swift` renders
   read-only with a visual distinction (tinted background, italic rendering). No
   `TextField` for ai_notes anywhere in the UI. The MCP `set_task_ai_notes` tool is
   the only write path.
5. **Idempotency-key + checksum mismatch is always rejected.**
   Reusing an idempotency key with a different payload is an error, not a replay.
   The MCP host's process cache is an optimization; the authoritative guard is
   an atomic durable claim inside the same `BEGIN IMMEDIATE` transaction as the
   domain mutation, before its body runs. See
   `../../docs/design/SYNC_APPLY_SEMANTICS.md` for the full contract.
6. **SECURITY: Prompt-injection fencing on user-supplied strings in MCP responses.**
   `get_task`, `list_tasks`, `get_overview`, and any new read tool that returns
   user-controlled text must use a `ToolDefinition` response-fencing policy.
   The shared policy applies `SecurityFencing.fenceValue(_:)` to the structured
   response, wrapping user content in ⟦user⟧…⟦/user⟧ sentinels (U+27E6/U+27E7).
   Never fence system-controlled fields (IDs, enums, timestamps). Tests verifying
   fence application are required for any new user-content response field.
7. **Rich return values from MCP tools.** Every write operation returns the
   complete updated object(s). Never `{success: true}` equivalent.
8. **Apple platform quality.** Write UI like Apple wrote it: native light/dark,
   correct modal hierarchy, system font, system icons, correct focus rings,
   keyboard navigation, accessibility labels. No third-party UI libraries.
9. **No cross-platform compromises.** This repo is Apple-only. Never add
   Windows/Linux/Web/Tauri shims.
10. **One concern per file.** `AppStore` is split across `AppStore*.swift` by
    domain (actions, state, derived state). Follow this pattern everywhere —
    split by *concern*, when a file starts doing two things, not by line count.
    A 400-700 line single-concern file is entirely fine. `script/verify_hotspots.py`
    enforces an 800-line hard cap on the app's source targets (test files exempt);
    it is a god-file guardrail, not a fragmentation nudge — never split a cohesive
    file or trim explanatory comments just to satisfy it.
11. **`LorvexCoreServicing` is the write contract.** Every mutation goes through
    the protocol. UI never writes to SQLite directly.
12. **UI/UX quality over code minimalism — the bar is very high.** The final
    quality bar for every surface is exacting across *all* dimensions:
    interaction and gesture affordances, UX flow, page layout, visual elements,
    and the fine visual details. Invest extra views, extra modifiers, extra
    polish for better human experience. Code brevity is a virtue in backend
    logic; in UI, the virtue is how it looks and feels.
    - **Declutter ruthlessly.** Remove redundant or low-value affordances: no
      duplicate actions (e.g. a "capture" button when a global ＋ exists), no
      manual-refresh buttons (sync/pull-to-refresh handle it), no decorative
      chevrons on rows whose tappability is already obvious, no counts that
      merely restate the list below them. Every element must earn its place.
    - **Make affordances match expectations.** A leading circle on a task row is
      a checkbox — tapping it must complete the task. Don't show data the user
      can't act on, or actions that belong on another surface.
    - **Motion and feedback are part of the bar, not an afterthought.** State
      changes should animate (`withAnimation`, matched transitions, spring
      easing), completion/selection should give crisp feedback (haptics via the
      shared feedback provider, subtle scale/check animations), and nothing
      should pop in/out abruptly. Loading, empty, and error states get the same
      polish as the happy path.
    - **Always visually QA in the simulator** (`xcrun simctl io … screenshot`)
      before considering a UI change done; the screenshot is the proof. Review it
      **critically**, not to confirm success: is this design actually perfect?
      What are its obvious flaws, weak spots, or redundancies? Could it be better?
      Treat every screen as not-yet-good-enough until you've tried to break it.
13. **No email addresses.** All contact routes through the lorvex.app
    support/privacy pages. Never introduce email contact references anywhere.
14. **Commits are caller-controlled.** Do not commit or push unless the
    controlling session explicitly asks for it.
15. **The main app is the sole CloudSync owner on each device.** Only the
    macOS, iOS/iPadOS, or visionOS main app may construct or run
    `CloudSyncEngineCoordinator`. MCP, widgets, App Intents, watchOS, CarPlay,
    and other helpers read or mutate the managed local store through
    `LorvexCoreServicing`; canonical mutations atomically enqueue outbox work
    for the main app to upload later. Those targets must not depend on
    `LorvexCloudSync`, import CloudKit, pull/push records, delete zones, advance
    cursors, or switch generations. A future background sync daemon is an
    explicit architecture change that requires a new ownership design, not a
    topology to support speculatively.

---

## Coding Standards

### Swift

- Swift 6 strict concurrency. All types crossing actor boundaries must be
  `Sendable`. Prefer `actor` for mutable shared state.
- `@MainActor` on all `ObservableObject` stores and SwiftUI view models.
- Prefer `async/await` over completion handlers. No Combine unless extending an
  existing Combine surface.
- No `force unwrap` (`!`) except in `#Preview` and test fixtures.
- `guard let` / `if let` over optional chaining chains longer than two levels.
- Use `@Observable` (iOS 17 / macOS 14) for new view models; `ObservableObject`
  only when targeting older APIs.

### Naming

- Views: `<Domain>WorkspaceView`, `<Domain>DetailView`, `<Domain>Row`,
  `<Domain>Sheet`
- Store extensions: `AppStore<Domain>Actions`, `AppStore<Domain>DerivedState`
- MCP catalogs: `<Domain>ToolCatalog` (schema) + `<Domain>ToolHandlers`
  (implementation)
- Protocols: noun or adjective + `ing`/`able` (e.g., `LorvexCoreServicing`)
- **`LorvexMobile` `Mobile*` vs `MobileStore*`:** `MobileStore<X>` names types
  that take a `MobileStore` and drive mutations / observe its state (the
  store-bound surfaces and their action extensions —
  `MobileStore<Domain>View`, `MobileStore<Domain>Actions`). `Mobile<X>` names
  store-agnostic value types and presentational components that take plain
  data, not the store (`MobileTaskRow`, `MobileCalendarDraft`,
  `MobileHomeSnapshot`). When a view needs the live store, prefix it
  `MobileStore`.
- **Accessibility identifiers are dot-separated**, hierarchy first, each
  segment lowerCamelCase: `surface.region.element` (e.g.
  `tasks.header.scope`, `task.detail.inspector.close`, `today.row.batchSelect`).
  No kebab-case. The shared `InspectorCloseButton` uses the parallel
  `<surface>.inspector.close` across task / habit / calendar.

### Platform `#if` idioms

Use the narrowest condition that states the real constraint:

- `#if os(iOS)` — iPhone/iPad-only behavior (e.g. the WCSession snapshot
  publisher, which has no meaning on visionOS even though visionOS imports
  WatchConnectivity).
- `#if canImport(UIKit) && !os(visionOS)` — touch-only affordances that UIKit
  vends but Vision Pro lacks (haptics via `UIImpactFeedbackGenerator`).
- `#if os(iOS) || os(visionOS)` — surfaces that genuinely render on both
  (the shared mobile UI). Prefer this over a bare `canImport(UIKit)` so the
  intent (which platforms) is explicit.

### Comments

Default: no comments. Add one only when the WHY is non-obvious — a hidden
constraint, a subtle invariant, a platform quirk, a workaround for a specific
bug. Describe the current state, not the history. No "previously / originally /
was changed in phase N" narration.

Docstrings must be self-contained. A reader landing on a type via hover should
understand the contract from the docstring alone — not by reading the
implementation or fetching another file.

---

## Development Workflow

**止于至善 — Pursue perfection ceaselessly.**

### Principles

1. **Be fully autonomous.** Analyze, decide, execute. Only pause for truly
   irreversible high-risk decisions.
2. **Think deeply before building.** Trace through every use case before
   deciding.
3. **Quality over velocity.** Getting the foundation right matters more than
   shipping fast.
4. **Never take shortcuts.** Always pursue the most comprehensive, thorough,
   optimal solution. When fixing a bug, also clean up related dead code. When
   refactoring, go all the way.
5. **Self-review every implementation.** Two passes before finishing: (1)
   bugs/typos/correctness, (2) dead code/stale comments/unused imports.
6. **Search docs before implementing unfamiliar APIs.** Use `context7` MCP
   tool. Apple docs for SwiftUI/AppKit, swift-sdk docs for MCP.
7. **Eliminate redundancy.** Remove duplicate code paths, stale abstractions,
   dead code.

### Before Starting Work

1. Read recent git log: `git log --oneline -20`
2. Check the root `ROADMAP.md` for lane status and open items
3. Run `swift test` to confirm the app-suite baseline

### After Completing Work

1. Run `swift build` — all targets must build cleanly
2. Run `swift test` from `apps/apple` and `swift test` from
   `apps/apple/core` — both suites must pass. Tests use explicit injected
   fakes or temporary stores; product runtime environment variables must not
   select preview or in-memory storage.
3. Run `./script/verify_all.sh` for the full gate (builds, metadata, MCP
   smoke checks, entitlements, packaging)
4. Commit with a descriptive message

### Verification Commands

```bash
# Fast check during development
 swift build && swift test

# Core package check
(cd core && swift test)

# Full gate before committing substantial work
./script/verify_all.sh

# Build and run (macOS app)
./script/build_and_run.sh --verify

# MCP stdio smoke check
python3 script/mcp_stdio_smoke.py
```

### Subagent Dispatch

1. One bounded objective per subagent. Do not pin a model or reasoning setting
   in repository policy.
2. No opportunistic follow-on work inside a subagent — stop and return.
3. Controller (this session) owns acceptance review.

### Common Pitfalls

- **Swift 6 concurrency:** `@MainActor` isolation does not automatically apply
  to closure captures. Annotate explicitly or use `Task { @MainActor in … }`.
- **`@Observable` vs `ObservableObject`:** do not mix in the same view graph —
  pick one per feature tree.
- **WidgetKit:** Widget code must not import AppKit. `LorvexWidgetViews` and
  `LorvexWidgetKitSupport` must remain platform-neutral (macOS + iOS + visionOS).
- **MCP tool definitions:** New tools require one entry in the matching domain's
  `*ToolDefinitions.swift`. That typed entry binds the catalog schema, handler,
  read/write + idempotency metadata, and response-fencing policy; listing and
  dispatch are derived from it. Never add a parallel name switch or allowlist.
- **Core service calls are async throws.** Every `LorvexCoreServicing` call must
  be awaited and errors surfaced — never silently dropped.
- **Storage is always the managed App Group store.** There is no external-DB
  selection: every surface (app, MCP helper, widgets, App Intents, notifications)
  resolves the managed database via `DbLocator`. The only injection is the
  unsandboxed dev `LORVEX_APPLE_DB_PATH` env override, resolved directly by the
  core (never persisted or bookmarked). Portability is export/import.
  `ManagedStorageInvariantTests` pins this.
- **Settings import owns a CloudKit linearization boundary.** Shipping surfaces
  call `AppStore.applyDataImport` / `MobileStore.applyDataImport`, never
  `LorvexDataImporter.apply` directly. In live mode,
  `CloudSyncDataImportBoundary` must drain and prove the exact current
  account/generation plus all persistent pending/corrupt inbound debt while
  holding the same coordinator gate through import. Off/record-plan imports are
  deliberately local-only but still share the maintenance gate when available.
  Import is atomic per semantic unit, not across the whole archive.
- **App Group container:** Widget and app share a group container only when
  `LORVEX_WIDGET_APP_GROUP_ID` / `LorvexWidgetAppGroupID` is explicitly set.
  Default local builds use a no-op publisher to avoid repeated permission
  prompts.

### Continuous Review Loop

When all tasks seem done, cycle through: code reading, UX simplification,
dead code scan, type consistency, MCP tool completeness, accessibility,
documentation freshness, feature ideation.

---

## Key References

- **Shared contracts:** `../../schema/schema.sql`,
  `../../docs/design/SYNC_APPLY_SEMANTICS.md`, and current specs under
  `../../spec/`. Use Tauri as historical context only, not as the Apple
  behavioral oracle.
- **MCP Swift SDK:** https://github.com/modelcontextprotocol/swift-sdk
- **swift-markdown:** https://github.com/swiftlang/swift-markdown
- **Build/verify:** `script/verify_all.sh`, `script/build_and_run.sh`
- **Packaging:** `script/package_dmg.sh` (fail-closed Release, Developer ID,
  profile-authorized, notarized arm64 DMG — the direct-distribution build;
  Apple Silicon only), `script/package_local.sh` (development/CI `.app`),
  `script/archive_local.sh` (development/CI ZIP). Mac App Store packaging is a
  separate `script/archive_mas.sh` channel, never the DMG input.
- **App icon:** `Resources/AppIcon/LorvexAppIcon.icns`, regenerated from
  `Resources/AppIcon/master_1024.png` via `script/generate_app_icon.sh`. The
  master is the SHARED Lorvex brand mark — identical artwork to the Tauri app's
  `apps/tauri/app/src-tauri/icons/icon-1024.png`. Refresh both together.
- **XcodeGen project:** `script/verify_xcodegen_project.sh`

### In-repo docs

- `../../docs/vision/DESIGN_PHILOSOPHY.md` — Product philosophy and non-goals
- `../../docs/design/AI_OPERATING_MODEL.md` — MCP-first write model
- `../../docs/design/CALENDAR_BEHAVIOR.md` — EventKit + recurrence rules
- `../../docs/design/SORT_KEYS.md` — Canonical task ordering, per-view deviations
- `../../docs/design/SYNC_APPLY_SEMANTICS.md` — Idempotency, checksum, HLC rules
- `docs/setup/ASSISTANT_MCP_SETUP.md` — Wiring MCP clients to LorvexMCPHost
- `docs/execution/CI_RELEASE_TRIGGER_POLICY.md` — Release tag/dispatch rules
- `docs/reference/FEATURES.md` — Feature inventory vs the `../tauri` reference
- `docs/SURFACE_DESIGN.md` — Per-platform surface status (macOS, iOS,
  iPadOS, visionOS, watchOS, CarPlay, widgets, Spotlight,
  Shortcuts, CloudKit, EventKit, notifications, packaging)
- `docs/architecture/` — Module boundaries and cross-target dependencies
- `docs/plans/` — Active and deferred work plans
