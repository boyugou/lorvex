# Verification and QA

How to prove a change works: the test suites and their quirks, the probe
suites, the oracles, and the headless capture channels for visual review. The
everyday commands are in `apps/apple/CLAUDE.md`; this page holds the detail
behind them. Commands run from `apps/apple`; `$S` stands for a scratch
directory outside the repository.

## Builds and tests

- The **LorvexMobileUITests** scheme in the generated Xcode project checks the
  spoken result of a quick capture. In Xcode 27 or later, choose a fresh iOS 27
  iPhone simulator and run the scheme's tests (⌘U). The test creates an undated
  task, enables VoiceOver, checks the title and list after the ordinary
  confirmation timeout, then follows the next spoken control into task detail.
  It restores the simulator's VoiceOver setting afterward. Run
  `script/ios_sim_build.sh` to generate the project under
  `dist/xcode-LorvexMobileApp`.

- `script/verify_swift.sh` is the one command for the whole Swift tree: it runs
  `swift build -j 4 --build-tests`, `script/compile_xcstrings.sh`, and
  `swift test --skip-build -j 4`, passes its arguments to `swift test`, and
  `--core` adds the core package's suite. The native SwiftPM build system
  (`--build-system native`) copies the string catalogs without compiling them,
  so a plain `swift build && swift test` there fails about thirty localization
  tests ("1 tasks", a missing `zh-Hans.lproj`). Swift Build, the default in
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
- A run whose output stops for minutes is not slow: something has blocked
  every thread of the cooperative pool, and the tests resume only when a
  blocking wait times out. Raising time limits only lengthens the stall. Run
  `sample <pid> 3` on the test process (`swiftpm-testing-helper` for Swift
  Testing, `xctest` for XCTest) while it is quiet; the pool threads'
  stacks name the wait. A hosted runner has three cores, so the pool has
  three threads; `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` gives it one and
  surfaces such a wait on this Mac. The rule is in `ENGINEERING_TRAPS.md`
  under "Async work and state".
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
| `ZZImportMutationFuzzProbeTests` | the backup importer, from the golden v1 fixture with fields deleted, retyped, hostile, or truncated; an import may refuse or restore in part but must not trap or take over 5 s, and nothing it restores may hold text the write boundary would strip | `IMPORTFUZZ_RUN=1` (required), `IMPORTFUZZ_SEED`, `IMPORTFUZZ_ROUNDS` |
| `ZZUndoRoundTripProbeTests` | `undo_ai_change` after random assistant updates to tasks and one-off events, with a person's edit in between half the time: what the update moved comes back, what the person changed stays, a second undo writes nothing, and an undo only succeeds or refuses in plain words | `UNDOFUZZ_RUN=1` (required), `UNDOFUZZ_SEED`, `UNDOFUZZ_ROUNDS` |
| `ZZTwoWritersContentionProbeTests` | two services on one on-disk database, as the app and the MCP host are two processes on one file, writing and reading at the same time (updates, long batch creates, preferences, exports): no write may fail with a busy error, none may be lost, and `integrity_check` must stay `ok` | `CONTENTION_RUN=1` (required), `CONTENTION_ROUNDS`, `CONTENTION_SHARED=1` (one service, as a baseline) |
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

## Benchmarks

The wall-clock benchmarks are skipped unless `LORVEX_BENCH=1` is set, so an
ordinary run, which runs suites in parallel, never fails on a slow median. Run
them on an otherwise idle Mac; the numbers are from a debug build.

| Suite | Measures | Command |
|---|---|---|
| `StoreLatencyBenchmarks` | the Mac `AppStore` and iOS `MobileStore` over an on-disk store of two sizes (about 130 tasks, and 4,400 tasks with a year of habit history and 1,000 events): first and warm refresh, a task completion, and the longest main-actor stall during each; `macRefreshSteps` times each step of the Mac refresh alone. Prints `[BENCH]` lines and asserts nothing | `LORVEX_BENCH=1 script/verify_swift.sh --filter StoreLatencyBenchmarks` |
| `PerformanceBenchmarks.swift` | guardrails with a threshold each: `AppStore.refresh` over a seeded in-memory store, the widget projector, export, MCP dispatch, Spotlight documents | `LORVEX_BENCH=1 script/verify_swift.sh --filter benchmark` |
| core `LorvexBenchmarks` | the core's reads, writes, search, and sync apply at 1,000 and 10,000 tasks | `cd core && LORVEX_BENCH=1 swift test -j 4 --filter LorvexBenchmarks` |
| `ResponsivenessTests` (iOS UI tests) | in the simulator, over the sample day with the stress content: launch time to a responsive first frame (XCTest's launch metric), and the late frames and long stretches of main-thread work while flinging each main screen, switching tabs, opening a task, and opening capture | `script/ios_sim_responsiveness.sh --optimized <outdir> [test …]` |

The app drives each interaction itself and measures it: with the DEBUG
launch argument `-lorvexFrameProbe <scenario>:<label>`,
`DebugInteractionDriver` waits three seconds after the launch route has drawn,
then scrolls the tallest list, switches tabs, pushes a task, or presents
capture, while `DebugFrameProbe` measures; the script collects each run's line
into `frames.txt`. The UI tests only launch and wait, because an XCUITest
element lookup snapshots the app's accessibility tree on its main thread,
which the probe would count as the app's own stutter; XCTest's own scroll
metric reports no hitch numbers in the simulator.

The probe reports two measures. Late frames (`hitches`, `hitch_ms`,
`worst_ms`) are the gaps between display-link callbacks beyond one refresh
interval; a frame is late when the main thread or the render server was busy,
and the simulator's render server draws on the Mac, so its share does not
predict a phone's. Busy main thread (`busy_ms`, `long_busy`,
`long_busy_over_ms`, `worst_busy_ms`) times each stretch of main-thread work
between two waits for events; a stretch longer than one refresh interval held
a frame back whatever the render server did, so it is the measure of the
app's own code. `--optimized` builds with the Swift optimizer on, into its own
derived data folder; without it the app is a debug build, whose views run
several times slower than a tester's. The simulator runs at 60 Hz on the
Mac's processor, so its numbers rank screens against each other rather than
predict a phone's.

To see what that main-thread work is, launch the installed app with a test's
arguments through `xcrun simctl launch`, then record it with
`xcrun xctrace record --device <udid> --attach Lorvex --instrument "Time Profiler"
--instrument "View Body (Legacy)" --time-limit 20s --output <file>.trace`.
Attach by the display name `Lorvex`; the process id and the executable name
are not found. Attached this way the stacks are symbolicated, and
`xctrace export --xpath` with the `time-profile` and `swiftui-body-interval`
schemas gives each main-thread sample and each view body with its time, so a
window can be cut to one interaction. The SwiftUI template records nothing in
the simulator, because its Hitches instrument is not supported there.
`sample <pid>` is not a substitute: in two of four runs it reported an idle
process while the probe in the same launch measured the interaction.

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
- **MCP tool choice.** `script/mcp_tool_choice_eval.py` measures whether an
  assistant that sees only the tool catalog picks the right tool. `prepare`
  starts the SwiftPM-built host on a disposable database and writes the server
  instructions, the catalog as a client reads it, and 52 user requests
  (`script/mcp_tool_choice_scenarios.json`, each with its accepted tools); a
  fresh sub-agent that may read only those files answers with the calls it would
  make; `check` scores the answers and validates every proposed call's
  arguments against the tool's input schema. On 2026-10-13 Haiku 5.5 and Sonnet
  5.5 each got an accepted tool for all 50 requests (after widening one
  scenario to the two equivalent ways to skip one occurrence) with no schema
  violation in 185 calls; after `undo_ai_change` was added, Haiku 5.5 chose it,
  after a lookup, for both "take back" requests added to the 52. Re-run it after
  adding or rewording a tool; a doubt the assistant names is two descriptions to
  tell apart.
- **MCP assistant sessions.** `script/mcp_assistant_session.py` has an
  assistant carry out whole requests with the real server, which the tool
  choice check cannot show: how many calls a request takes, how large each
  result is, and where the assistant was unsure. `seed <dir>` writes one
  fictional person's week into a new store through the MCP tools (the
  SwiftPM-built host on a disposable database); `copy` gives each request its
  own copy; `brief <dir> <request>` prints the instructions for a fresh
  sub-agent that may use only the script's `instructions`, `tools`, `schema`
  and `call` commands on that store, and must return its reply to the person
  and a frank list of what got in its way; `summary <dir>` reads the store's
  call log. The seven requests are in
  `script/mcp_assistant_session_requests.json`, each with what a good result
  includes. Read the reply against the store's final state, not only the
  notes: the first run's largest finding was a reply that claimed four tasks
  had left Today when they had not. Run it after changing the server
  instructions, a tool's result, or a rule an assistant has to know.
- **Committed sweeps.** `MCPResponseFencingSweepTests`,
  `MCPExtremeIntegerArgumentTests`, `BackupWholeStoreRoundTripTests` (every
  table is declared backed up or local, and a restore is lossless apart from
  clocks and some timestamps), and `TitleFieldFitTests`.

## Housekeeping

A full test run leaves empty preference files named `<Suite>.<uuid>.plist` in
`~/Library/Preferences`, because a test's own `UserDefaults` suite cannot erase
its file. Delete them with `script/clean_test_defaults.py` (`--dry-run` counts
first); it removes only the files of the suites the tests name, never another
project's.

## Headless visual review

Rebuild before capturing and delete old capture folders, so nothing stale is
mistaken for current behavior. None of these channels opens a window,
activates an app, or needs Simulator.app. Shut simulators down afterward.

### macOS tour

From `apps/apple`, run `swift build --product LorvexApple` followed by
`./.build/debug/LorvexApple --ui-preview -uiPreviewSearchScene -uiPreviewPlannedDay`
to exercise the regular Mac window with a seeded, in-memory store. The check
switches workspaces during toolbar animations, checks each search prompt and
its absence on other pages, then drives ⌘F, text entry, and Escape.

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
- window: `-uiPreviewWindowSize 1000x600`, the smallest the main window goes;
  Today puts its schedule beside the column from about 1120 wide.

`LORVEX_TOUR_LAST_STOP=<stop>` ends the tour once that stop is captured, for a
quick look at the first few stops (`today`, `today-suggestion`, `today-event`
open the tour).

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

`event-detail-zone` and `event-edit-zone` show a visual-only recurring event:
Monday at 23:30 in New York, displayed Tuesday at 13:30 in Tokyo. They check
that the repeat summary names Monday and explains the source clock. The edit
fixture is for presentation checks, not saving; no event is persisted.
`event-detail-custom` and `event-edit-custom` exercise a longer month-end
pattern, including negative month days, matching weekdays and positions,
the week start, and an occurrence limit. Use a large text size and Chinese
to check wrapping and ordinal wording. These are also visual-only fixtures.
`event-detail-fold` and `event-edit-fold` show a positive half-hour crossing
the New York fall-back: 01:45 GMT-4 to 01:15 GMT-5. Check both endpoint offsets
and the editor's valid state, including at large text sizes. These are
visual-only too; they do not create or edit a real event.
`event-edit-optional-end` and `event-edit-with-end` check the Add end time and
clear-end controls in the native editor. Check the latter at a large text size
to ensure its end picker and clear button both fit. These are visual-only.

Environment: `LORVEX_SIM_UDID` and `LORVEX_SIM_DEVICE` pick the device (pass
the UDID when two simulators share a name), `LORVEX_SIM_EXTRA_ARGS` carries
launch arguments, `LORVEX_SIM_SETTLE` sets the wait before a capture (raise it
for the stress seed or scrolling), `LORVEX_SIM_FRESH=1` erases first,
`LORVEX_SIM_DISPLAY` names the display to capture on a device with more than
one, and `LORVEX_SIM_INCREASE_CONTRAST=enabled` turns on Increase Contrast,
which is device state that survives shutdown.

#### iPhone Duo

The Duo simulator (`LORVEX_SIM_DEVICE="iPhone Duo"`, iOS 27.1 or later) has
two built-in displays. `simctl io` names the outer one `primary` (466 × 678
points) and the inner one `primary-1` (669 × 951 points). The device boots
folded, with the outer display live and the inner one black. A plain
`simctl io screenshot` fails on it, so the capture script names `primary`
there unless `LORVEX_SIM_DISPLAY` says otherwise.

What can be driven headlessly, and what cannot (Xcode 27.2):

- Folding and unfolding cannot. Nothing in `simctl`, `devicectl` or XCTest
  sets the hinge; the only control is the hinge slider in Xcode's Device Hub.
  Turning a display off with `simctl io … screenConfig` does not move the
  app to the other one. The inner display, the half-open posture and its
  reserved regions are therefore checked by hand.
- Rotation can: `xcrun devicectl device orientation set --device <udid>
  landscapeLeft`, or the app's own `-lorvexPreviewOrientation landscape`.
- Window size can: `xcrun devicectl device appResize start --device <udid>
  --preferred-size <width>x<height>` moves the frontmost app to a resizable
  display until interrupted, `appResize set` changes the size without a
  relaunch, and `simctl io <udid> screenshot --display=resizable` captures
  it.

On the outer display the system draws the status items, the toolbar items
and the tab bar in one column on the trailing edge (the leading edge in
landscape), and the safe area excludes that column. A horizontal scroll view
still draws its content beneath the column, so a paged strip needs a clip.

After each boot the simulator's wallpaper processes and the host's Spotlight
indexing load the machine for a minute or two. A capture taken then can show
the screen before the sample data or the deep link applied (an empty Today,
or Today where another tab was asked for). Use `LORVEX_SIM_SETTLE=9` or more
on this device and look at each capture before trusting it.

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

### Accessibility audit

`script/ios_sim_accessibility_audit.sh <outdir> [light|dark] [screen …]` runs
XCTest's `performAccessibilityAudit` on the iPhone app's screens over the
sample day, through the `AccessibilityAuditTests` UI test. It writes
`findings-<appearance>.txt`, one line per finding, and a screenshot of each
screen; the test's header lists the fields and the screen names. Seventeen
screens take about five minutes. `LORVEX_AUDIT_TEXT_SIZE` launches the app at
a text size, for example `UICTContentSizeCategoryAccessibilityXL`.

The audit reports and never fails: each finding is judged beside the
screenshot of its screen.
`uv run script/ax_audit_contrast.py <findings file> <screenshot directory>`
measures every contrast finding on its capture and prints the ratios, lowest
first. Normal text needs 4.5:1; large text (18 pt, or 14 pt bold) needs 3:1.

How the findings read on this app:

- **Contrast.** Most findings are the platform's own styles: secondary text
  (3.3–4.0:1 measured), accent-colored text on white (3.5:1) and inside a
  tinted bordered button (2.6–3.0:1), placeholders, and disabled controls.
  The app adopts those as the system draws them, and the system darkens them
  when a person turns on Increase Contrast. A finding counts where the app
  chose both colors, such as a label on a fill of its own
  (`docs/design/DESIGN_SYSTEM.md` §1). The audit checks an element only
  when it stands alone: a colored word inside a combined row is not measured.
- **Dynamic Type.** At the default text size the audit reports "partially
  unsupported" for nearly every text (128 findings on seventeen screens).
  These are false: the text uses text styles and grows. The run that counts
  is one at an accessibility size, read from its captures. What it still
  reports there is navigation bar titles and bar buttons, which the system
  caps and shows enlarged through the Large Content Viewer.
- **Text clipped.** "May be clipped at larger Dynamic Type sizes" is a
  prediction, not an observation. The large-size captures decide it.
- **Hit region.** A control under 44 pt in either dimension. Controls whose
  size is their meaning, such as a short event on a time grid, are exempt.
- **Hidden controls.** XCUITest's tree includes children of elements hidden
  from VoiceOver, so a control hidden with `.accessibilityHidden(true)` is
  audited as if it showed. The calendar's Today button, while the day shown
  is today, is one.
- **Under the tab bar.** Text scrolled beneath the glass tab bar is measured
  through the glass.

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

## Calendar time regression coverage

EventKit instant preservation: `EventKitInstantBridgeTests` runs unsaved real
EKEvents through both platform mappers and the in-memory ingest/timeline path.
`EventKitOccurrenceInstantTests` covers repeated-hour readings, half-hour
transitions, privacy tiers, cache reconciliation and monotonic upserts;
`ProviderOccurrenceMigrationTests` upgrades a version-4 fixture with existing
provider data and task links. These tests never save to the system calendar.

MCP calendar time context: `MCPCalendarTimeContextTests` drives a real in-memory
registry through compact/full/explicit-field reads, repeated-hour pagination,
source-coordinate round trips, cross-day scoped edits, recurrence gaps, empty
window timezone changes, and full/busy provider links. `CalendarTimelineOrderingTests`
checks every ordering of mixed floating/projected fold clocks, binary-title and
stable-id ties, and missing-time placement. These use no managed user database.

Human calendar editing: `CalendarSourceTimingPreservationTests` exercises both
stores and all occurrence scopes with spring-gap clocks, end-only edits,
cancel/restore, floating zones, and concurrent field changes.
`CalendarOptionalEndTests` checks adding/removing ends (including overnight
spans), moving points, and resize undo/redo through real in-memory writes.
Core `CalendarInheritedStartTests` verifies that inherited-gap permission cannot
be reused for a different date, clock, zone, or all-day state.
