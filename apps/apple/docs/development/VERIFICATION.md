# Verification and QA

How to prove a change works: the test suites and their quirks, the probe
suites, the oracles, and the headless capture channels for visual review. The
everyday commands are in `apps/apple/CLAUDE.md`; this page holds the detail
behind them. Commands run from `apps/apple`; `$S` stands for a scratch
directory outside the repository.

## Builds and tests

- `script/verify_swift.sh` is the one command for the whole Swift tree: it runs
  `swift build -j 4 --build-tests`, `script/compile_xcstrings.sh`, and
  `swift test --skip-build -j 4`, passes its arguments to `swift test`, and
  `--core` adds the core package's suite. The native SwiftPM build system,
  Xcode 26.x's default, copies the string catalogs without compiling them, so a
  plain `swift build && swift test` there fails about thirty localization tests
  ("1 tasks", a missing `zh-Hans.lproj`). Swift Build, the default from
  Xcode 27, compiles them itself. A failing run of that shape means the compile
  step was skipped, not that the code is wrong.
- `swift build` does not compile test targets, so `swift test --skip-build`
  afterward runs the previous test binary. Build with
  `swift build -j 4 --build-tests`, and confirm a new test's name appears in
  the output.
- `swift build --product LorvexApple` compiles neither `LorvexMobile`'s
  iOS-only branches nor watchOS code. `#if os(iOS)` test files never compile
  under SwiftPM. Check iOS code with `script/ios_sim_build.sh` and watchOS code
  with `script/watch_sim_build.sh`.
- Run the full `swift test -j 4` before every commit that touches Swift.
  Source-pin tests (for example `MobileRegularLayoutParityTests`,
  `MobileViewEntrypointTests`, `MacHitTargetSourceTests`) and
  `script/verify_source_hygiene.py` match literal source fragments and file
  names, and a `--filter` run skips them. Before rewording or deleting a line in
  a view, search `Tests/` and the hygiene script for it, and update them in the
  same commit.
- `--filter` matches type and function names, never a `@Suite("display name")`.
- Gate on the test command's own exit code, never on a `grep` of its log.
- A language server's background index (an editor's, or one an agent starts
  after a Swift edit) can load the machine above 100 and fail time-bound tests;
  stop it before a full run.
- A full run takes about three to four minutes for roughly 5,500 tests (4,966
  Swift Testing tests and 547 XCTest cases) on an otherwise idle Apple Silicon
  Mac. The `@MainActor` tests share one main actor, so a test's reported duration and its
  `.timeLimit` include queue wait. When a full run shows a few time-bound
  failures, rerun them with `-j 1 --filter`; if they pass alone, the machine was
  loaded. `AppStoreBatchCompleteUndoTests`, `AppStoreCaptureTests`,
  `AppStoreToastTests`, and `StorageGenerationCutoverTests` are the usual ones.
  Judge a failing run by its total duration and `uptime` before reading the
  failures, and do not start another build while it runs.
- In-memory cores use a wall clock fixed at 08:00 today. A test that computes
  its expectation from the real `Date()` fails only between midnight and about
  04:00; pass the clock the core uses.
- The core package has its own suite: `(cd core && swift test -j 4)`, needed
  only when `core/` changed. Its first build takes about three minutes.
- Swift Testing quirks: `#expect(cgFloat == 14 + 3)` can fail across numeric
  types; `#expect(try await …)` prints `<not evaluated>` on failure. A test
  using `UndoManager` sets `groupsByEvent = false` and groups explicitly. A
  test that would reach live EventKit injects `authorizationStatusProvider`.
- `script/verify_static_gates.sh` runs every static gate (Python gates, their
  unit tests, the schema embed check, the public-safety scan) in about 30
  seconds, builds and launches nothing, and is the check before each push.

## Probe suites

The `ZZ…Tests.swift` files in `Tests/LorvexAppleTests/` are randomized walks,
fuzzers, and render probes. Each heavy one is inert unless its environment
variable is set. Build once with `swift build --build-tests -j 4`, then run
`swift test --skip-build -j 4 --filter <SuiteName>`. A trap ends the whole test
process, so run risky variants one at a time. Findings and images go to
`LORVEX_SCRATCH_DIR`, or the temporary directory when it is unset. Name a
throwaway probe `ZZ<Topic>Tests.swift` and delete it afterward; never overwrite
`ZZScratchRenderTests.swift`.

| Suite | Walks or fuzzes | Variables |
|---|---|---|
| `ZZRandomWalkProbeTests` | Mac `AppStore` task actions compared with the core | `WALK_SEED` (required), `WALK_STEPS`, `WALK_TRACE` |
| `ZZMobileWalkProbeTests` | iOS `MobileStore` task actions | `MOBILE_SEED`, `MOBILE_STEPS`, `MOBILE_TRACE` |
| `ZZMobileEntityWalkProbeTests` | iOS habits, lists, memory, events, review | `ENTITY_SEED` (required), `ENTITY_STEPS`, `ENTITY_TRACE`, `ENTITY_COVERAGE`, `ENTITY_SABOTAGE=archived\|detail`, `ENTITY_LOOPBACK` |
| `ZZAppEntityWalkProbeTests` | Mac entities, Reviews, calendar, planning | the same with the prefix `AENTITY_` |
| `ZZCaptureParserFuzzProbeTests` | quick-add parser in every language, from mutated test lines | `FUZZ_RUN=1` (required), `FUZZ_SEED`, `FUZZ_PER_LANG`, `FUZZ_STRICT`, `FUZZ_NFD`, `FUZZ_SHOW` with `FUZZ_INPUT` and `FUZZ_LANG` |
| `ZZMCPToolFuzzProbeTests` | every MCP tool with schema-generated hostile arguments | `MCPFUZZ_RUN=1` (required), `MCPFUZZ_SEED`, `MCPFUZZ_ROUNDS`, `MCPFUZZ_ONLY=a,b`, `MCPFUZZ_SHOW` with `MCPFUZZ_SHOW_FILE`; modes `MCPFUZZ_HOSTS=1`, `MCPFUZZ_RECUR=1`, `MCPFUZZ_PARITY=1`, `MCPFUZZ_HABITS=1` |
| `ZZMarkdownDepthProbeTests` | deeply nested markdown | `PROBE_KIND=quote\|dash\|ordered\|emph\|quotedash\|spawn`, `PROBE_N` |
| `ZZReviewDraftProbeTests`, `ZZStaleSelectedProbeTests` | review drafts; stale selected task | `REVIEW_PROBE`; `STALE_PROBE`, `REOPEN_PROBE` |
| `ZZScratchRenderTests`, `ZZTimeChipRenderProbeTests`, `ZZDropProbeTests`, `ZZWeekGridDropProbeTests` | view renders and synthetic drops | `LORVEX_SCRATCH_DIR` |

Notes:

- The entity walks mix assistant edits, peer edits (a core edit followed by the
  selective inbound reload), and plain refreshes. Loop-back mode follows each
  store write with `refresh()`, as the app does; review work needs it. The
  walks do not model real sheets, tab lifecycle, CloudKit apply, EventKit, or
  overlapping async work.
- The MCP fuzz oracles: an error code instead of a throw, no raw internals in
  messages, under 3 s per call, failed calls and reads change nothing, a
  successful write adds one changelog row, a keyed replay is identical, and
  user strings are fenced.
- The drop probes need a Launch Services record for the app's drag types; a
  built `dist/Lorvex.app` provides one. A synthetic drop drives SwiftUI's drop
  view with a fake `NSDraggingInfo` and a private `NSPasteboard`.

## Oracles and committed checks

- **Recurrence.** `script/recurrence_oracle.py` compares the recurrence engine
  with python-dateutil. `spec/fixtures/recurrence/oracle-cases.json` holds the
  committed vectors that `CalendarRecurrenceOracleTests` (core) replays. After
  editing `CalendarRecurrence*.swift`, run a wide sample:
  `uv run script/recurrence_oracle.py --cases 20000 --seed N "$S/wide.json"`,
  then in `core/`:
  `LORVEX_RECURRENCE_ORACLE_CASES="$S/wide.json" swift test -j 4 --filter CalendarRecurrenceOracleTests`.
- **Sync convergence.** `Tests/LorvexCoreServiceTests/SyncConvergenceSimulationTests.swift`
  runs several replicas over a simulated transport:
  `LORVEX_SYNC_SIM_TRANSPORT=log|chaos` (log models a CloudKit zone, chaos
  reorders freely), `LORVEX_SYNC_SIM_SEEDS`, `LORVEX_SYNC_SIM_STEPS`,
  `LORVEX_SYNC_SIM_FIRST_SEED`. Long soaks fail a few seeds on the known limits
  listed in `ROADMAP.md`. `core/Tests/LorvexSyncTests/ApplyEdgeAliasConvergenceTests.swift`
  checks edge alias folding over permutations.
- **Committed sweeps.** `MCPResponseFencingSweepTests`,
  `MCPExtremeIntegerArgumentTests`, `BackupWholeStoreRoundTripTests` (every
  table is declared backed up or local, and a restore is lossless apart from
  clocks and some timestamps), and `TitleFieldFitTests`.

## Headless visual review

Rebuild before capturing and delete old capture folders, so nothing stale is
mistaken for current behavior. None of these channels opens a window,
activates an app, or needs Simulator.app. Shut simulators down afterward.

### macOS tour

`script/ui_tour_macos.sh <light|dark> <outdir>` photographs the DEBUG
`--ui-preview` window, which never becomes key, at about 57 stops over a seeded
in-memory core with EventKit and CloudKit off. Toolbar and prominent buttons
therefore draw in their inactive gray. Image size depends on the display, so
compare pixels only between tours from the same machine. Launch arguments go in
`LORVEX_TOUR_EXTRA_ARGS`:

- language: `"-AppleLanguages (de) -AppleLocale de_DE"`; Arabic needs no extra
  right-to-left flag;
- data: `-lorvexSeedStressData`, `-uiPreviewEmptyStore`;
- clock: `-lorvexPreviewNow HH:mm` (DEBUG only, default 11:20); a tour started
  just before midnight shows two different days;
- accessibility: `-lorvexDifferentiateWithoutColor`, `-uiPreviewDumpAX`
  (then `script/mac_ax_report.py` over the tour log; the shell must be trusted
  for Accessibility);
- window: `-uiPreviewWindowSize 1000x600`.

Popovers cannot be toured, and `ImageRenderer` draws a placeholder glyph for
AppKit-backed views. `script/widget_gallery_macos.sh <outdir>` renders the Mac
widgets offscreen in light and dark.

### iOS and iPadOS simulator

`script/ios_sim_build.sh`, then
`script/ios_sim_screenshots.sh <outdir> <light|dark> <routes…>`. The script
boots the simulator headless, pins the default text size and Increase Contrast
off, clears the app's App Group data after install, captures each route, and
shuts down. Read the script for the route list (`today`, `tasks`,
`calendar-day`, `calendar-week`, `calendar-month`, `habits`, `review`,
`settings`, `widgets…`, or raw `lorvex://` URLs such as
`lorvex://findtask/<url-encoded title>/edit` and
`lorvex://sheet/capture/<text>`).

Environment: `LORVEX_SIM_UDID` and `LORVEX_SIM_DEVICE` pick the device (pass
the UDID when two simulators share a name), `LORVEX_SIM_EXTRA_ARGS` carries
launch arguments, `LORVEX_SIM_SETTLE` sets the wait before a capture (raise it
for the stress seed or scrolling), `LORVEX_SIM_FRESH=1` erases first, and
`LORVEX_SIM_INCREASE_CONTRAST=enabled` turns on Increase Contrast, which is
device state that survives shutdown.

DEBUG launch arguments: `-lorvexSeedSampleData` (seeds only an empty store),
`-lorvexSeedStressData`, `-lorvexPreviewNow 11:20`, `-lorvexOpenURL <url>`,
`-lorvexPreviewOrientation landscape` (landscape iPhone), `-lorvexScrollListTo
middle|end`, `-lorvexPreviewDayState overbooked|allDone|empty`,
`-setupCompleted NO`, `-lorvexDumpAX`, `-lorvexDifferentiateWithoutColor`,
`-UIPreferredContentSizeCategoryName <category>`, and `-AppleLanguages (xx)
-AppleLocale xx_XX`. Text size categories run from
`UICTContentSizeCategoryXS` through `XXXL`, then
`UICTContentSizeCategoryAccessibilityM` through `AccessibilityXXXL`. A debug hook
that reads seeded data waits on `MobileSeedDebugState.waitUntilFinished()`.
The iOS seed generates ids, has no task notes, and schedules no reminders, so
no permission alert covers a capture.

Capture traps:

- A simulator App Group left from an older build holds an incompatible
  database, and the app reports that it cannot access its data storage. This
  is the schema check failing closed, not an app bug; `simctl uninstall` does
  not clear the App Group, and the script's wipe does.
- A new simulator's first boots can capture Today for any deep link; capture
  again before investigating.
- Never use `simctl openurl`: it raises a confirmation dialog that cannot be
  dismissed headlessly. Routes go through `-lorvexOpenURL`.
- Compare captures by pixels, not bytes; Liquid Glass buttons differ slightly
  per run. `PIL.ImageChops.difference(a, b).getbbox()` returning `None` proves
  two captures equal.
- Measure contrast on full-resolution captures with a luminance script, not on
  downscaled previews.
- iPad landscape cannot be set by a launch argument; only a UI test that sets
  `XCUIDevice.shared.orientation` rotates it.

### VoiceOver tree dumps

`-lorvexDumpAX` (`Sources/LorvexMobileApp/DebugAccessibilityDump.swift`) waits
12 seconds and prints one line per element:
`AXDUMP E <depth> [x,y wxh] traits=… label='…' value='…' id='…' actions='…'`.
SwiftUI builds its accessibility tree only while accessibility is on, so first
write `ApplicationAccessibilityEnabled` and `AccessibilityEnabled` as true with
`xcrun simctl spawn <udid> defaults write com.apple.Accessibility …` on the
booted device. Launch with `simctl launch --console` redirected to a file, wait
for `AXDUMP done`, then remove both keys with `plutil -remove` on the shut-down
device. The dump matches what VoiceOver reads; XCUITest trees list children of
ignored elements that VoiceOver never reaches.

### Watch and widgets

`script/watch_sim_build.sh`, then
`script/watch_sim_screenshots.sh <outdir> today habits capture actions` boots
the watch with its paired iPhone and captures each page from the DEBUG sample
day. Run it alone, one route set at a time; the first run after a boot can
capture the watch face, so run it again. `LORVEX_WATCH_SIM_UDID` and
`LORVEX_WATCH_SIM_EXTRA_ARGS` work like their iOS counterparts. The iOS widget
gallery is the `widgets…` routes of `ios_sim_screenshots.sh`, which accept
language arguments.

### Quick-action replay

To replay a Home Screen quick action, write the key
`LorvexPendingIntentQuickAction` with the value `com.lorvex.apple.quickCapture`
into the App Group defaults through the simulator's preferences daemon
(`simctl spawn <udid> defaults write` on the container's
`Library/Preferences/group.com.lorvex.apple`). Editing the plist with `plutil`
on a booted device is invisible to the app.

## Things only a device or a person can verify

Real drags and resizes, undo, context menus, Full Keyboard Access, the Quick
Capture hotkey, Open at Login, the Control Center capture control, real-finger
calendar swipes, watch hardware, iPad hardware-keyboard shortcuts, two-device
CloudKit sync, and background notification actions. `ROADMAP.md` keeps the
current list.
