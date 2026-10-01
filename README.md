<div align="center">

<img src="apps/apple/Resources/AppIcon/master_1024.png" alt="Lorvex" width="128" height="128">

# Lorvex

**The AI-native planner. Your assistant does the typing; you do the living.**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](apps/apple)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20·%20iOS%20·%20iPadOS%20·%20watchOS-black?style=flat-square&logo=apple&logoColor=white)](apps/apple)
[![MCP](https://img.shields.io/badge/MCP-114%20tools-6B57D2?style=flat-square)](apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md)

[Website](https://lorvex.app) · [Getting started](#getting-started) · [MCP setup](#connect-an-ai-assistant) · [Documentation](#documentation) · [Privacy](PRIVACY.md)

</div>

---

Lorvex is a task, calendar, and habit planner built **MCP-first**: the primary
write interface is a [Model Context Protocol](https://modelcontextprotocol.io)
server, so any MCP-capable AI assistant (Claude, or anything else that speaks
MCP) can manage your tasks, plan your days, schedule your calendar, and track
your habits through 114 typed tools. The native apps are calm, fast read
surfaces with the human actions that matter — complete, defer, review — not a
form-filling UI.

- **Local-first.** Everything lives in a SQLite database on your device. No
  accounts, no server of ours, fully usable offline.
- **Private sync.** Optional multi-device sync through your own iCloud
  (CloudKit private database) with encrypted payloads — multi-master,
  conflict-free (HLC clocks + last-writer-wins registers). We cannot read your
  data; there is nowhere for us to read it from.
- **No embedded AI, no tracking.** Lorvex ships no model, no analytics, no
  ads. Intelligence comes from *your* assistant, connected on *your* terms.
- **Native everywhere.** macOS, iPhone, iPad, Apple Watch, CarPlay, widgets,
  Shortcuts, Spotlight, and two-way EventKit calendar integration.

## How it works

```
┌──────────────┐   MCP (stdio)   ┌───────────────┐        ┌──────────────────┐
│ AI assistant │ ◄─────────────► │ LorvexMCPHost │ ◄────► │  Pure-Swift core │
│  (Claude, …) │    114 tools    │ (MCP server)  │        │  SQLite (GRDB)   │
└──────────────┘                 └───────────────┘        └────────┬─────────┘
                                                                   │ encrypted
┌──────────────┐   read / act    ┌───────────────────────┐         │ envelopes
│     You      │ ◄─────────────► │ Native apps & widgets │ ◄───────┴────────►  your iCloud
└──────────────┘                 └───────────────────────┘   (CloudKit private DB,
                                                              multi-master sync)
```

Every mutation — human or AI — flows through one audited write surface with
idempotency keys and a changelog, then syncs as an encrypted envelope in your
private CloudKit database. Other devices merge deterministically; no device is
"the server."

## Repository layout

The repository holds the Apple app plus the contracts it owns:

```
lorvex/
├── apps/
│   └── apple/     Apple-native app — Swift 6, SwiftUI/AppKit, SwiftPM.
├── schema/        SQLite schema (the Apple app's authority) + sync payload manifests.
├── cloudkit/      CloudKit record-type template and deploy tooling (Apple-owned).
├── spec/          Cross-implementation behavior contracts: docs + test-vector fixtures.
└── docs/          Project-level documentation (see docs/INDEX.md).
```

Lorvex began as a cross-platform Tauri app. That implementation was removed on
2026-09-17; this repository is the Apple-native app only.

## Getting started

### Apple app (macOS)

Requires Xcode 26 or newer (Swift 6 toolchain); the app targets macOS 26, iOS 26, and watchOS 26.

```bash
cd apps/apple
swift build              # build all targets
swift test               # app-level test suite
(cd core && swift test)  # pure-Swift core suite
./script/build_and_run.sh --verify   # build, verify, and launch the macOS app
```

iOS / watchOS build through the XcodeGen-generated project — see
[`apps/apple/CLAUDE.md`](apps/apple/CLAUDE.md) for the full developer manual
and [`apps/apple/docs/release.md`](apps/apple/docs/release.md) for packaging.

## Connect an AI assistant

With Lorvex installed, open **Settings → Assistant** and copy the setup prompt
or the config for your client. In Claude Code, the Lorvex plugin sets up the
connection and adds skills for planning a day, capturing tasks, the weekly
review, and tidying the assistant's memory
([`plugins/lorvex`](plugins/lorvex/README.md)):

```
/plugin marketplace add boyugou/lorvex
/plugin install lorvex@lorvex
```

From a source checkout, build the MCP host and point any MCP-capable client at
it:

```bash
cd apps/apple && swift build -c release --product LorvexMCPHost
```

```json
{
  "mcpServers": {
    "lorvex": {
      "type": "stdio",
      "command": "/path/to/lorvex/apps/apple/.build/release/LorvexMCPHost"
    }
  }
}
```

Full client-by-client instructions (Claude Desktop, Claude Code, and others):
[`apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md`](apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md).

## Documentation

| Topic | Where |
|---|---|
| Documentation index | [`docs/INDEX.md`](docs/INDEX.md) |
| Design philosophy & non-goals | [`docs/vision/DESIGN_PHILOSOPHY.md`](docs/vision/DESIGN_PHILOSOPHY.md) |
| Assistant operating model (instructions, skills, tool design) | [`docs/design/AI_OPERATING_MODEL.md`](docs/design/AI_OPERATING_MODEL.md) |
| Sync semantics (HLC, LWW, idempotency) | [`docs/design/SYNC_APPLY_SEMANTICS.md`](docs/design/SYNC_APPLY_SEMANTICS.md) |
| Schema & data-infrastructure invariants | [`docs/design/SCHEMA_OPTIMALITY.md`](docs/design/SCHEMA_OPTIMALITY.md) |
| Export / backup format | [`spec/EXPORT_FORMAT.md`](spec/EXPORT_FORMAT.md) |
| Feature inventory | [`apps/apple/docs/reference/FEATURES.md`](apps/apple/docs/reference/FEATURES.md) |
| User guide | [`apps/apple/docs/USER_GUIDE.md`](apps/apple/docs/USER_GUIDE.md) |
| Roadmap & status | [`ROADMAP.md`](ROADMAP.md) |

## Status

Pre-release. The Apple app is feature-complete and in App Store preparation;
the data, schema, sync, and backup contracts are finalized and gated by
repository verifiers (`apps/apple/script/verify_all.sh`). See
[`ROADMAP.md`](ROADMAP.md).

## Privacy

Local data, your iCloud, our zero access — the full policy is in
[`PRIVACY.md`](PRIVACY.md). Lorvex collects nothing: no accounts, no
analytics, no telemetry, no third-party services.

## Contributing & support

- Contributions: see [`apps/apple/docs/CONTRIBUTING.md`](apps/apple/docs/CONTRIBUTING.md).
- Issues and feature requests: [GitHub Issues](https://github.com/boyugou/lorvex/issues).
- Support: [lorvex.app/support](https://lorvex.app/support/).
- Security issues: report them privately, as described in [`SECURITY.md`](SECURITY.md).

## License

[Apache-2.0](LICENSE)
