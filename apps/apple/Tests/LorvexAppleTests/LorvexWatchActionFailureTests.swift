import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

private final class FailingForwarder: LorvexWatchMutationForwarding, @unchecked Sendable {
  let error: any Error
  init(_ error: any Error) { self.error = error }
  func forward(_ mutation: LorvexWatchMutation) async throws { throw error }
}

private final class AcceptingForwarder: LorvexWatchMutationForwarding, @unchecked Sendable {
  func forward(_ mutation: LorvexWatchMutation) async throws {}
}

/// An action that fails is reported where it was taken, in words that say the
/// change did not save; a rejected action names what it was for.
@Suite("Watch action failures")
@MainActor
struct LorvexWatchActionFailureTests {
  private static let workspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private static let task = "11111111-1111-4111-8111-111111111111"
  private static let habit = "33333333-3333-4333-8333-333333333333"
  /// 2026-05-25 12:00:00 UTC.
  private static let now = Date(timeIntervalSince1970: 1_779_710_400)

  /// A store over a replica listing one task and one habit.
  private func makeStore(
    forwarder: any LorvexWatchMutationForwarding
  ) async throws -> (LorvexWatchStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watch-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let snapshot = WidgetSnapshot(
      generatedAt: LorvexDateFormatters.iso8601.string(from: Self.now),
      workspaceInstanceID: Self.workspace, localChangeSequence: 1, timezone: "UTC",
      logicalDay: "2026-05-25",
      stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 0), briefing: nil,
      tasks: [
        .init(
          id: Self.task, title: "Renew passport", status: "open", dueDate: nil, priority: 2,
          listID: nil, estimatedMinutes: nil)
      ],
      habits: [.init(id: Self.habit, name: "Water", icon: nil, completedToday: 0, target: 1)])
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: Self.workspace, snapshotData: JSONEncoder().encode(snapshot))
    let url = directory.appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    try envelope.wireData().write(to: url)
    let now = Self.now
    let store = LorvexWatchStore(snapshotURL: url, now: { now }, mutationForwarder: forwarder)
    await store.refresh()
    return (store, directory)
  }

  @Test("a failed action reads as a change that did not save, and the next refresh clears it")
  func aFailedActionIsNotALoadFailure() async throws {
    let (store, directory) = try await makeStore(
      forwarder: FailingForwarder(LorvexWatchCommandJournalError.corrupt))
    defer { try? FileManager.default.removeItem(at: directory) }

    await store.completeHabit(id: Self.habit)

    #expect(store.error != nil)
    #expect(store.errorIsFromAction)
    #expect(store.actionFailureText == LorvexWatchCalmCopy.actionFailed)

    await store.refresh()
    #expect(store.error == nil)
    #expect(!store.errorIsFromAction)
    #expect(store.actionFailureText == nil)
  }

  /// Before the iPhone has sent any copy of Today the journal has no
  /// workspace to bind a command to; the capture says to open the iPhone.
  @Test("an action before the first replica says to open the iPhone first")
  func anActionBeforeTheFirstReplicaSaysOpenTheIPhone() async throws {
    let store = LorvexWatchStore(
      snapshotUnavailable: .init(reason: .missingFile, detail: "test"),
      mutationForwarder: FailingForwarder(LorvexWatchReplicaStoreError.baselineUnavailable))
    await store.refresh()
    #expect(store.error != nil)
    #expect(store.actionFailureText == nil)

    store.captureTitle = "Call the bank"
    await store.captureTask()

    #expect(store.errorIsFromAction)
    #expect(store.actionFailureText == LorvexWatchCalmCopy.openPhoneFirst)
    #expect(store.captureTitle == "Call the bank")
  }

  @Test("a failed load is not reported as a failed action")
  func aFailedLoadIsNotAnAction() async {
    let store = LorvexWatchStore(
      snapshotUnavailable: .init(reason: .invalidJSON, detail: "test"),
      mutationForwarder: AcceptingForwarder())
    await store.refresh()

    #expect(store.error != nil)
    #expect(!store.errorIsFromAction)
    #expect(store.actionFailureText == nil)
  }

  /// A rejection usually arrives after the item has left the list (completed
  /// on the wrist, or gone on the phone); the row still names it.
  @Test("a rejected action names the task, habit, or capture it was for")
  func aRejectionNamesItsSubject() async throws {
    let (store, directory) = try await makeStore(forwarder: AcceptingForwarder())
    defer { try? FileManager.default.removeItem(at: directory) }

    await store.completeTask(id: Self.task)
    #expect(store.tasks.isEmpty)

    func rejected(_ mutation: LorvexWatchMutation) -> LorvexWatchRejectedCommand {
      LorvexWatchRejectedCommand(
        id: "c", sequence: 1, mutation: mutation, code: "not_found", reason: "")
    }
    #expect(store.subject(of: rejected(.completeTask(id: Self.task))) == "Renew passport")
    #expect(
      store.subject(of: rejected(.completeHabit(id: Self.habit, date: "2026-05-25"))) == "Water")
    #expect(store.subject(of: rejected(.captureTask(title: "Call the bank"))) == "Call the bank")
    #expect(
      store.subject(of: rejected(.cancelTask(id: "99999999-9999-4999-8999-999999999999"))) == nil)
  }

  @Test("every action has its own not-applied headline")
  func everyActionHasAHeadline() {
    let id = Self.task
    let headlines = [
      LorvexWatchMutation.completeTask(id: id), .startTask(id: id), .pauseTask(id: id),
      .deferTaskToTomorrow(id: id, plannedDate: "2026-05-26"), .cancelTask(id: id),
      .captureTask(title: "T"), .completeHabit(id: id, date: "2026-05-25"),
    ].map(LorvexWatchCalmCopy.notApplied)
    #expect(Set(headlines).count == headlines.count)
  }
}
