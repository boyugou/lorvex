# Lorvex for Apple

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](../../LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20·%20iOS%20·%20iPadOS%20·%20watchOS-lightgrey.svg)](#surfaces)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)

> Your planner. Your AI's workspace. Built natively for Apple platforms.

**Lorvex** is an AI-native personal planning system. You use it as a calm,
local-first planner; an AI assistant connected over [MCP](https://modelcontextprotocol.io/)
does the heavy lifting — organizing tasks, planning today, proposing
schedules, and writing briefings. You make the decisions and do the work.

This repository is the **Apple-native** Lorvex: a ground-up Swift / SwiftUI /
AppKit rebuild that treats each Apple device as its own first-class surface
rather than a single ported UI. It shares product semantics and data shape with
the original cross-platform Lorvex (Rust + Tauri), but the experience is
designed the way Apple would design it.

There is **no AI runtime inside the app.** Intelligence comes from external
MCP-capable assistant clients (Claude and others) talking to Lorvex's
Swift-native MCP host.

---

## How it works

1. **Plan in the app** — capture tasks, organize lists, track habits, work
   through Today, review your day and week.
2. **Connect an AI assistant over MCP** — it creates and prioritizes tasks, plans
   what's on today, proposes time-blocked schedules, and keeps a plain-English
   audit trail. Every write returns the full updated object.
3. **Stay in flow everywhere** — Today follows you to your watch,
   your widgets, and CarPlay. (The menu-bar HUD keeps you on today's due count
   and next-up tasks.)

The pure-Swift `LorvexAppleCore` package owns the SQLite database (GRDB),
workflow rules, and sync; Swift owns the product and every surface.

## <a name="surfaces"></a>Surfaces

| Surface | What it's for |
|---|---|
| **macOS** | The command center — sidebar, multi-window, menu bar extra, full keyboard commands, tabbed Settings. |
| **iPhone** | Capture, glance, and plan — tab-first with quick capture, Today, reviews, and reach into every domain. |
| **iPadOS** | A `NavigationSplitView` sidebar with the full workspace set; keyboard- and pointer-aware. |
| **Apple Watch** | Wrist-glance Today and habits, one-tap complete, start/pause, defer, cancel, and capture, plus face complications. Forwards actions to the phone over WatchConnectivity. |
| **Widgets** | Today, Habits, and daily-progress widgets across system + accessory families, with interactive complete buttons. |
| **Control Center** | A Lorvex Control Center widget (iOS 18+) that shows the task at the top of Today and opens Lorvex to Today when tapped. |
| **CarPlay** | Hands-free Today list read against the clock, each row with its time detail; row tap opens a Done / Tomorrow instead / Open on iPhone / Cancel action sheet. Code wired; Apple Developer entitlement approval pending. See [`docs/SURFACE_DESIGN.md`](docs/SURFACE_DESIGN.md#carplay--hands-free-today) for provisioning steps. |
| **Menu bar** | A Today HUD: date header, due-count chip (and a count on the menu-bar glyph), one-line quick-add, the next-up task list with one-click complete, plus Open / Refresh / Quit. |

See [`docs/SURFACE_DESIGN.md`](docs/SURFACE_DESIGN.md) for the design intent and
honest status of each surface.

## Features

**Core planning**
- Tasks with priorities (P1–P3), due dates, duration estimates, tags,
  dependencies, checklists, reminders, and recurrence
- Lists with health snapshots; tag rename and per-tag views
- Calendar with EventKit read-only mirroring on every platform, macOS-only
  write-back for Lorvex-owned events, and `.ics` export
- Habit tracking with streaks, completion rates, milestone waypoints, and reminder
  policies
- Daily and weekly reviews (mood, energy, wins, blockers, learnings) with amend
  and history
- Today: one ordered list of what's planned, due, or started, with an
  assistant briefing and an optional time-blocked schedule (propose / save /
  clear)

**AI integration (via MCP)**
- A Swift-native MCP host built on the official
  [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)
- A broad tool catalog covering tasks, day planning, calendar, lists, tags, habits,
  reviews, memory, preferences, dependency graphs, and batch
  operations — every write returns the complete updated object
- App Intents / Shortcuts / Siri for capture, open, complete, defer, start/pause,
  and day planning
- Spotlight indexing for tasks, lists, habits, and reviews
- NSUserActivity Handoff between devices

**Apple-platform polish**
- System-native light / dark appearance with the user's Apple accent color
  applied app-wide through SwiftUI `.tint`
- Markdown rendering via [swift-markdown](https://github.com/swiftlang/swift-markdown),
  wrapped in the `LorvexMarkdownUI` target
- TipKit onboarding, drag-and-drop, value-typed multi-window, haptic
  feedback, rich notification actions, opt-in local diagnostics with MetricKit
  crash/hang capture
- Cross-device sync via iCloud / CloudKit (export, subscription, and ingestion
  paths)

## Architecture

```
Sources/
├── LorvexCore/            Platform-neutral models + LorvexCoreServicing protocol
├── LorvexCloudSync/       CloudKit sync engine (account status, push, checkpoints)
├── LorvexMarkdownUI/      swift-markdown → SwiftUI rendering
├── LorvexApple/           macOS app (SwiftUI + AppKit)
├── LorvexMobile/          iOS · iPadOS surface
├── LorvexMobileApp/       iOS @main entry
├── LorvexSystemIntents/   Shared App Intents · Shortcuts · Siri provider
├── LorvexWatch*/          watchOS store, @main app, and complication
├── LorvexCarPlay/         CarPlay scene + controller
├── LorvexMCPHost/         MCP stdio server (catalog · handlers · dispatch)
└── LorvexWidget*/         WidgetKit support, views, intents, extension, bundle
core/                      LorvexAppleCore SwiftPM package — pure-Swift core
                           (LorvexDomain · LorvexStore [GRDB/SQLite] ·
                            LorvexWorkflow · LorvexSync · LorvexRuntime)
```

The single write contract is `LorvexCoreServicing`. The macOS, mobile, watch,
widget, CarPlay, and MCP surfaces all consume it; `SwiftLorvexCoreService` runs
over the `LorvexAppleCore` package against the real database, and previews and
the test suite run the same service over an in-memory GRDB store.

## Quick start

**Prerequisites:** macOS 26 or newer, Xcode 26 or newer (Swift 6 toolchain).

```bash
# Build and test everything
swift build
swift test
(cd core && swift test)

# Run the macOS app
./script/build_and_run.sh --verify

# Full verification gate (builds, metadata, MCP smoke, entitlements, packaging)
./script/verify_all.sh
```

To connect an AI assistant, build the app and copy the generated MCP client
configuration (`./script/generate_mcp_client_config.py`) into your assistant's
MCP settings; it points at the bundled `LorvexMCPHost` stdio helper. Full steps
are in [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md).

## Documentation

**Setup**
- [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) — setup, capture, day planning, MCP, widgets, watch, sync
- [`docs/setup/ASSISTANT_MCP_SETUP.md`](docs/setup/ASSISTANT_MCP_SETUP.md) — connecting Claude, Codex, and other MCP clients; idempotency and security fencing contract

**Vision and Design**
- [`../../docs/vision/DESIGN_PHILOSOPHY.md`](../../docs/vision/DESIGN_PHILOSOPHY.md) — the AI-native product philosophy and design principles
- [`docs/SURFACE_DESIGN.md`](docs/SURFACE_DESIGN.md) — the design intent and honest status of each Apple surface
- [`../../docs/design/AI_OPERATING_MODEL.md`](../../docs/design/AI_OPERATING_MODEL.md) — the "Chief of Staff" mental model and MCP operational patterns
- [`../../docs/design/CALENDAR_BEHAVIOR.md`](../../docs/design/CALENDAR_BEHAVIOR.md) — three-family ownership model (tasks / canonical events / provider mirrors)
- [`../../docs/design/SORT_KEYS.md`](../../docs/design/SORT_KEYS.md) — canonical task sort key and allowed per-view deviations
- [`../../docs/design/SYNC_APPLY_SEMANTICS.md`](../../docs/design/SYNC_APPLY_SEMANTICS.md) — CloudKit sync apply pipeline, HLC conflict resolution, ai_changelog union semantics, idempotency cache

**Reference**
- [`docs/reference/FEATURES.md`](docs/reference/FEATURES.md) — feature status catalogue (`[SHIPPED]` / `[PARTIAL]` / `[PLANNED]`) with MCP tool catalog
- [`docs/execution/CI_RELEASE_TRIGGER_POLICY.md`](docs/execution/CI_RELEASE_TRIGGER_POLICY.md) — CI trigger policy and release tag conventions

**Contributing**
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — building, conventions, adding MCP tools and core methods
- [`docs/LOCALIZATION.md`](docs/LOCALIZATION.md) — adding locales and translatable strings
- [`CLAUDE.md`](CLAUDE.md) — agent / contributor operating rules (includes core design contracts)

## Status

Lorvex Apple is pre-public-release. It builds cleanly across all targets with a
large automated test suite, but several capabilities (CloudKit live sync,
CarPlay, push notifications) require Apple Developer provisioning and on-device
verification before they can be called externally available. Version numbers
identify build artifacts, not a data-format compatibility guarantee.

All public contact and support routes through `https://lorvex.app/support/`;
Lorvex has no public email mailbox.

## License

[Apache-2.0](../../LICENSE).
