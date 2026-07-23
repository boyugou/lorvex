# Lorvex — AI-Native Personal Planning System

> **Monorepo note.** This directory is the cross-platform Tauri app within the
> Lorvex monorepo (`apps/tauri`). It is a snapshot of
> [`github.com/boyugou/ai-native-todo`](https://github.com/boyugou/ai-native-todo),
> where its full commit history lives. It stays self-contained — build it from
> here with its own Cargo + npm + Tauri toolchain. Shared artifacts (`schema/`,
> `spec/`) live at the monorepo root; see the root `README.md` and
> `CLAUDE.md`.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> Your planner. Your AI's workspace.

**Lorvex** is a local-first personal planning system that works beautifully on its own and becomes extraordinary with an AI assistant. Your assistant organizes tasks, schedules days, and surfaces what matters via [MCP](https://modelcontextprotocol.io/) — you make the decisions and do the work.

## How It Works

1. **Use Lorvex as a standalone planner** — create tasks, manage lists, track habits, review your week
2. **Optionally connect an AI assistant** via MCP — it manages your tasks, sets today's focus, writes briefings, and saves focus schedules
3. **Open the app** to see your dashboard: today's focus, calendar, upcoming work
4. **Execute and review** — complete tasks, check the AI activity log, adjust as needed

The app contains no AI runtime. Intelligence comes from external MCP-capable assistant clients (Claude, etc.) connecting to Lorvex's MCP server.

## Features

**Core Planning**
- Task management with priorities, due dates, duration estimates, tags, and dependencies
- Smart lists with health snapshots and stalled-task detection
- Calendar with events, `.ics` subscription sync, and native calendar imports via Windows Appointments and Linux local calendar/ICS
- Habit tracking with streaks, completion rates, and daily check-ins
- Daily and weekly reviews with mood, energy, wins, blockers, and learnings
- Recurring tasks with flexible recurrence rules

**AI-Powered (via MCP)**
- AI-composed Today dashboard — your assistant controls layout, briefings, and focus
- AI-managed priority (P1-P3) — priorities shift based on deadlines, deferrals, and dependencies
- Focus scheduling — AI proposes daily time-blocked schedules
- AI memory — your assistant remembers your working style across sessions
- Full audit trail — every AI action logged in plain English

**Interface**
- WYSIWYG markdown editor (Milkdown) for task notes
- Quick Capture (`Cmd+N`) and Command Palette (`Cmd+K`)
- 12 theme options: Paper, Light, Dark, Ember, Midnight, Liquid Glass (dark + light), Mica (dark + light), Adwaita (dark + light), and a System auto-detect that follows the OS
- 4 appearance profiles (Clarity, Studio, Focus Compact, Liquid Glass)
- Adjustable font scale (Small to Extra Large)
- Menu bar popover with inline task expansion and quick actions
- Sticky note floating windows for pinned tasks
- Eisenhower matrix, Kanban board, dependency graph, and upcoming views
- 31 locales including English, Chinese, Japanese, Korean, Arabic, and Hindi

**Technical**
- Local-first SQLite database — your data stays on your machine
- Local export/import for backup and transfer; future non-Apple sync providers should reuse the provider-neutral sync model
- 117 MCP tools for comprehensive AI assistant integration
- Lorvex CLI — agent-first terminal companion with MCP serve, TUI, and shell commands
- Windows and Linux are the product-facing Tauri desktop runtime paths. The macOS Tauri build is a developer/reference build for Mac-only contributors. Apple App Store, iOS, and iPadOS belong to the Swift app under `apps/apple`; Android remains a future Tauri runtime.

## Release Status

Lorvex is still governed as a pre-public-release product. Package versions identify build artifacts and release channels; they are not a current data-format compatibility guarantee.

Current release availability is narrower than the implemented runtime surface: GitHub Releases currently provides repo-visible macOS developer/reference artifacts, and there is no proven stable release line yet. Windows and Linux packaging is implemented for future direct desktop distribution. Mac App Store builds are not part of the Tauri line.

Ordinary branch pushes do not package or publish, and `main` pushes run verification only. Release packaging and publishing are opt-in through protected release tags (`v*`, `mac-v*`) or explicit GitHub Actions manual dispatch with `release_mode` set to `dry-run`, `artifacts`, or `publish`; see [CI_RELEASE_TRIGGER_POLICY.md](docs/execution/CI_RELEASE_TRIGGER_POLICY.md) and [DISTRIBUTION.md](docs/design/DISTRIBUTION.md).

The active SQLite schema is a squashed baseline during this phase. Pre-release schema drift may be replaced directly instead of preserved through compatibility shims. Future public-release database compatibility will be documented as an explicit policy before real user databases are treated as stable.

## Quick Start

### Prerequisites

- [**Node.js**](https://nodejs.org/) 22+ and **npm** 10+
- [**Rust**](https://rustup.rs/) 1.86+ (install via `rustup`)
- **Platform-specific dependencies:**
  - **macOS:** macOS 14+ (Sonoma or later) to run the desktop app, plus Xcode Command Line Tools for development (`xcode-select --install`)
  - **Windows:** [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) with C++ workload, [WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
  - **Linux:** `libwebkit2gtk-4.1-dev`, `libappindicator3-dev`, `librsvg2-dev`, `patchelf` (see [Tauri Linux prerequisites](https://v2.tauri.app/start/prerequisites/#linux))

### Development

```bash
git clone https://github.com/boyugou/ai-native-todo.git lorvex
cd lorvex
npm ci
npm run -w app tauri:dev
```

This launches both the Vite dev server (frontend hot-reload) and the Tauri Rust backend. The app window opens automatically.

### Build for Distribution

```bash
# macOS Universal Binary DMG (see CLAUDE.md for signing/notarization):
bash scripts/build_dmg.sh

# Windows NSIS:
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1 -Bundle nsis

# Linux AppImage/deb/rpm:
npm run -w app tauri:build -- --bundles appimage,deb,rpm -- --locked
```

### Type Checking and Tests

<!-- verification-matrix:readme:start -->
Quick local verification subset. For the full canonical completion matrix, see [CONTRIBUTING.md#verification-commands](CONTRIBUTING.md#verification-commands).

```bash
npm run verify:ci-typecheck
cargo check --manifest-path app/src-tauri/Cargo.toml --all-targets
cargo clippy --manifest-path app/src-tauri/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path app/src-tauri/Cargo.toml --lib
cargo check --manifest-path mcp-server/Cargo.toml
cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings
cargo test --manifest-path mcp-server/Cargo.toml --lib
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --lib
```
<!-- verification-matrix:readme:end -->

### Lorvex CLI

The CLI is an agent-first terminal companion that shares the same database as the app.

```bash
# Build and install
bash scripts/build_cli.sh
bash scripts/install_cli.sh

# Set up and configure MCP
lorvex setup --install-mcp-for claude-code
lorvex doctor   # verify installation

# Use from terminal
lorvex tasks    # filtered task listing
lorvex graph    # task dependency graph
lorvex today    # what's on your plate
lorvex deferred # tasks you keep pushing off
lorvex reminder due # reminders needing attention now
lorvex reminder set <task-id> --at 2026-05-01T09:00:00Z
lorvex reminder add <task-id> 2026-05-01T17:00:00Z
lorvex reminder remove <task-id> <reminder-id>
lorvex reminder clear <task-id>
lorvex trash move <task-id> [task-id...]
lorvex trash restore <task-id> [task-id...]
lorvex trash delete <task-id> [task-id...] --dry-run
lorvex changelog # recent assistant-authored writes
lorvex capture "Ship the feature"
lorvex tag rename OldTag NewTag # rename or merge a tag
lorvex habit reminder upsert <habit-id> 07:30
lorvex focus    # today's focus plan
lorvex tui      # dashboard snapshot
```

See [docs/design/MULTI_SURFACE_ARCHITECTURE.md](docs/design/MULTI_SURFACE_ARCHITECTURE.md) for how App and CLI coexist.

### Connect an AI assistant

Open Lorvex → Settings → Assistant MCP → copy the config block into your MCP client.

See [GETTING_STARTED.md](docs/setup/GETTING_STARTED.md) for full setup and [ASSISTANT_MCP_SETUP.md](docs/setup/ASSISTANT_MCP_SETUP.md) for MCP wiring.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 19 + TypeScript + Tailwind CSS 4 |
| Backend | Tauri 2.x (Rust) |
| AI Interface | Rust MCP server via rmcp (117 tools) |
| CLI | Rust binary — MCP serve, TUI, shell commands |
| Shared Runtime | lorvex-runtime — DB locator, identity, sync leases |
| Database | SQLite (WAL mode, shared by app + CLI + MCP) |
| Editor | Milkdown (prosemirror + remark) |

## Design Philosophy

1. **AI-first, human-correctable.** MCP is the primary write interface; the UI is optimized for fast human correction.
2. **Standalone excellence.** The app is a great task manager even without AI — no AI lock-in.
3. **Conversation as review layer.** Discuss intent with your assistant before tasks are created.
4. **AI-managed priority.** Priority (P1-P3) is dynamic — the AI adjusts based on deadlines, deferrals, and dependencies.
5. **Local-first.** Your data lives in SQLite on your machine. Network sync is opt-in.

Read the full philosophy: [docs/vision/DESIGN_PHILOSOPHY.md](docs/vision/DESIGN_PHILOSOPHY.md)

## Documentation

| Document | Description |
|----------|-------------|
| [GETTING_STARTED.md](docs/setup/GETTING_STARTED.md) | Installation and first-use guide |
| [ASSISTANT_MCP_SETUP.md](docs/setup/ASSISTANT_MCP_SETUP.md) | Configure MCP clients |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup and coding standards |
| [docs/INDEX.md](docs/INDEX.md) | Full documentation reading guide |

## Architecture Overview

Lorvex is a workspace monorepo with eight Rust workspace crates, a separate
Tauri backend crate, and a React frontend:

```
lorvex-domain    Pure domain logic (no unconditional IO/storage deps; feature-gated rusqlite typed-id bindings)
lorvex-store     SQLite storage, migrations, export/import
lorvex-workflow  Cross-surface workflow ops (changelog, lifecycle, deferral, recurrence,
                 habit reminders, status side effects, memory, reseed) — sits above the
                 store and is shared by mcp-server, app/src-tauri, lorvex-cli, sync apply
lorvex-sync      Sync protocol (envelopes, merge, conflict log)
lorvex-runtime   DB locator, device identity, leases
lorvex-mcp-derive Internal proc-macro crate for MCP contract validation
mcp-server       117-tool MCP server (stdio transport)
lorvex-cli       Terminal companion (TUI, shell commands, MCP serve)
app/             Tauri 2 desktop app (React + Rust backend)
shared/          @lorvex/shared TypeScript types
```

See [docs/design/ARCHITECTURE.md](docs/design/ARCHITECTURE.md) for the full architecture guide.

## Contributing

We welcome contributions -- including opening issues. A well-described issue can be directly implemented by coding agents, making text contributions as impactful as code.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding standards, and verification commands.

## Credits

**Concept and product direction:** [Boyu Gou](https://github.com/boyugou)

**Implementation:** AI coding agents ([Claude Code](https://claude.ai/claude-code)).

## License

Apache License 2.0 -- see [LICENSE](LICENSE).
