import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple
@testable import LorvexMobile

// Phase 2: each store's inbound-reload executor dispatches `InboundReloadDomain`
// through a `switch` with no `default`, so "handle every domain" is a compile-time
// obligation — a new case can't be silently unhandled on one platform. That
// exhaustiveness is enforced by the compiler; these runtime smokes pin the
// filled-in per-domain behavior:
//   - every domain that owns a store-published surface reloads exactly that
//     surface when reloaded alone, and
//   - the two mobile documented no-ops (`.tasks`, `.diagnostics`) reload no
//     primary surface, while macOS `.diagnostics` (whose full refresh loads
//     diagnostics) still reloads it.
//
// The end-to-end multi-domain gating (which surfaces reload for a given applied
// kind set, and that untouched surfaces stay put) is the regression guard in
// `AppStoreInboundSelectiveReloadTests` / `MobileStoreInboundSelectiveReloadTests`.

@Suite("Inbound reload executor per-domain coverage")
struct InboundReloadExecutorCoverageTests {

  @Test("InboundReloadDomain exposes the full vocabulary both executors switch over")
  func inboundReloadDomainVocabularyIsComplete() {
    // The real exhaustiveness guarantee is the no-`default` switch in each executor
    // (a new case fails to compile). This pins the vocabulary so an accidental
    // add/remove of a domain surfaces here too.
    #expect(InboundReloadDomain.allCases.count == 9)
    #expect(
      Set(InboundReloadDomain.allCases) == [
        .today, .tasks, .lists, .calendar, .focus, .reviews, .habits, .memory, .diagnostics,
      ])
  }

  @Test("both executors gate the derived surfaces on the shared InboundReloadScope predicates")
  func bothExecutorsShareDerivedSurfacePredicates() throws {
    // Coherence invariant (see docs/architecture/MULTI_STORE_COHERENCE.md): a given
    // inbound change must drive the same derived-surface set — badge, reminders,
    // widget — on both platforms. Each store maps applied kinds through the shared
    // `InboundReloadScope.domains(for:)` and gates each derived surface on the
    // shared predicate, so "which domains drive the badge" lives in exactly one
    // place. This source-scan locks that neither store hand-rolls its own
    // derived-surface predicate (the drift `recomputesBadge` was extracted to close).
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexAppleTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .appending(path: "Sources")
    let appExecutor = try String(
      contentsOf: sources.appending(path: "LorvexApple/Stores/AppStoreInboundReload.swift"),
      encoding: .utf8)
    let mobileExecutor = try String(
      contentsOf: sources.appending(path: "LorvexMobile/MobileStoreInboundReload.swift"),
      encoding: .utf8)

    for executor in [appExecutor, mobileExecutor] {
      #expect(executor.contains("InboundReloadScope.recomputesBadge(domains)"))
      #expect(executor.contains("InboundReloadScope.recomputesReminders(domains)"))
      #expect(executor.contains("InboundReloadScope.republishesWidget(domains)"))
    }
  }

  // MARK: Mobile

  @MainActor
  @Test("mobile executor: each surface-owning domain reloads its surface when reloaded alone")
  func mobileExecutorReloadsEachSurfaceDomain() async throws {
    do {
      let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
      await makeStore(core: core).reloadInboundDomains([.today])
      #expect(core.loadTodayCallCount == 1)
    }
    do {
      let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
      await makeStore(core: core).reloadInboundDomains([.lists])
      #expect(core.loadListsCallCount == 1)
    }
    do {
      let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
      await makeStore(core: core).reloadInboundDomains([.calendar])
      #expect(core.loadCalendarTimelineCallCount == 1)
      #expect(core.scheduledTasksCallCount == 1)
    }
    do {
      let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
      await makeStore(core: core).reloadInboundDomains([.focus])
      #expect(core.loadCurrentFocusCallCount == 1)
    }
    do {
      let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
      await makeStore(core: core).reloadInboundDomains([.habits])
      #expect(core.loadHabitsCallCount == 1)
    }
  }

  @MainActor
  @Test("mobile executor: .tasks is a documented no-op — no store-published task pool read")
  func mobileExecutorTasksDomainIsNoOp() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    await makeStore(core: core).reloadInboundDomains([.tasks])

    // The mobile Tasks tab self-loads via `.task(id:)`; there is no store-published
    // task pool to reload, so the task-list read never fires and no other primary
    // surface reloads. (The task-derived reminders/badge still recompute via the
    // derived fan-out — exercised by the selective-reload suite, not asserted here.)
    #expect(core.listTasksCallCount == 0)
    #expect(core.loadTodayCallCount == 0)
    #expect(core.loadListsCallCount == 0)
    #expect(core.loadHabitsCallCount == 0)
    #expect(core.loadCalendarTimelineCallCount == 0)
  }

  @MainActor
  @Test("mobile executor: .diagnostics is a documented no-op — reloads nothing")
  func mobileExecutorDiagnosticsDomainIsNoOp() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    await makeStore(core: core).reloadInboundDomains([.diagnostics])

    // Mobile diagnostics is loaded on demand when Settings appears, not by the
    // refresh fan-out, so a selective inbound reload reads nothing at all.
    #expect(core.loadRuntimeDiagnosticsCallCount == 0)
    #expect(core.loadTodayCallCount == 0)
    #expect(core.loadListsCallCount == 0)
    #expect(core.loadHabitsCallCount == 0)
    #expect(core.loadCalendarTimelineCallCount == 0)
  }

  // MARK: macOS

  @MainActor
  @Test("macOS executor: .diagnostics reloads the diagnostics surface (unlike mobile)")
  func appStoreExecutorDiagnosticsDomainReloads() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    await AppStore(core: core).performSelectiveInboundReload([.diagnostics])

    // macOS's full refresh loads runtime diagnostics, so its selective executor
    // reloads it too — and in isolation, nothing else.
    #expect(core.loadRuntimeDiagnosticsCallCount == 1)
    #expect(core.loadTodayCallCount == 0)
    #expect(core.loadListsCallCount == 0)
    #expect(core.loadHabitsCallCount == 0)
    #expect(core.loadCalendarTimelineCallCount == 0)
  }
}
