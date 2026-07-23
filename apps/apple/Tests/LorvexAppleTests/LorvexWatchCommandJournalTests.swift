import Foundation
import LorvexCore
@testable import LorvexWatch
import Testing

@Suite("Watch command journal")
struct LorvexWatchCommandJournalTests {
  @Test("enqueue is durable before return and restart preserves install sequence")
  func restartPreservesIdentityAndSequence() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let first = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let command1 = try await first.enqueue(
      mutation: .completeTask(id: task1),
      workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")

    let restarted = try LorvexWatchCommandJournal(fileURL: url, newInstallID: alternateInstallID)
    let restored = await restarted.allEntries()
    #expect(restored.map(\.command) == [command1])
    #expect(await restarted.installID() == watchInstallID)

    let command2 = try await restarted.enqueue(
      mutation: .cancelTask(id: task2),
      workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:01.000Z")
    #expect(command1.sequence == 1)
    #expect(command2.sequence == 2)
    #expect(command2.installID == command1.installID)
    #expect(await restarted.nextSequence() == 3)
  }

  @Test("corrupt journal fails closed without replacing bytes")
  func corruptJournalFailsClosed() throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let corrupt = Data("not a journal".utf8)
    try corrupt.write(to: url)

    #expect(throws: LorvexWatchCommandJournalError.corrupt) {
      _ = try LorvexWatchCommandJournal(fileURL: url)
    }
    #expect(try Data(contentsOf: url) == corrupt)
  }

  @Test("unacknowledged commands are never capacity-evicted")
  func unacknowledgedCommandsAreRetained() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)

    for index in 0..<128 {
      _ = try await journal.enqueue(
        mutation: .captureTask(title: "Task \(index)"),
        workspaceInstanceID: workspaceA,
        createdAt: "2026-07-16T12:00:00.000Z")
    }

    let entries = await journal.allEntries()
    #expect(entries.count == 128)
    #expect(entries.first?.command.sequence == 1)
    #expect(entries.last?.command.sequence == 128)
  }

  @Test("retryable outcome retains and blocks the FIFO head")
  func retryableOutcomeRetainsHead() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let first = try await journal.enqueue(
      mutation: .completeTask(id: task1), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")
    _ = try await journal.enqueue(
      mutation: .completeTask(id: task2), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:01.000Z")

    let retryAt = Date(timeIntervalSince1970: 200)
    let acknowledgement = try LorvexWatchCommandAck(
      command: first.wireCommand(),
      outcome: .retryable,
      code: "phone_busy",
      message: "Phone busy")
    #expect(try await journal.applyAcknowledgement(
      acknowledgement, retryAt: retryAt) == .retryable)

    #expect(await journal.nextDeliverable(at: Date(timeIntervalSince1970: 199)) == nil)
    #expect(await journal.nextDeliverable(at: retryAt)?.command.id == first.id)
    #expect(await journal.allEntries().count == 2)
  }

  @Test("applied ACK removes only the strict FIFO head")
  func appliedAckRemovesHead() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let first = try await journal.enqueue(
      mutation: .completeTask(id: task1), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")
    let second = try await journal.enqueue(
      mutation: .cancelTask(id: task2), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:01.000Z")

    let acknowledgement = try LorvexWatchCommandAck(
      command: first.wireCommand(), outcome: .applied)
    #expect(try await journal.applyAcknowledgement(
      acknowledgement, retryAt: .distantFuture) == .applied)
    #expect(await journal.allEntries().map(\.command.id) == [second.id])

    // Duplicate application ACK is idempotent and cannot consume the next row.
    #expect(try await journal.applyAcknowledgement(
      acknowledgement, retryAt: .distantFuture) == .duplicate)
    #expect(await journal.allEntries().map(\.command.id) == [second.id])
  }

  @Test("future ACK is rejected out of order")
  func futureAckIsRejected() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let first = try await journal.enqueue(
      mutation: .completeTask(id: task1), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")
    let second = try await journal.enqueue(
      mutation: .completeTask(id: task2), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:01.000Z")

    do {
      let acknowledgement = try LorvexWatchCommandAck(
        command: second.wireCommand(), outcome: .applied)
      _ = try await journal.applyAcknowledgement(
        acknowledgement, retryAt: .distantFuture)
      Issue.record("Expected an out-of-order acknowledgement error")
    } catch let error as LorvexWatchCommandJournalError {
      #expect(error == .acknowledgementOutOfOrder)
    }
    #expect(await journal.allEntries().map(\.command.id) == [first.id, second.id])
  }

  @Test("rejected command remains visible until explicit dismissal")
  func rejectedCommandIsRetained() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let command = try await journal.enqueue(
      mutation: .captureTask(title: "Keep me"), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")

    let acknowledgement = try LorvexWatchCommandAck(
      command: command.wireCommand(),
      outcome: .rejected,
      code: "validation_failed",
      message: "Task validation failed")
    #expect(try await journal.applyAcknowledgement(
      acknowledgement, retryAt: .distantFuture) == .rejected)

    let status = await journal.deliveryStatus()
    #expect(status.pendingCount == 0)
    #expect(status.rejectedCommands.map(\.id) == [command.id])
    #expect(status.rejectedCommands.map(\.code) == ["validation_failed"])
    #expect(status.rejectedCommands.map(\.reason) == ["This action is no longer valid."])
    #expect(try await journal.dismissRejected(commandID: command.id))
    #expect(await journal.allEntries().isEmpty)
  }

  @Test("unknown phone rejection message is replaced by localized Watch copy")
  func unknownRejectionUsesLocalizedFallback() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let command = try await journal.enqueue(
      mutation: .captureTask(title: "Keep localized"), workspaceInstanceID: workspaceA,
      createdAt: "2026-07-16T12:00:00.000Z")
    let acknowledgement = try LorvexWatchCommandAck(
      command: command.wireCommand(),
      outcome: .rejected,
      code: "future_policy",
      message: "Phone-authored diagnostic must not reach UI")

    #expect(
      try await journal.applyAcknowledgement(
        acknowledgement, retryAt: .distantFuture) == .rejected)
    let rejected = try #require(await journal.deliveryStatus().rejectedCommands.first)
    #expect(rejected.code == "future_policy")
    #expect(rejected.reason == "This action wasn't applied on iPhone.")
    #expect(!rejected.reason.contains("diagnostic"))
  }

  @Test("workspace replacement rejects old pending commands before transport")
  func workspaceReplacementFencesOldCommands() async throws {
    let url = makeJournalURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let journal = try LorvexWatchCommandJournal(fileURL: url, newInstallID: watchInstallID)
    let old = try await journal.enqueue(
      mutation: .completeTask(id: task1), workspaceInstanceID: workspaceOld,
      createdAt: "2026-07-16T12:00:00.000Z")
    let current = try await journal.enqueue(
      mutation: .captureTask(title: "New workspace"), workspaceInstanceID: workspaceNew,
      createdAt: "2026-07-16T12:00:01.000Z")

    #expect(try await journal.rejectCommandsOutsideWorkspace(
      workspaceNew, code: LorvexWatchDeliveryRejectionText.workspaceReplacedCode))

    let status = await journal.deliveryStatus()
    #expect(status.rejectedCommands.map(\.id) == [old.id])
    #expect(status.rejectedCommands.map(\.code) == ["workspace_replaced"])
    #expect(status.pendingCommands.map(\.id) == [current.id])
    #expect(await journal.nextDeliverable(at: .distantFuture)?.command.id == current.id)
  }
}

private func makeJournalURL() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-watch-journal-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("commands-v1.json")
}

private let watchInstallID = "11111111-1111-4111-8111-111111111111"
private let alternateInstallID = "22222222-2222-4222-8222-222222222222"
private let workspaceA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
private let workspaceOld = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
private let workspaceNew = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
private let task1 = LorvexTask.ID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
private let task2 = LorvexTask.ID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
