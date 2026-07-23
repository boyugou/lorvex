# Contributing to Lorvex Apple

This guide covers the project layout, build steps, and conventions for
contributors. For product architecture detail, see
[`docs/architecture/apple-native-architecture.md`](architecture/apple-native-architecture.md).

---

## Project Layout

```
apps/apple/
├── Sources/
│   ├── LorvexCore/             # Platform-neutral models, protocol, factory
│   ├── LorvexCloudSync/        # CloudKit sync engine (account status, push, checkpoints)
│   ├── LorvexMarkdownUI/       # swift-markdown → SwiftUI rendering
│   ├── LorvexApple/            # macOS app shell (SwiftUI + AppKit)
│   ├── LorvexMobile/           # iOS/iPadOS/visionOS surface
│   ├── LorvexMobileApp/        # iOS @main entry point
│   ├── LorvexVisionApp/        # visionOS @main entry point
│   ├── LorvexSystemIntents/    # Shared App Intents and Shortcuts provider
│   ├── LorvexWatch/            # watchOS shared store + WatchConnectivity client
│   ├── LorvexWatchApp/         # watchOS focus companion entry point
│   ├── LorvexWatchComplication/# watchOS complications (WidgetKit on watchOS)
│   ├── LorvexCarPlay/          # CarPlay scene delegate + templates
│   ├── LorvexMCPHost/          # MCP stdio server executable
│   ├── LorvexWidgetKitSupport/ # Shared widget snapshot/timeline infrastructure
│   ├── LorvexWidgetViews/      # Reusable SwiftUI widget views
│   ├── LorvexWidgetIntents/    # Interactive widget AppIntents (iOS 18+)
│   ├── LorvexWidgetExtension/  # WidgetKit TimelineProvider + container
│   ├── LorvexWidgetBundle/     # @main WidgetBundle entry
│   ├── LorvexFocusWidget/      # Standalone focus widget
│   └── LorvexCoreSmoke/        # Executable smoke check for the on-disk Swift core
├── Tests/                      # Swift Testing test targets
├── core/                       # Native Swift core package (canonical behavior)
├── script/                     # Build, verify, packaging scripts
├── Config/
│   └── XcodeGen/               # project.yml for iOS/visionOS/watchOS/Widget
└── docs/                       # Architecture, user guide, release notes
```

### Key module responsibilities

**`LorvexCore`** — Shared domain types (`LorvexTask`, `TodaySnapshot`,
`CurrentFocusPlan`, etc.), the `LorvexCoreServicing` protocol,
`SwiftLorvexCoreService` (over the `LorvexAppleCore` package, on-disk in
production and in-memory for tests/previews via
`SwiftLorvexCoreService.inMemory()` / `LorvexPreviewCoreFactory`), system
intent mutation runner, App Intent handoff store, deep link contract, and
Shortcuts descriptor. Every platform target imports this module.

**`LorvexApple`** — The macOS `@main` SwiftUI app. `AppStore` is split into
focused extension files per concern (`AppStoreBatchTaskActions.swift`,
`AppStoreFocusActions.swift`, etc.). Views follow the
`<Domain>WorkspaceView / <Domain>DetailView / <Domain>Row` naming convention.

**`LorvexMobile`** — iOS/iPadOS/visionOS SwiftUI library. `MobileStore` is the
root state owner for mobile; it wraps the same `LorvexCoreServicing` boundary.
Compact layouts use `TabView`; regular-width layouts use `NavigationSplitView`.

**`LorvexCloudSync`** — CloudKit transport and synchronization engine. Only the
main-app implementation modules (`LorvexApple`, `LorvexMobile`,
`LorvexMobileApp`, and `LorvexVisionApp`) may link or import it. Each device's
main app retains one `CloudSyncEngineCoordinator` and routes normal sync plus
account, import, retention, and cloud-data maintenance through that same actor
gate.

**`LorvexSystemIntents`** — Shared App Intents target for macOS, iOS/iPadOS,
and visionOS. It owns `AppIntent`, `AppEntity`, `SetFocusFilterIntent`, and
`AppShortcutsProvider` types, while delegating task mutations to
`LorvexSystemIntentRunner` in `LorvexCore`. Add user-facing Shortcuts/App
Intents here, not under the macOS-only app target.

**`LorvexMCPHost`** — Command-line executable. Tool definitions live in
`*ToolCatalog.swift`, implementations in `*ToolHandlers.swift`, and each domain's
typed registry in `*ToolDefinitions.swift`. The typed entry binds the schema,
handler, mutation/idempotency policy, and response-fencing policy. `tools/list`,
dispatch, and idempotency membership are derived from those entries.

**`LorvexWidgetKitSupport`** — Owns the widget snapshot wire format, freshness
policy, timeline entry construction, and render model projection. Widget code
imports this instead of duplicating JSON decoding or stale-state logic.

**Non-app surfaces** — `LorvexMCPHost`, widgets, App Intents, watchOS, CarPlay,
and other helpers never link `LorvexCloudSync` or import CloudKit. Their writes
go through `LorvexCoreServicing` to the managed local database, where the
canonical transaction also creates its audit and outbox records. The main app
uploads that durable outbox work later. Adding a background sync helper is an
architecture change and requires an explicit ownership design first.

---

## Building

### Prerequisites

- Xcode 16 or later (provides Swift 6 toolchain)
- Python 3 (for verification scripts)
- XcodeGen (for iOS/visionOS/watchOS/Widget Xcode projects): `brew install xcodegen`

### Build and test

```bash
# Build all SwiftPM targets
swift build

# Run all tests
swift test

# Build the macOS app and run a quick smoke check
./script/build_and_run.sh --verify

# Full verification gate (required before committing substantial changes)
./script/verify_all.sh
```

### Local packaging

```bash
# Development/CI package into dist/Lorvex.app and emit MCP client config
./script/package_local.sh

# Create a local verification ZIP (not the public release artifact)
./script/archive_local.sh
```

The public direct-distribution artifact is the production Developer ID DMG from
`package_dmg.sh`. Do not run it as a routine contributor check: it requires an
armed schema freeze, real Developer ID identity and profiles, notary
credentials, contacts Apple twice, and irreversibly erases this Mac's Lorvex
App Group while verifying the exact mounted artifact. It replaces the app at
`/Applications/Lorvex.app` (or the explicit absolute production install path),
cold-launches that exact installed copy, and does not back up or restore either
the previous app or its data. See `docs/DISTRIBUTION.md` for its operator-only
environment.

### iOS, visionOS, and watchOS builds (requires XcodeGen + Xcode)

The iOS, visionOS, and watchOS targets cannot be built with `swift build` alone;
they require an Xcode project generated by XcodeGen.

```bash
# Verify the XcodeGen project is correct (generates and validates project.yml)
./script/verify_xcodegen_project.sh

# Compile-only check for an iOS, visionOS, or watchOS target (no signing needed)
./script/archive_ios.sh --scheme LorvexMobileApp --build-only
./script/archive_ios.sh --scheme LorvexVisionApp --build-only
./script/archive_ios.sh --scheme LorvexWatchApp  --build-only

# Archive + export IPA to App Store Connect (requires APPLE_TEAM_ID)
export APPLE_TEAM_ID="ABCDE12345"
./script/archive_ios.sh --scheme LorvexMobileApp --export
./script/archive_ios.sh --scheme LorvexVisionApp --export
```

`archive_ios.sh` runs `xcodegen` against `Config/XcodeGen/project.yml` to
regenerate the Xcode project under `dist/ios-xcode-project/` before every
archive. The script selects the correct `generic/platform` destination for each
scheme: `iOS` for `LorvexMobileApp`, `visionOS` for `LorvexVisionApp`, and
`watchOS` for `LorvexWatchApp`.

**watchOS embed requirement.** The App Store requires a watchOS app to ship
inside its companion iOS app. `archive_ios.sh --scheme LorvexWatchApp --export`
checks that `LorvexWatchApp` is declared as an embedded dependency of
`LorvexMobileApp` in `project.yml` and exits with an error if the embed is
absent. See `docs/DISTRIBUTION.md §5` for the embed configuration and current
status.

### Simulator builds (requires matching Xcode SDK)

```bash
# All Apple platform build checks (simulators + Release device-graph links)
./script/verify_apple_simulators.sh

# iOS simulator
./script/verify_mobile_simulator.sh

# visionOS simulator
./script/verify_vision_simulator.sh

# watchOS simulator
./script/verify_watch_simulator.sh

# iPhone Release device graph, unsigned (catches Release-only link failures)
./script/verify_mobile_release_link.sh

# visionOS Release device graph, unsigned (catches Release-only compile/link
# failures, including APIs gated behind an OS version newer than the
# visionOS deployment floor)
./script/verify_vision_release_link.sh
```

The platform-specific scripts fail early with SDK/runtime diagnostics if the
required simulator is not installed. The aggregate script still attempts every
check and then prints a per-check summary, returning 78 when one or more
simulator runtimes or platform SDKs are unavailable.

---

## Adding a New MCP Tool

Every MCP tool requires three coordinated changes. Omitting any one of them
leaves the tool invisible to the host.

### 1. Define the tool schema in a catalog file

Add a static `ToolDefinition` entry in the appropriate `*ToolCatalog.swift`
file, or create a new `<Domain>ToolCatalog.swift` if the tool belongs to a new
domain:

```swift
// Sources/LorvexMCPHost/MyDomainToolCatalog.swift
enum MyDomainToolCatalog {
    static let myNewTool = Tool(
        name: "my_domain_new_tool",
        description: "One-sentence description of what the tool does and returns.",
        inputSchema: .object(
            properties: [
                "task_id": .string(description: "The task identifier.")
            ],
            required: ["task_id"]
        )
    )
}
```

### 2. Implement the handler

Add the handler function in the matching `*ToolHandlers.swift` file:

```swift
// Sources/LorvexMCPHost/MyDomainToolHandlers.swift
func handleMyNewTool(
    arguments: [String: Value],
    service: any LorvexCoreServicing
) async throws -> [TextContent] {
    guard let taskId = arguments["task_id"]?.stringValue else {
        throw MCPError.invalidParams("task_id is required")
    }
    let result = try await service.myNewOperation(taskId: taskId)
    // Always return the complete updated object, not a success flag.
    return [TextContent(text: result.jsonEncoded())]
}
```

### 3. Add the typed tool definition

Bind the schema and handler in the matching domain's `*ToolDefinitions.swift`.
Choose `.read` or `.write` deliberately; `.write` participates in the optional
idempotency-key contract. The definition's response-fencing policy is applied
by the common dispatcher:

```swift
// Sources/LorvexMCPHost/MyDomainToolDefinitions.swift
.write(120, MyDomainToolCatalog.myNewTool) {
    try await $0.handleMyNewTool(arguments: $1)
},
```

Do not add a second listing entry, dispatch switch, idempotency allowlist, or
fencing allowlist. All four are derived from this definition. The listing-order
number is part of the stable `tools/list` order and must remain unique and
contiguous from zero.

Update `script/expected_mcp_tools.py` in the same change. The expected list is
the release contract for the Swift-native MCP host, and
`script/verify_mcp_tool_catalog.py` compares it against the actual
typed registry surface and checks write/idempotency agreement. A tool is not
complete until the catalog verifier and stdio smoke both see it.

### Tests

Add a test in `Tests/LorvexAppleTests/` (or the nearest domain test file)
using the real in-memory core as the fixture:

```swift
@Test func myNewToolReturnsTask() async throws {
    let service = try await makeSeededInMemoryCore()
    let result = try await handleMyNewTool(
        arguments: ["task_id": .string(LorvexPreviewSeedID.agendaTask)],
        service: service
    )
    #expect(result.first?.text.contains(LorvexPreviewSeedID.agendaTask) == true)
}
```

---

## Adding a New `LorvexCoreServicing` Method

New data operations must follow the three-point pattern:

### 1. Protocol declaration (`LorvexCore`)

Add the method signature to `LorvexCoreServicing.swift`:

```swift
func myNewOperation(taskId: String) async throws -> LorvexTask
```

### 2. Swift core implementation (`SwiftLorvexCoreService`)

Implement the method in the matching `SwiftLorvexCoreService+<Domain>.swift`
extension. Reads go through `LorvexStore` repos / `Overview`; writes funnel
through the `+WriteSurface` adapter (one HLC version per mutation, transaction +
`ai_changelog` + `local_change_seq` bump). Every method is `async throws`; do
not silently swallow errors.

### 3. Defaults / no-op stub

If the method has a sensible default (no-op, empty list, nil), add it as a
protocol extension default in `LorvexCoreServicing.swift`. This prevents
compile errors on platform targets that do not override every method.

Do not leave the complete runtime service on those defaults.
`SwiftLorvexCoreService` must implement every domain protocol method except
explicit real composition defaults such as `exportData`. Run
`script/verify_core_service_coverage.py` to prove the complete service cannot
fall through to an `unsupportedServiceOperation` default.

---

## Conventions

### Swift 6 Strict Concurrency

All types that cross actor boundaries must conform to `Sendable`. Prefer
`actor` for mutable shared state. Use `@MainActor` on all `ObservableObject`
stores and SwiftUI view models. When a closure captures state across actor
boundaries, annotate it explicitly rather than relying on inference.

### File Size

Keep files under approximately 400 lines. `AppStore` is the canonical example:
it is split into `AppStore<Domain>Actions.swift` and
`AppStore<Domain>DerivedState.swift` files, each covering one domain concern.
Apply the same split whenever a file grows beyond that guideline.

### One Concern Per File

Each file should have a single, clearly named responsibility. Do not add
unrelated helpers to an existing file because it is convenient. Create a new
file with a name that describes its role.

### Accessibility

Every interactive view must have an `accessibilityLabel`. Use
`accessibilityHint` for non-obvious affordances. Verify with the Accessibility
Inspector and VoiceOver before calling a view complete.

### No Force Unwrap

Use `guard let` or `if let`. Force unwrap (`!`) is permitted only in `#Preview`
blocks and test fixtures where a crash is an acceptable signal.

---

## Testing

### Framework

Use **Swift Testing** (`import Testing`, `@Test`, `#expect`). The test targets
live in `Tests/`.

### Default Fixture

The real core over an in-memory GRDB store is the default test fixture for all
unit and integration tests: `makeSeededInMemoryCore()` (pre-populated with the
fixed preview dataset, rows addressed through `LorvexPreviewSeedID`) or
`makeInMemoryCore()` (empty). Both run production query/write semantics with no
on-disk footprint. Do not create mock service objects from scratch — seed a
real in-memory core through its own API instead.

### Recording Helpers

`RecordingXxx` helpers (where they exist) capture sequences of calls for
assertion. Use them when verifying call order or side-effect sequences rather
than relying on output values alone.

### What to Test

- Every new MCP tool handler: happy path, missing required argument, invalid
  argument type.
- Every new `LorvexCoreServicing` method: at least one test via the real
  in-memory core.
- Every new view model derived-state computation.
- Widget timeline projection and snapshot loading when touching
  `LorvexWidgetKitSupport`.

### Running Tests

```bash
swift test
```

All tests must pass before committing. The full gate (`verify_all.sh`) also
runs tests as part of its sequence.

---

## Verification Gate

`./script/verify_all.sh` is the required pre-commit gate for substantial
changes. It runs:

1. `swift build` — all SwiftPM targets
2. `swift test` — all test targets
3. Python verification script compilation and unit tests, including MCP client
   config validation, release/platform manifest validation, shared
   quality gate metadata, build matrix validation, system entrypoint drift
   checks, and generated MCP client
   config verification, including executable bundled helper validation
4. Metadata consistency checks (bundle ids, entitlements, App Group,
   CloudKit container, widget identifiers)
5. Apple-only strategy checks (`script/verify_apple_strategy.py`) to reject
   CLI products, Tauri/Node packaging artifacts, web UI source artifacts such
   as `.tsx`, `.jsx`, `.css`, `.html`, and `.js`, Windows/Linux targets, custom
   theme-system source paths, non-Swift MCP host drift, and Rust MCP server
   fallback names such as `RustMCP`, `MCPServer`, `MCPDaemon`, or
   `MCPSupervisor`. The same verifier pins main-app-only CloudSync ownership by
   rejecting `LorvexCloudSync` dependencies, CloudKit imports, or coordinator
   construction in non-app production targets.
6. MCP tool catalog contract checks (`script/verify_mcp_tool_catalog.py`)
7. Build matrix checks (`script/verify_build_matrix.py`) to ensure every Apple
   executable product is declared and built by the full gate
8. System entrypoint checks (`script/verify_system_entrypoints.py`) for Home
   Screen quick actions and cross-device `NSUserActivityTypes`
9. Hotspot checks (`script/verify_hotspots.py`) to keep Swift source files
   under the current 800-line cap
10. MCP stdio smoke checks (`script/mcp_stdio_smoke.py`): unsandboxed builds use
    a disposable database. The separate credentialed production-DMG harness
    requires `LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1`, clears the main app's
    defaults/private CloudSync state and irreversibly resets the real App Group
    before the exact installed app's first cold launch, then the sandboxed MCP
    smoke resets the App Group again before and after its production-entitlement
    round-trip
11. Generated MCP client config verification, including executable bundled
   helper validation
12. XcodeGen project contract checks (writes and verifies
   `dist/lorvex-apple-platform-manifest.json`)
13. Launch verification (launches the built app binary against real managed
   storage and confirms it starts cleanly)
14. Local packaging (`script/package_local.sh`)
15. Local archive verification — builds the development ZIP, extracts it, verifies signing and
   entitlements, launches the extracted app, checks the Widget extension, and
   writes `dist/lorvex-apple-release-manifest.json`

The credential-free full gate deliberately does not invoke the production DMG
path. `verify_packaging.sh` plus `test_production_dmg_packaging.py` pin that
path's fail-closed orchestration and exercise profile/notary decisions with
synthetic data and mocked command results. They also pin the real-install path,
mounted-to-installed content identity, exact executable launch, PlugInKit
registration, stale-DMG refusal, and required runtime evidence without invoking
the credentialed or destructive production command.

**Run the full gate before any commit that touches:**
- `Package.swift`
- Entitlement files
- `Config/` or `script/`
- `LorvexMCPHost` (tool registration or dispatch)
- `LorvexCore` public protocol surface
- `LorvexSystemIntents` or App Intent/Shortcuts behavior

For incremental UI or test changes, `swift build && swift test` is sufficient.

---

## Commit Style

- **Present tense, imperative mood.** "Add task recurrence tool" not "Added" or
  "Adds".
- **What and why in the message body.** The title names the change; the body
  explains the motivation or constraint if it is not obvious from the diff.
- **No emoji.** Keep commit messages plain text.
- **Link issues** by number when a commit closes or relates to a tracked issue:
  `Closes #42` or `Related to #38`.
- **One logical change per commit.** Avoid mixing unrelated fixes or
  refactors. If two concerns are truly coupled, describe both in the message
  body.

Example:

```
Add add_to_current_focus tool to MCP host

The AI client needs a way to append a task to the current focus plan without
replacing the whole ordered set. Wires the existing CurrentFocusItemsRepo union
path through the typed tool definition and returns the updated focus plan.
Closes #57.
```
