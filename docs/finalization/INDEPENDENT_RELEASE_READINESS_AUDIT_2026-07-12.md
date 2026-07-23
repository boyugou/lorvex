# Independent Apple Release-Readiness Audit — 2026-07-12

## Scope and baseline

- Audited source tree: `655420259457141cf6ef1315862e5a8b27c0a5a9`.
- Current `origin/main` at the end of the review was `a5acd94c34fbf4705d7692b3a66de3ff096b3e23`; its file tree is byte-identical to the audited tree (`git diff 655420259..a5acd94c` is empty).
- Scope: Apple Swift implementation only, with emphasis on macOS-first App Store release plus the iPhone/iPad/watchOS graph, SQLite/schema/migrations, CloudKit convergence, MCP, localization, packaging/signing gates, source-level UI/UX correctness, dead code, and documentation drift.
- Explicitly excluded at the owner's request: CUA, manual UI clicking, and new screenshot/visual inspection work.
- This review made no product-code changes. It adds only this independent audit record.

## Executive verdict

The repository is substantially more mature than it was at the start of finalization, but it is **not yet correct to claim that the Apple implementation is fully finalized or ready to submit**.

For a macOS-first release, the remaining code-level blockers are:

1. the CloudKit over-window recovery protocol does not actually replace a stale local snapshot and can still resurrect deleted data;
2. the zone-epoch mechanism is not initialized on the normal zone-creation path and cannot preserve a fleet-wide monotonic epoch across zone deletion;
3. the advertised full verification gate is not reproducible from a clean checkout because runtime localization tests execute before `.xcstrings` compilation.

The actual Mac App Store submission additionally remains blocked, intentionally, by the unarmed schema freeze and the owner/account-side work: final App IDs/capabilities/profiles, production CloudKit schema promotion, a truly signed archive/package, Xcode's archive privacy report, public support/privacy URLs, App Store Connect metadata, and upload/TestFlight evidence.

For the complete Apple ecosystem, iOS/watchOS has one additional deterministic blocker: the Watch app bundle identifier is not a child of the companion iOS app's bundle identifier.

## Release-blocking findings

### B1 — HIGH — “Snapshot re-enrollment” is a union pull, not an authoritative snapshot replacement

Relevant code:

- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+ZoneEpoch.swift:128-185`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator.swift:241-374`
- `apps/apple/Sources/LorvexCore/Services/SwiftLorvexCoreService+EnvelopeSync.swift:209+`
- tests at `apps/apple/Tests/LorvexAppleTests/CloudSyncEngineCoordinatorTests.swift:2181-2440`

The S-5 recovery path calls itself “snapshot re-enrollment,” but it performs only these operations:

1. mark existing pending outbox rows permanently failed;
2. clear the CloudKit change-token checkpoint;
3. record/adopt an epoch and clear `reseed_required`;
4. pull every record currently present in the zone from a nil token;
5. union/LWW-apply those returned envelopes into the existing local database.

It never removes a live local row merely because that row is absent from the current zone. Once a CloudKit delete and the corresponding SQLite tombstone have aged out, absence produces no inbound envelope.

Minimal failing sequence:

1. Devices A and B both contain entity X.
2. B remains offline past the recovery horizon.
3. A deletes X; the fleet eventually GC's the deletion knowledge.
4. The custom zone is rebuilt, so its historical delete is absent.
5. B reconnects with stale live X. The pre-push gate quarantines an old pending upsert, if one exists, and performs a nil-token pull.
6. Because the zone contains no X envelope, X remains live in B's SQLite database.
7. The user later edits X on B. The edit receives a fresh dominating HLC and creates a new outbox upsert.
8. B is now enrolled at the current epoch with a fresh checkpoint, so the new upsert pushes normally and resurrects X on the fleet.

There is an even simpler arm: when B has no pending outbox row and no `reseed_required` marker, `adoptZoneTruthBeforePushIfOverWindow` returns early. The ordinary pull refreshes the checkpoint without ever reconciling local absence; a later edit resurrects X in the same way.

The existing S-5 tests use a fake backend that does not store real SQLite entity rows. They prove only “the stale outbox was not pushed during this cycle”; they never assert that stale X disappeared locally or run a second post-adoption edit/push cycle.

This is a protocol correctness blocker before CloudKit production promotion and schema freeze.

#### Recommended terminal design

Given that there are no released users, the safest pre-1.0 choice is one of the following, made explicit and tested end-to-end:

1. **Recommended for v1: permanent compact deletion knowledge.** Keep `sync_tombstones` as the permanent compact death ledger (`entity_type`, `entity_id`, death HLC and redirect metadata) and always backfill it into a recreated zone. Do not rely on absence as a delete. This has unbounded-but-compact metadata growth and the simplest convergence proof.
2. **Alternative: a true authoritative snapshot replacement protocol.** After a complete zone inventory has been fetched and validated, construct a staged local sync snapshot, preserve explicitly local-only state, reconcile every syncable entity/edge absent from the inventory, then atomically replace or commit it. Unknown future types and incomplete pages must fail closed. A nil-token union pull is not sufficient.

If bounded tombstones remain a product requirement, option 2 is required. The current hybrid should not be frozen.

### B2 — HIGH — Zone epoch is neither initialized normally nor monotonic across zone deletion

Relevant code:

- `apps/apple/Sources/LorvexCloudSync/CloudSyncRecordPushing.swift:56-87`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator.swift:162-180`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncEngineCoordinator+ZoneEpoch.swift:53-99`
- `apps/apple/Sources/LorvexCloudSync/CloudSyncZoneEpochRecord.swift:4-38`
- the only `advanceAndEnrollZoneEpoch` call is in `CloudSyncEngineCoordinator+AccountGate.swift:429`

There are two independent gaps.

First, the normal `ensureZone()` path creates only the `CKRecordZone` and a local “zone ensured” marker. It does not create the `LorvexZoneEpoch` record and does not enroll the local database. Because every normal cycle calls `ensureZone()` before fetching, a fresh account usually gets a zone successfully and never enters the later `zoneNotFound` recovery arm that advances the epoch. The S-5 tests hide this by manually preloading epoch values.

Second, `LorvexZoneEpoch` is stored inside the custom zone it is meant to version. Deleting that zone deletes the epoch record too. Reconstruction calculates a new value only from the recreating device's local enrollment floor. That is not fleet-wide monotonicity: a stale device enrolled at 3 can recreate epoch 4 even when the deleted zone had previously reached 9. Other devices enrolled at 9 then see `4 > 9 == false`, so the 90–365 day rebuild signal fails. Network/decode errors are also often collapsed to nil with `try?`, which fails open.

#### Recommended terminal design

- Prefer an opaque random **zone generation token** over a numeric counter. Generate it whenever a new custom zone is created; every successful complete enrollment stores the token locally. Inequality, not numerical ordering, proves that the zone was replaced.
- The zone ensure operation must also ensure a valid generation record and expose whether it created/recovered the generation.
- A generation fetch or parse failure must stop the destructive/adoption decision, not become nil and proceed.
- If a numeric monotonic epoch is retained, its authority must live outside the deletable custom zone, for example in account-scoped metadata that survives that zone's deletion.
- A generation mismatch still needs the real snapshot/death-ledger solution in B1; detecting a rebuild without reconciling absent local rows is not enough.

Because the CloudKit schema is not yet promoted and there are no users, now is the cheapest point to simplify this protocol rather than preserve the current epoch contract.

### B3 — HIGH — `verify_all.sh` is not reproducible from a clean checkout

Relevant code:

- `apps/apple/script/verify_all.sh:35-46`
- `apps/apple/script/build_and_run.sh:161-177`
- `docs/finalization/FINDINGS_BACKLOG.md:86-95`

On a genuinely fresh worktree, `verify_all.sh` executes `swift test` before any script compiles the `.xcstrings` catalogs into `.lproj` resources. The compilation currently happens only much later as a packaging side effect in `build_and_run.sh`.

Observed from a fresh exact checkout:

- 31 localization tests ran;
- 11 failed;
- `.lproj` lookup returned nil;
- English/Russian plural tests received raw fallback strings;
- singular import summaries rendered as “1 imported records.”

After manually compiling the catalogs, the same localization tests pass, the app suite passes, and the core suite passes. A later full-gate green result therefore proves a warmed build directory, not a reproducible clean gate.

The permanent fix is to make catalog compilation an explicit pre-test phase, preferably through a reusable script/build plugin or a purpose-built compiled fixture bundle. It must run before `swift test` in both local and CI gates. A static `.xcstrings` verifier is valuable but cannot replace runtime resource-loading tests.

### B4 — HIGH, iOS/watchOS only — Watch bundle identifier violates the companion-prefix topology

Current identifiers:

- iOS host: `com.lorvex.apple.mobile`
- Watch app: `com.lorvex.apple.watch`
- Watch complication: `com.lorvex.apple.watch.complication`
- `WKCompanionAppBundleIdentifier`: `com.lorvex.apple.mobile`

Sources:

- `apps/apple/Config/XcodeGen/project.yml:605,638`
- `apps/apple/Config/LorvexWatchApp-Info.plist:47-48`
- `apps/apple/script/app_metadata.sh:17-18,24-27`

The companion key itself is correct, but the Watch app ID is not based on/prefixed by the iOS host ID. Apple requires the iOS bundle ID to be the prefix of a companion Watch app bundle ID. A source-consistent set would be similar to:

```text
com.lorvex.apple.mobile
com.lorvex.apple.mobile.watchkitapp
com.lorvex.apple.mobile.watchkitapp.widgets
```

This previously manifested as a Watch install failure stating that the app bundle identifier did not start with its parent app's identifier plus a dot. Current metadata verifiers check that the repo agrees with itself but do not check this parent/child topology.

This does not block a macOS-only first release. It does block shipping the embedded Watch app in the future iPhone IPA and should be fixed before final App IDs/profiles are created.

Apple references:

- [TN3157 — Updating a watchOS project for SwiftUI and WidgetKit](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)
- [`WKCompanionAppBundleIdentifier`](https://developer.apple.com/documentation/BundleResources/Information-Property-List/WKCompanionAppBundleIdentifier)

### B5 — External submission blockers remain intentionally open

The source tree cannot prove the following owner/account-side facts, and the current release scripts correctly refuse a normal App Store archive while the schema freeze remains dormant:

- `schema/migration_policy.json` is still `launched: false`; the first public RC must run and commit `apps/apple/script/verify_schema_freeze.py --arm`.
- Final Apple Developer App IDs, App Group, CloudKit container capabilities, certificates, and distribution provisioning profiles have not been proven against an actual signed artifact.
- The final CloudKit schema has not been shown as promoted to Production.
- Production multi-device tests have not been shown for offline edits, account changes, zone deletion/recreation, encrypted-key reset, and helper/app concurrent writes.
- Xcode's privacy report has not been generated from the exact signed archive and reconciled with App Store Connect answers.
- Screenshots, localized store metadata, age rating, DSA status, support information, and App Review notes remain owner work.
- A Transporter/App Store Connect validation or TestFlight install has not been shown.

The configured public URLs currently return 404 when fetched anonymously:

- `https://github.com/boyugou/lorvex`
- `https://github.com/boyugou/lorvex/issues`
- `https://github.com/boyugou/lorvex/blob/main/PRIVACY.md`

They are embedded in `PrivacyPolicySummary.swift`, `FeedbackGitHubLink.swift`, `PRIVACY_SUMMARY.md`, and the App Store metadata. Either make those routes publicly accessible or replace them with stable public pages before submission. Apple requires a privacy-policy URL for macOS/iOS and an actionable support route.

Apple references:

- [Deploying an iCloud container's schema](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)
- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [App Store Connect app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [App Review Guidelines, developer information](https://developer.apple.com/app-store/review/guidelines/)

## High-priority correctness and finalization findings

### H1 — MED-HIGH — Factory-reset cutover still has a stale identity/HLC race

Relevant code:

- `apps/apple/Sources/LorvexCore/Services/SwiftLorvexCoreService+WriteSurface.swift:55-106`
- `apps/apple/Sources/LorvexCore/Services/SwiftLorvexCoreService+EnvelopeSync.swift:216-218`

The previously reported sequential stale-state bug was fixed: `writeState()` now forces a `store()` check before consulting its epoch-keyed cache. Marker corruption, the marker/delete open ABA, and inode replacement were also fixed.

A narrower cross-process window remains:

1. `withWrite` obtains `(deviceId, clock)` from `writeState()` against database generation N.
2. A different process performs factory reset and creates generation N+1.
3. The separate `store()` call in `withWrite` notices the cutover and opens the fresh database.
4. `runWriteAttempt` writes into the fresh database using generation N's device ID/HLC.

The inbound-apply funnel has the same split. Existing tests reset first and then write; they do not install a barrier between `writeState()` and the second `store()`.

The clean fix is a single cutover lease/transaction funnel that resolves `(store, storage epoch, device identity, HLC)` together and holds the shared reset lock through the transaction, or verifies the epoch immediately before commit and retries the entire operation on change.

### H2 — MEDIUM — Native non-destructive import is still check-then-write for most aggregates

The owner has decided that import is non-destructive and that there will be no whole-DB authoritative restore mode. Tasks correctly enforce skip-if-existing inside their transactional import path. Lists, tags, habits, calendar events, memories, daily reviews, current focus, and focus schedules generally perform:

1. a separate `importTargetExists` read;
2. a later import write that mints a fresh dominating HLC.

Relevant code:

- `LorvexDataImporter+DomainApply.swift:10-21,59-71,95-108,169-180`
- `LorvexDataImporter+ContentApply.swift:11-31,50-74,146-157,180-193`
- `SwiftLorvexCoreService+ImportPresence.swift:41-79`

An MCP write, CloudKit apply, or second app process can create/update the target between those two transactions. The stale backup then wins with a fresh HLC and propagates fleet-wide. The task path demonstrates the right design: every aggregate needs an atomic “insert only if no live target and policy permits the tombstone” operation that returns imported/skipped.

`task_calendar_event_links` is imported without a presence/tombstone guard and can reintroduce a relationship that was deliberately removed. The non-destructive policy should explicitly define tombstoned IDs/edges as skipped, not resurrected, unless the user chooses a separate explicit recreate operation.

### H3 — MEDIUM — MCP/Siri sync diagnostics knowingly publish false state

Relevant code:

- `SwiftLorvexCoreService+Diagnostics.swift:12-24,89-100`
- `LorvexMCPHost/CoreBridgeClientStatus.swift:5-29`
- `LorvexMCPHost/SystemSyncStatusToolCatalog.swift:4-12`
- `LorvexSystemIntents/ReadLorvexSyncStatusIntent.swift:9-17`

The core comment correctly admits that the DB-only helper cannot observe app-runtime CloudKit mode, account state, last success, or last error. It nevertheless returns `backend: "disabled"`, nil last-sync/error, and the MCP adapter exposes this as both the configured and effective backend. It also drops the core's `reseedRequired` field from the MCP response.

Consequences:

- an assistant can tell the user that sync is disabled while the app is actively using CloudKit;
- a critical `reseed_required` recovery state is hidden;
- Siri/Shortcuts can speak the same false backend;
- the tool description over-promises “backend state” and “checkpoints.”

Best design: persist a small, atomic, app-group runtime-health snapshot written by the live app coordinator and read by MCP/App Intents. Until that exists, publish `runtime_backend: unknown/unobservable` rather than `disabled`, narrow the tool description, and always include `reseed_required`.

### H4 — MEDIUM — First schema-freeze arm does not prove the shipping Apple embed matches canonical schema state

`verify_schema_freeze.py --arm` now correctly runs the canonical migration-ladder validation even on first arm. It still validates the Apple lock and canonical lock separately and does not require their equality before writing the permanent frozen baseline. The tests currently allow different Apple and canonical SHA values and freeze the Apple value.

The full `verify_all.sh` runs `verify_schema_embed.sh`, so a disciplined full-gate release catches current drift. The archive scripts themselves call only the armed-freeze gate. The irreversible `--arm` operation should be self-contained and fail before mutation unless:

- canonical schema/lock/migrations are internally valid;
- the Apple embedded schema, lock, and migration files are byte-identical to the canonical Apple authority;
- the policy to be written corresponds to those exact shipping bytes.

### H5 — MEDIUM — MAS profile verifier can accept a Developer ID profile

The earlier MAS profile gaps were mostly fixed: app/helper/widget profiles are mandatory for `--package`; device-limited and `get-task-allow` development profiles are rejected; CloudKit environment is cross-checked.

`verify_mas_provisioning.py` still accepts an `OSX` profile with `ProvisionsAllDevices=true` when other fields match. That is characteristic of Developer ID distribution, not Mac App Store distribution. The verifier should reject `ProvisionsAllDevices`, validate the distribution class/certificate relationship, and test an actual negative fixture.

Apple reference: [TN3125 — Inside code signing: Provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

### H6 — MEDIUM — Final exported IPA is only partially audited

`archive_ios.sh` now unzips the final, re-signed IPA and verifies Mach-O closure, which is a material improvement. It does not recursively verify the final payload's:

- code signatures;
- signed entitlements;
- embedded provisioning profiles and their relationship to every nested bundle;
- privacy-manifest presence/content;
- final bundle/version metadata.

Archive-time/static checks do not prove the post-export artifact. Add a final-payload verifier for the host app, widget, Watch app, and complication before declaring an IPA ready.

## Architecture, MCP, CI, and maintenance findings

### A1 — MCP typed registry is a good refactor, but its frozen-contract claim is wider than its gate

Current positive state:

- 118 unique typed definitions;
- list/dispatch/idempotency derivation is unified;
- current `.read/.write` metadata and `readOnlyHint` have no observed mismatch;
- stdio smoke and the input-schema manifest pass after the localization resource precondition is satisfied.

Residual gaps:

- `verify_mcp_tool_manifest.py` intentionally locks names and structural input-schema tokens, but excludes descriptions and annotations. It therefore does not enforce the previously stated “name, description, inputSchema, annotations byte-identical” wire contract.
- `verify_mcp_tool_catalog.py` does not assert `Tool.annotations.readOnlyHint` against the typed access classification.
- every definition uses the same default response-fencing policy. Actual field ownership remains the global `SecurityFencing.userContentKeys`/array-key allowlist; adding a differently named user-authored response field can silently miss fencing.
- `ToolDefinition.Idempotency.none` is unreachable for writes under the only write factory.

Before the public MCP contract freezes, lock the full canonical `tools/list` JSON, including annotations and descriptions if they are promised stable; derive or test read-only annotations; and move toward typed response-field/taint descriptors rather than a global string-key convention.

### A2 — Error taxonomy migration remains incomplete

There are still approximately 85 shipping references to `LorvexCoreError.unsupportedOperation`. Some are genuine unsupported capabilities, but others encode validation, not-found, conflict, or internal invariant failures. Examples include missing review dates and absent daily reviews.

`ToolRegistry.errorCode` maps typed errors but sends the remaining `unsupportedOperation` cases as generic `tool_error`. This makes MCP clients parse prose or lose recoverability. Complete the typed-case migration before declaring the MCP error wire stable; keep `unsupportedOperation` only for actual unsupported capabilities.

### A3 — CI can pass with an incomplete Apple SDK matrix

The workflow currently runs only by `workflow_dispatch`, which is an intentional cost decision, not a code defect. Two correctness gaps remain:

- one OR-pattern grep for `ios 26|macos 26|xros 26|watchos 26` proves only that at least one SDK is present;
- iOS and visionOS release-link exit 78 is converted to a green notice.

Assert each required SDK independently. A required iOS release build must not soft-skip. If visionOS is optional for the macOS-first milestone, model it explicitly as optional rather than allowing environment absence to masquerade as a fully covered matrix.

### A4 — Xcode Release builds still emit module dependency warnings

Unsigned Release device builds succeed, but Xcode 26.6 reports that `LorvexStore` is missing dependencies on `LorvexDomain`/`GRDB` and `LorvexWorkflow` is missing dependencies on `LorvexStore`/`LorvexDomain`/`GRDB`.

Those dependencies already exist in `core/Package.swift`; the likely issue is the way multiple SwiftPM products are promoted/embedded as dynamic frameworks by the generated Xcode project. This is not a current linker blocker, but it is build-graph debt that can become stricter under a later Xcode. Resolve it or add a narrowly justified warning baseline before calling Release warning-clean.

### A5 — The shipping compile is not warning-clean

`swift build -c release -Xswiftc -warnings-as-errors` fails at:

- `SwiftLorvexCoreService+EnvelopeSync.swift:141` — unused result of `write` in `clearReseedRequired`.

Test compilation also reports actor-isolation and vacuous-test warnings, including synchronous calls to MainActor-isolated widget helpers and a nonoptional value compared with nil. These do not currently break normal Swift 6.3 builds, but they contradict documentation that says there are zero actor-isolation warnings and create future compiler-upgrade debt.

### A6 — Hotspot/dead-code residue is small but real

The hotspot verifier passes, with three explicitly grandfathered core files. `CalendarNormalization.swift` is 796/800 lines, so its next small edit will require a split.

Confirmed low-risk unused declarations include:

- `SettingsChrome.swift:299` — `sqliteDatabaseFile`, left from the removed external-DB picker;
- `AppStoreAppleSurfacePublishing.swift:188` — the unused macOS `replenishReminderWindow` counterpart;
- `AppSettingsRuntimeState.swift:10` — unused instance property `isSandboxed`;
- `SettingsView.swift:14` — unused `detailVerticalPadding`;
- `CalendarWorkspaceView.swift:28` — unused `moveTargetLists`;
- `LorvexMCPHost/CoreBridgeClient.swift:16` — stored `databasePath` after it has already been used to construct the service.

A Periphery scan produces many SwiftUI/AppIntent/protocol false positives, so it should be introduced with a reviewed baseline and dynamic-entrypoint exclusions rather than bulk deletion.

### A7 — Low/forward-compat sync robustness gaps

- A full-resync backfill that encounters an unknown/non-syncable tombstone silently continues without increasing `skipped`; `sync_tombstones.entity_type` has no schema CHECK. A downgraded/future or corrupt row can therefore be reported as a clean pass and clear `reseed_required`.
- The core correctly sets a durable marker for known poison rows, but `CloudSyncEngineCoordinator.runFullResyncBackfill` discards the structured report and returns true for any nonthrowing partial pass. Recovery eventually retries, but the immediate coordinator status is falsely successful.

Treat every tombstone that cannot be re-emitted as a reported partial/fail-closed condition, and preserve the report through the coordinator health surface.

## Documentation drift

The current documentation cannot be treated as release instructions without reconciliation. Confirmed examples:

- root `README.md` still calls the Apple/Tauri schema shared and byte-identical;
- `apps/apple/docs/release.md:27-28` still requires migration byte-copies into both runtimes;
- `apps/apple/docs/release.md:36-46` and `DISTRIBUTION.md` describe a universal DMG, `--host-arch`, and a `*-universal.dmg`, while `package_dmg.sh` is arm64-only and emits `*-arm64.dmg`;
- the same release doc describes old Apple-ID/password notarization variables, while the script requires `NOTARY_KEYCHAIN_PROFILE` and `APPLE_TEAM_ID`;
- `apps/apple/docs/reference/FEATURES.md` still says a security-scoped database bookmark is shipped and the MCP host can use a bookmark environment variable, although the external-DB picker/bookmark contract was removed;
- that features doc still advertises cross-import with Tauri despite the owner decision to make Apple exports native/semantic and AI-mediated across platforms;
- `mcp_stdio_smoke.py` still says the surface has 116 tools; it now has 118;
- release/account docs still list the invalid Watch identifiers;
- finalization docs simultaneously claim all headless code is complete and record the 11-failure clean-checkout localization workaround;
- a “zero actor-isolation warnings” claim conflicts with fresh compiler output.

`verify_user_docs.py` passes because it does not cover these semantic contracts. Release docs should be derived/tested against `app_metadata.sh`, actual script usage output, schema policy, and the typed MCP registry where practical.

## Data-schema observations

The current baseline has many strong properties:

- SQLite `STRICT` tables, checks, generated recurrence bounds, explicit foreign keys, and FTS/trigram support;
- 19 sync entity kinds are structurally checked against the CloudKit envelope schema;
- a fresh schema load passes `PRAGMA integrity_check` and foreign-key checking;
- no exact duplicate indexes or obviously unindexed foreign-key child columns were found;
- production baseline replay on every open was removed, so future destructive numbered migrations are no longer undone;
- checksum mismatch on a healthy readable database now fails closed rather than quarantining it as empty data.

Two possible redundant-prefix indexes should be benchmarked before freeze rather than deleted by inspection:

- `idx_calendar_events_start_date(start_date)` is a prefix of `idx_calendar_events_range_start(start_date, end_date, start_time)`;
- `idx_provider_events_start(start_date)` is a prefix of `idx_provider_events_range_start(start_date, end_date)`.

The narrower forms can still be cheaper for specific queries, so query-plan/performance evidence should decide.

The principal schema/protocol decision is B1: either retain compact deletion knowledge permanently or implement a real authoritative snapshot reconciliation. That choice matters much more than removing small index redundancy.

## Confirmed improvements and positive evidence

The following previously reported issues are fixed on the audited tree and should not be reopened without new evidence:

- App Store CloudKit environment entitlements are scalar `"Production"`, not arrays.
- repo-hygiene verification follows the delegated CI/gate structure and passes.
- release scripts no longer run destructive `git checkout -- core/Package.resolved` cleanup.
- the generated Xcode project uses a complete committed package-resolution lock with automatic resolution disabled.
- MAS packaging requires app, MCP helper, and widget profiles; it rejects device-limited and `get-task-allow` development profiles and checks CloudKit environment.
- the schema-freeze gate blocks normal MAS/iOS release packaging while unarmed.
- iPhone/iPad orientation declarations are present and the earlier Xcode validation warning is gone.
- final IPA verification now includes post-export Mach-O closure.
- full-resync poison rows set a durable `reseed_required` marker.
- normal generation marker ABA, corrupt-marker fallback, and inode replacement handling were fixed.
- production baseline schema replay and checksum-mismatch quarantine were fixed.
- nil/unconfirmable CloudKit account adoption now fails closed.
- the old raw Apple interchange/HLC path was removed in favor of typed native import/export.
- the MCP registry currently contains 118 unique typed tools with coherent access/idempotency wiring.
- static localization verification passes for 975 app keys and 12 shipped non-source languages; runtime tests pass after the missing compilation precondition is supplied.
- no shipping `try!`, `as!`, `TODO`, or `FIXME` instances were found; preview-only `fatalError` calls are isolated to preview seed failure.
- deployment floors are consistently macOS 15, iOS 18, visionOS 2, and watchOS 11; the generated Xcode project excludes `x86_64`, matching the Apple-Silicon-first decision.
- Xcode 26.6 / SDK 26.5 satisfies Apple's current 2026 upload toolchain floor.

Apple's current submission and toolchain references:

- [Submitting apps to the App Store](https://developer.apple.com/app-store/submitting/)
- [Xcode support and current SDK matrix](https://developer.apple.com/support/xcode)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

## Recommended order of work

1. Freeze further CloudKit production/schema decisions and resolve B1+B2 as one protocol-design pass, with real two-database/zone-inventory tests and a second post-recovery edit cycle.
2. Make the clean-checkout localization/test gate deterministic; re-run the entire gate in a disposable clone with no `.build`/`dist` state.
3. Close the factory-reset identity race and atomic non-destructive import races before the schema freeze is armed.
4. Make sync diagnostics honest and include `reseed_required`; finish the MCP contract/error gates intended to remain stable after 1.0.
5. Make `verify_schema_freeze.py --arm` self-contained and strict; then arm only after all prelaunch schema/protocol changes land.
6. For macOS: finish the three-profile MAS verifier, generate a fully signed app/package, promote CloudKit to Production, generate the archive privacy report, publish valid support/privacy URLs, and validate through App Store Connect.
7. Before the iPhone/watch release: change the Watch identifier topology, create matching final App IDs/profiles, and add post-export recursive IPA signature/profile/entitlement/privacy verification.
8. Reconcile the release/current-state docs from executable metadata and delete or clearly label historical reference documents that describe removed contracts.

## Go/no-go summary

| Target | Current decision | What changes it to GO |
|---|---|---|
| macOS local development build | GO for continued testing | Existing warmed build/package path is functional; this is not a submission claim. |
| macOS first App Store release | NO-GO | Resolve CloudKit B1/B2, clean gate B3, then arm schema and complete signed production/account/store evidence. |
| iPhone/iPad TestFlight/App Store with embedded Watch app | NO-GO | All macOS/shared items plus Watch ID B4 and final IPA distribution audit. |
| Claim that all code-fixable finalization is complete | NO | Re-run an independent clean gate after the blockers above land and update the docs to the resulting evidence. |
