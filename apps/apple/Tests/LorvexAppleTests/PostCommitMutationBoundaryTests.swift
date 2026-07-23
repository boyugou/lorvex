import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

private struct PostCommitRefreshProbeError: Error {}

@MainActor
@Test("macOS preserves a committed mutation when derived reconciliation fails")
func macOSPostCommitReconciliationIsDiagnosticOnly() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)

  let result = await store.performCanonicalMutation { "committed-id" }
  await store.reconcileAfterCommittedMutation(source: "test.macos.post_commit") {
    throw PostCommitRefreshProbeError()
  }

  #expect(result == "committed-id")
  #expect(store.errorMessage == nil)
  let logs = try await core.loadRecentLogs(
    limit: 10, offset: 0, since: nil, levels: nil,
    sources: ["error_log"], redact: false)
  #expect(logs.entries.contains { $0.origin == "test.macos.post_commit" })
}

@MainActor
@Test("macOS inline create stays successful when its loaded workspace cannot reload")
func macOSInlineCreateWorkspaceFailureIsDiagnosticOnly() async throws {
  let preview = try await makeSeededInMemoryCore()
  let core = StubFocusCoreService(preview: preview)
  let store = AppStore(core: core)
  await store.loadTaskWorkspace()
  #expect(store.taskWorkspaceHasLoaded)

  core.listTasksError = .unsupportedOperation("Injected workspace read failure.")
  await store.createTaskInInbox(title: "Durable post-commit capture")

  #expect(store.errorMessage == nil)
  let page = try await preview.listTasks(
    status: "all", listID: nil, priority: nil, text: "Durable post-commit capture",
    limit: 10, offset: 0)
  #expect(page.tasks.contains { $0.title == "Durable post-commit capture" })
  let logs = try await preview.loadRecentLogs(
    limit: 10, offset: 0, since: nil, levels: nil,
    sources: ["error_log"], redact: false)
  #expect(logs.entries.contains { $0.origin == "macos.task.create_in_inbox.reconcile" })
}

@MainActor
@Test("iPhone preserves a committed mutation when derived reconciliation fails")
func mobilePostCommitReconciliationIsDiagnosticOnly() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)

  let result = await store.performCanonicalMutation { "committed-id" }
  await store.reconcileAfterCommittedMutation(source: "test.ios.post_commit") {
    throw PostCommitRefreshProbeError()
  }

  #expect(result == "committed-id")
  #expect(store.errorMessage == nil)
  let logs = try await core.loadRecentLogs(
    limit: 10, offset: 0, since: nil, levels: nil,
    sources: ["error_log"], redact: false)
  #expect(logs.entries.contains { $0.origin == "test.ios.post_commit" })
}
