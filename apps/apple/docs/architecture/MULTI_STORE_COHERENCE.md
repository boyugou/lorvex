# Multi-store coherence over one database

Several stores observe the same logical Lorvex database at once. This document
states the invariant they must satisfy and the mechanism each configuration
uses to satisfy it.

## The invariant

> Any two stores observing the same logical database converge to the same
> persisted state within bounded time, with no user action required.

Caches (per-store snapshots of `today`, list details, workspace pages, calendar
timelines) are permitted — but every cache must be invalidatable by a shared
signal. A store that can only be brought current by a manual refresh violates
the invariant.

"Persisted state" is the SQLite contents; transient per-window UI state
(selection, scroll position, unsaved drafts) is deliberately per-store and
never converges. Unsaved drafts always win over a refresh: convergence must
not clobber typing in progress.

## Configurations and their signals

| Configuration | Writer the store can't see directly | Convergence signal |
|---|---|---|
| Main-window `AppStore` | MCP host or interactive-widget intent (separate process) | Darwin notification `DatabaseChangeSignal` posted after the committed operation → in-app relay → `refresh()`; `NSApplication.didBecomeActive` refresh as the return-to-app backstop |
| Main-window `AppStore` | Detached window or App Intent / notification action (same process) | Every ordinary committed core write schedules one coalesced in-process `DatabaseChangeSignal` → `refresh()` |
| Detached task/list window `AppStore`s | Main window, sibling detached window, MCP host, widget, or CloudKit apply | The same unified `DatabaseChangeSignal` (coalesced local commits + Darwin relay + one origin-tagged notification after a successful inbound apply) → reload of just the shown task/list, coalesced single-flight and deferred while a task draft is unsaved. The sticky window resumes a deferred reload as soon as the draft becomes clean, so it does not require another write or focus change. One observer is registered on window open and cancelled on close, so the window converges live without its own CloudKit stack (`cloudSyncMode == .off`, no coordinator). Reload on the window regaining key (`controlActiveState == .key`) is the backstop for signals missed while unfocused; `replaceCore` propagates database swaps to open detached stores |
| Other devices (CloudKit `.live`) | Remote peers | CloudKit push → `.lorvexCloudKitRemoteChange` → `refresh()` (which runs a sync cycle); inbound apply bumps `local_change_seq` |

All signals are keyed, directly or indirectly, on a committed write:
`SwiftLorvexCoreService.withWrite` bumps `local_change_seq` in the same
transaction as every mutation. The app's core funnel schedules its local signal
only after commit; the MCP host does the same for Darwin, while each widget
action emits one Darwin signal only after its owned mutation returns. A refresh
is therefore always able to observe the state that triggered it. The local
relay throttles a transaction burst to one notification per 50 ms and both the
main and detached stores add a single-flight trailing-rerun guard, preventing a
multi-write action from turning into a reload storm.

Inbound CloudKit apply uses a separate transaction funnel, so the main
`AppStore` emits one in-process signal only when the completed cycle reports a
non-empty `appliedEntityTypes` set. The signal is tagged with that store as its
origin: detached stores reload, while the already-reconciled main store ignores
its own notification. Failed, outbound-only, decoded-but-skipped, and empty
follow-up cycles emit no signal, so invalidation cannot form a refresh/sync loop.

## Selective inbound reload shares one domain map

After a CloudKit apply, the originating platform store reloads only the surfaces
the applied entity kinds can affect; detached windows independently reload their
single shown entity through the signal above. Both platform stores derive their
domain set from one shared source, so they stay coherent instead of drifting
through parallel hand-maintained logic:

- **Kind → domain.** `InboundReloadScope.domains(for:)` maps the applied
  `EntityKind`s to the `InboundReloadDomain`s whose surfaces read them
  (conservative: any signal that can't be cleanly bounded returns `nil` → full
  reload). Both executors consume the same map.
- **Domain → executor.** Each store dispatches the domains through a `switch`
  with no `default` over `InboundReloadDomain.allCases`, so a new domain is a
  compile-time obligation on both platforms — it can't be silently unhandled on
  one. A platform with no store-published surface for a domain takes a documented
  no-op (iOS `.tasks` self-loads its tab; iOS `.diagnostics` loads on demand),
  never an accidental omission.
- **Derived surfaces.** The badge, reminders, and widget are recomputed from
  whichever primary domains reloaded, gated on the shared predicates
  `InboundReloadScope.recomputesBadge`, `.recomputesReminders`, and
  `.republishesWidget`. "Which domains drive the badge" therefore lives in one
  place; a change updates both stores at once.

The result: a given inbound change drives the same reloaded surfaces and the
same derived effects on macOS and iOS, modulo each platform's documented no-ops.
`InboundReloadExecutorCoverageTests` locks both the switch exhaustiveness and the
shared derived-surface predicates.

## What is deliberately separate

- Each window owns its `AppStore` so per-window navigation, selection, and
  drafts never interfere across windows. Sharing one `core` service instance
  per process is correct and required (one connection pool, one HLC clock per
  process surface).
- Explicit in-memory fixtures used by tests and SwiftUI previews run one fake
  per store with no shared backing; they make no coherence promise and are not
  reachable from the product runtime environment.
