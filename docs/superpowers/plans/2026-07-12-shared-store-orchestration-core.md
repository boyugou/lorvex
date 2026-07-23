# Shared Store Orchestration Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is a PHASED refactor: each phase is independently gated and pushed; do NOT big-bang.

**Goal:** Collapse the duplicated macOS `AppStore` / iOS `MobileStore` refresh-and-reload orchestration into one platform-neutral functional core that emits typed plans, with two thin platform shells that interpret those plans — eliminating the "fixed on one platform, still broken on the other" defect class without merging the two stores.

**Architecture:** Functional core / imperative shell. A pure, `@MainActor`, platform-agnostic layer in `LorvexCore` owns the *decisions* (refresh single-flight sequencing + waiter resumption, dirty-domain→reload plan, draft-reconciliation policy). Each platform store keeps its own UI state and stays the *effect interpreter* (macOS: 9 domain storages, Spotlight, menu bar, detached windows, AppKit; iOS: `MobileHomeSnapshot`, Watch mirror, scene lifecycle, background-push deadline). The core has no platform types and no I/O; the shells hold no sequencing logic. The reload executor is made compile-time-exhaustive over `InboundReloadDomain` so a new domain can't be silently unhandled on one platform.

**Tech Stack:** Swift 6 strict concurrency, `@MainActor`, Swift Testing / XCTest (match the suite being extended), SwiftPM. No new dependencies. The shared core lives in `LorvexCore` alongside the existing `InboundReloadScope` (already the shared kind→domain classifier both stores import).

## Global Constraints

- Swift 6 strict concurrency; every shared type is `@MainActor` (both stores are `@MainActor ObservableObject`/`@Observable`). Copied verbatim from `apps/apple/CLAUDE.md`.
- Deployment floor macOS 15 / iOS 18 / visionOS 2 / watchOS 11 (from `Package.swift`); no `@available` needed for anything used here.
- `LorvexCore` is platform-neutral: **no `import AppKit`, no `import UIKit`, no `import SwiftUI`** in the shared-core files. Enforced by the widget-neutrality precedent.
- One concern per file; 800-line hard cap (`script/verify_hotspots.py`). New core files are small value types — nowhere near the cap.
- English only for code/comments/commits; no email addresses anywhere. Commit trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Describe the current state, not the history, in docstrings (no "previously/was"). Docstrings self-contained.
- **Behavior-preserving:** every phase must be a pure refactor — no user-visible behavior change except the one intended fix (Phase 2 makes mobile's reload exhaustive, which only ADDS reloads that were latently missing; verify no surface reloads that shouldn't).
- Gate before every push: `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` exit 0 (verify `MAC_GATE=0`) + `./script/verify_mobile_release_link.sh` (iOS; exit 78 = skip-no-SDK). These touch iOS-compiled code, so the iOS link matters.

## Current State (verified in source at HEAD 63e995787)

- **macOS `AppStore.refresh()`** (`Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift:312-323`): `guard !isRefreshing else { refreshPending = true; return }; isRefreshing = true; defer { isRefreshing = false }; repeat { refreshPending = false; await performRefresh() } while refreshPending`. Returns `Void`. No waiters.
- **iOS `MobileStore.refresh()`** (`Sources/LorvexMobile/MobileStoreRuntimeActions.swift:21-43`): same loop shape but returns `MobileCloudSyncLifecycleResult`, and a coalesced caller `await withCheckedContinuation { refreshWaiters.append($0) }`; after the loop it resumes every waiter with the final `result`, then `await applyPendingCloudSyncModeIfNeeded()`.
- **Reload executors** (`AppStoreInboundReload.swift`, `MobileStoreInboundReload.swift`): each hand-writes an `if domains.contains(.x)` ladder. macOS covers all 8 `InboundReloadDomain` cases; **mobile covers 6** (no `.tasks`, no `.diagnostics` branch). `InboundReloadScope.domains(for:)` (`Sources/LorvexCore/Services/InboundReloadScope.swift`) is ALREADY an exhaustive `switch` over `EntityKind` (no `default`) — the kind→domain map is shared and safe; only the per-platform domain→execution is drift-prone.
- **Draft reconciliation** (daily-review): macOS `dailyReviewDraftMatchesLoaded`; iOS inline `dailyReviewDraft == MobileDailyReviewDraft(review: dailyReview)`. Same rule ("adopt loaded value only when the draft is clean"), two spellings.
- **Single-flight scope differs:** macOS's *cloud-sync-cycle* single-flight uses a file-private `Set<ObjectIdentifier>` (`AppStoreRuntimeLifecycle.swift:8`) to dedup across multiple window-scoped `AppStore` instances sharing one DB; iOS uses instance flags. The *refresh* single-flight (this plan's Phase 1) is per-instance on both — safe to share; the cross-instance cycle lock is OUT OF SCOPE (Phase 1 does not touch it).

---

## Phase 1 — Generic refresh single-flight state machine (additive, no behavior change)

Extract the coalescing single-flight loop (guard → set-pending → repeat-until-drained → resume-waiters) into one generic `@MainActor` value type in `LorvexCore`. Both stores keep their own `performRefresh` bodies; they only delegate the *sequencing*.

### Task 1: `RefreshSingleFlight<Result>` value type + full unit tests

**Files:**
- Create: `apps/apple/Sources/LorvexCore/Support/RefreshSingleFlight.swift`
- Test: `apps/apple/Tests/LorvexCoreServiceTests/RefreshSingleFlightTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor public struct RefreshSingleFlight<Result: Sendable> {
    public init(initialResult: Result)
    public var isRunning: Bool { get }
    /// Runs `body` under single-flight coalescing. A call arriving while a run is
    /// in flight registers as a waiter and returns the in-flight run's final
    /// result; it does not start a parallel body. After the loop drains
    /// (`pending` cleared with no new trigger), `afterDrain` runs once, then every
    /// waiter is resumed with the final result. `body` is rerun once per pending
    /// trigger set during its own execution.
    public mutating func run(
      body: () async -> Result,
      afterDrain: () async -> Void = {}
    ) async -> Result
  }
  ```
  (Internally holds `isRunning: Bool`, `pending: Bool`, `waiters: [CheckedContinuation<Result, Never>]`, `lastResult: Result`. Because it's `@MainActor` and the flag reads/writes happen with no intervening suspension before the guard, the coalescing is race-free — same argument the current inline code documents.)

- [ ] **Step 1: Write the failing test** — coalescing collapses concurrent triggers to one rerun and all callers get the final result.

```swift
import Testing
@testable import LorvexCore

@MainActor
struct RefreshSingleFlightTests {
  @Test func secondCallWhileRunningCoalescesToOneRerunAndSharesFinalResult() async {
    final class Box { var runs = 0; var triggerOnce = true }
    let box = Box()
    var flight = RefreshSingleFlight<Int>(initialResult: -1)
    // First run: on its first body execution, fire a re-entrant trigger by calling
    // run() again (which, because isRunning, only sets pending + waits).
    async let second: Int = {
      // Give the first run a turn to set isRunning before we call.
      await Task.yield()
      return await flight.run(body: { box.runs += 1; return box.runs })
    }()
    let first = await flight.run(body: {
      box.runs += 1
      if box.triggerOnce { box.triggerOnce = false; await Task.yield() }
      return box.runs
    })
    let secondResult = await second
    #expect(box.runs == 2)            // one initial body + exactly one rerun
    #expect(first == secondResult)     // coalesced caller got the final result
  }
}
```

- [ ] **Step 2: Run test to verify it fails** — `cd apps/apple && swift test --filter RefreshSingleFlightTests` → FAIL ("cannot find 'RefreshSingleFlight'").

- [ ] **Step 3: Write minimal implementation** in `RefreshSingleFlight.swift`:

```swift
import Foundation

/// Single-flight coalescing for an async refresh body, shared by the macOS and
/// iOS stores. A trigger arriving mid-run sets a pending flag (not a parallel
/// body); the in-flight run reruns once after it finishes, so a write that
/// committed after the run's reads began is still observed. Coalesced callers
/// await the in-flight run and receive its final result. `@MainActor`, so the
/// flag reads/writes are ordered without an intervening suspension.
@MainActor
public struct RefreshSingleFlight<Result: Sendable> {
  private var isRunning = false
  private var pending = false
  private var waiters: [CheckedContinuation<Result, Never>] = []
  private var lastResult: Result

  public init(initialResult: Result) { self.lastResult = initialResult }

  public var isRunning_: Bool { isRunning }

  public mutating func run(
    body: () async -> Result,
    afterDrain: () async -> Void = {}
  ) async -> Result {
    if isRunning {
      pending = true
      return await withCheckedContinuation { waiters.append($0) }
    }
    isRunning = true
    var result = lastResult
    repeat {
      pending = false
      result = await body()
    } while pending
    lastResult = result
    isRunning = false
    let resumeList = waiters
    waiters = []
    await afterDrain()
    for w in resumeList { w.resume(returning: result) }
    return result
  }
}
```
(NOTE to implementer: `isRunning` is exposed as `isRunning_` only if a shell needs to read it; prefer not to expose it. Delete the accessor if unused — YAGNI. Also reconcile the mutating-struct-in-a-class-property ergonomics: if storing this in an `@MainActor` class works better as a small `final class`, use a class — decide during Task 2 and keep the tests.)

- [ ] **Step 4: Run test to verify it passes** — `swift test --filter RefreshSingleFlightTests` → PASS. Add two more tests: (a) a lone call runs the body exactly once and returns its result; (b) `afterDrain` runs exactly once after the loop and before waiters resume (assert ordering via a recorder). Run all three → PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/apple/Sources/LorvexCore/Support/RefreshSingleFlight.swift \
        apps/apple/Tests/LorvexCoreServiceTests/RefreshSingleFlightTests.swift
git commit -m "Add shared RefreshSingleFlight coalescing state machine"
```

### Task 2: Route macOS `AppStore.refresh()` through `RefreshSingleFlight<Void>`

**Files:** Modify `Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift:312-323`; the `isRefreshing`/`refreshPending` stored properties move into a `RefreshSingleFlight<Void>` held by the store (find their declarations — likely `AppStore` state file — and replace).

**Interfaces:** Consumes `RefreshSingleFlight<Void>` from Task 1.

- [ ] **Step 1:** Confirm the existing macOS refresh-coalescing tests (search `Tests/LorvexAppleTests` for `RefreshCoalesce`/`refreshPending`/`InboundSyncReload` — e.g. `AppStoreRefreshCoalesce*`, `AppStoreInboundSyncReloadTests`) and run them GREEN first: `swift test --filter AppStoreRefreshCoalesce` (adapt to real names). These are the regression guard.
- [ ] **Step 2:** Replace the inline loop body with `await refreshFlight.run(body: { await performRefresh() })`, where `refreshFlight` is a new `RefreshSingleFlight<Void>` property (initialResult: ()). Remove `isRefreshing`/`refreshPending` stored props and any external readers (grep `isRefreshing`/`refreshPending` in `LorvexApple`; the cloud-sync-cycle path at `AppStoreRuntimeLifecycle.swift:236,257,313` reads `isRefreshing`/sets `refreshPending` — route those through the flight's API: add `var isRefreshing: Bool { refreshFlight.isRunning_ }` and, for the inbound "set pending" at :257/:314, expose a `requestRerun()` on the flight OR keep the mid-refresh rerun by having that path call into the flight — DESIGN THIS EXPLICITLY: the inbound-apply "set refreshPending" is the concurrency-M3 rerun; it must still work. Add a `RefreshSingleFlight.requestRerun()` mutating method that sets `pending = true` and unit-test it in Task 1 if you add it.)
- [ ] **Step 3:** Run the macOS refresh + inbound-reload + concurrency-M3 tests → PASS (no behavior change). `swift test --filter AppStore`.
- [ ] **Step 4:** Commit `Route macOS refresh through the shared single-flight`.

### Task 3: Route iOS `MobileStore.refresh()` through `RefreshSingleFlight<MobileCloudSyncLifecycleResult>`

**Files:** Modify `Sources/LorvexMobile/MobileStoreRuntimeActions.swift:21-43`; remove `refreshWaiters`, `isRefreshing`, `refreshPending`.

**Interfaces:** Consumes `RefreshSingleFlight` (with `Result = MobileCloudSyncLifecycleResult`, `afterDrain = { await applyPendingCloudSyncModeIfNeeded() }`).

- [ ] **Step 1:** Run existing mobile refresh/coalesce tests GREEN first (search `MobileStoreRefresh`/`MobileStoreInboundSelectiveReload`/overlap tests): `swift test --filter MobileStore`.
- [ ] **Step 2:** Replace the loop with `await refreshFlight.run(body: { await performRefresh() }, afterDrain: { await applyPendingCloudSyncModeIfNeeded() })`. The waiter machinery is now inside the flight, so delete `refreshWaiters` and its resume loop. Keep `@discardableResult` and the `MobileCloudSyncLifecycleResult` return.
- [ ] **Step 3:** Run mobile refresh + background-fetch-completion tests → PASS (waiters still resumed with final result; `applyPendingCloudSyncModeIfNeeded` still runs after the loop).
- [ ] **Step 4:** Commit `Route iOS refresh through the shared single-flight`.

### Phase 1 gate & push
- [ ] Run `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` (MAC_GATE=0) + `./script/verify_mobile_release_link.sh`. On green, `git checkout -- apps/apple/core/Package.resolved`, delete any `.DS_Store`, push. **Net:** the coalescing sequencing (waiters, rerun, drain) now has ONE definition + full unit tests; both stores keep their own bodies.

---

## Phase 2 — Exhaustive reload executor (fixes the HIGH-1b latent drift hazard)

Convert both stores' `if domains.contains(.x)` reload ladders into a `switch` over `InboundReloadDomain.allCases` (or a protocol with a per-domain requirement) so every domain is EXPLICITLY handled on each platform — a new domain becomes a compile error, not a silent stale surface. Execution stays per-platform (correct: `.tasks` legitimately reloads a workspace pool on macOS and is a no-op on mobile).

### Task 4: `InboundReloadDomain` conformances + a per-platform exhaustive dispatch

**Files:**
- Modify: `Sources/LorvexCore/Services/InboundReloadScope.swift` — make `InboundReloadDomain: CaseIterable` (if not already) and add a doc note that each platform executor MUST handle every case.
- Modify: `Sources/LorvexApple/Stores/AppStoreInboundReload.swift`, `Sources/LorvexMobile/MobileStoreInboundReload.swift`.
- Test: extend `AppStoreInboundSelectiveReloadTests`, `MobileStoreInboundSelectiveReloadTests`.

**Interfaces:** Consumes `InboundReloadDomain.allCases`.

- [ ] **Step 1: Write the failing test** — a mobile inbound apply of ONLY `.diagnostics` reloads the mobile diagnostics/changelog surface (currently silently dropped). Assert via a call-counting core that the diagnostics read fires. (If mobile genuinely has no diagnostics surface, the test instead asserts the `.diagnostics` case is an EXPLICIT documented no-op — encoded so it can't be an accidental omission. Determine which during Step 1 by reading the mobile store's state.)
- [ ] **Step 2:** Run → FAIL (or, for the no-op variant, first make the switch exhaustive so the compiler forces the case).
- [ ] **Step 3:** Rewrite each `reloadInboundDomains(_:)` to iterate/switch exhaustively: `for domain in InboundReloadDomain.allCases where domains.contains(domain) { switch domain { case .today: …; case .tasks: …; case .diagnostics: …; … } }` with NO `default`. Each platform fills every case with either a real reload or `break // documented: no store-published surface for this domain on <platform>`. macOS keeps its existing 8 handlers; mobile fills its missing `.tasks` (no-op with the verified rationale — Tasks tab self-loads) and `.diagnostics` (reload the activity/recent-logs surface if one exists, else documented no-op).
- [ ] **Step 4:** Run both stores' selective-reload suites → PASS. Add a test asserting `InboundReloadDomain.allCases` is fully handled (compile-time via the no-default switch; plus a runtime smoke that each domain triggers its expected read on a call-counting core).
- [ ] **Step 5:** Commit `Make inbound reload executors exhaustive over InboundReloadDomain`.

### Phase 2 gate & push
- [ ] Full gate (macOS + iOS). **Net:** the "conservative superset never misses a surface" contract is now compile-enforced per platform. Closes the HIGH-1b drift class.

---

## Phase 3 — Pure draft-reconciliation policy (small, additive)

### Task 5: `DraftReconciliation` pure helper

**Files:** Create `apps/apple/Sources/LorvexCore/Support/DraftReconciliation.swift`; Test `.../DraftReconciliationTests.swift`; then modify both stores' daily-review reload to call it.

**Interfaces:**
```swift
public enum DraftReconciliation {
  /// Adopt `loaded` into the editor only when the current draft still equals the
  /// previously-loaded value (i.e. the user has no unsaved edits). Returns the
  /// value the editor should now hold.
  public static func adopt<T: Equatable>(loaded: T, currentDraft: T, previousLoaded: T) -> T {
    currentDraft == previousLoaded ? loaded : currentDraft
  }
}
```
- [ ] TDD: failing test (clean draft adopts loaded; dirty draft keeps current) → implement → pass → replace the two inline spellings (`dailyReviewDraftMatchesLoaded` on macOS, the inline `==` on iOS) with `DraftReconciliation.adopt(...)`, keeping each store's own draft types → run both stores' review-draft tests → commit → Phase gate + push.

---

## Phase 4 — ReloadPlan value (dirty domains → domains-to-reload + derived effects)

### Task 6: Fold the derived-effect decisions into a pure `ReloadPlan`

`InboundReloadScope` already maps kinds→domains and exposes `recomputesReminders(_:)` / `republishesWidget(_:)`. Promote these into one `ReloadPlan` value computed once from the dirty domains, so both shells consume `plan.reloadDomains`, `plan.recomputesReminders`, `plan.republishesWidget`, `plan.recomputesBadge` instead of re-deriving. Pure; unit-tested exhaustively. Shells still EXECUTE per platform.

- [ ] TDD the `ReloadPlan.from(domains:)` value (assert the derived flags per domain set) → migrate both `reloadInboundDomains` to consume `ReloadPlan` → run both suites → gate + push. **Net:** the derived-effect fan-out decision is defined once.

---

## Phase 5 — Contract tests + doc

### Task 7: Cross-shell contract tests + update the architecture doc

- [ ] Add a contract-test file asserting both shells honor the same invariants for a representative dirty-domain set (e.g. a `.task` apply recomputes reminders + republishes widget on both; a `.habits`-only apply does not recompute the badge on either). These pin the shared policy without requiring identical execution code.
- [ ] Update `docs/architecture/MULTI_STORE_COHERENCE.md`: document the functional-core/imperative-shell split, the `RefreshSingleFlight`/`ReloadPlan`/`DraftReconciliation` shared components, and the exhaustive-executor rule. Remove any now-stale "share the vocabulary, not the implementation" framing where it implied the executors could drift.
- [ ] Gate + push.

---

## Explicit non-goals (do NOT do)
- Do NOT merge `AppStore` and `MobileStore` into one type or a capability-flag engine. They remain separate UI-state owners (9 domain storages vs `MobileHomeSnapshot`; Spotlight/menu-bar/detached-windows vs Watch/scene/background-push are genuinely different effects).
- Do NOT touch the cross-instance cloud-sync-cycle `Set<ObjectIdentifier>` lock (macOS multi-window) — its scope is genuinely per-process and out of Phase 1's per-instance single-flight.
- Do NOT change `CloudSyncEngineCoordinator`, the sync apply pipeline, reminder scheduler, or widget snapshot writer — already shared, working, out of scope.
- Do NOT change any user-visible behavior except Phase 2's added mobile reloads (which only fix latently-missing refreshes).

## Sequencing & risk
- Land this AFTER the in-flight correctness wave (CRITICAL unbounded-INTERVAL crash, EventKit series fix, sync-emit gaps) — those are release blockers; this is a high-value ARCH refactor, not a blocker.
- Each phase is behavior-preserving (except Phase 2's additive reloads), independently gated (macOS+iOS) and pushed, so a regression is isolated to one small phase.
- Phase 1 (additive core + delegation) and Phase 3/4 (pure helpers) carry the least risk; Phase 2 carries the one intended behavior change (do the mobile-surface reasoning carefully and verify no over-reload).

## Self-review notes (author)
- Spec coverage: single-flight (P1), exhaustive executor / HIGH-1b (P2), draft policy (P3), reload plan / derived effects (P4), contract tests + doc (P5) — every element of the agreed design has a phase. ✓
- The one under-specified spot is Task 2's handling of the concurrency-M3 mid-refresh rerun (`refreshPending = true` from the inbound-apply path): flagged inline as requiring an explicit `requestRerun()` on the flight — the implementer must add + test it, not paper over it. This is called out, not left as a placeholder.
- Type consistency: `RefreshSingleFlight<Result>.run(body:afterDrain:)` used identically in Tasks 2 & 3; `ReloadPlan`/`DraftReconciliation`/`InboundReloadDomain.allCases` names consistent across phases.
</content>
</invoke>
