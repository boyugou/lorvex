import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

@Suite("Watch command delivery")
struct LorvexWatchCommandDeliveryTests {
  @Test("reachable delivery applies strict ACKs and drains FIFO in order")
  func reachableDeliveryDrainsFIFO() async throws {
    let harness = try await makeDeliveryHarness(
      state: .reachable,
      directReplies: [.acknowledgement(.applied), .acknowledgement(.applied)])
    defer { harness.removeFiles() }

    let first = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    let second = try await harness.delivery.enqueue(.cancelTask(id: deliveryTask2))
    await harness.delivery.drain()

    #expect(try await harness.channel.directCommandIDs() == [first.id, second.id])
    #expect(await harness.journal.allEntries().isEmpty)
  }

  @Test("direct transport failure retains the head with deterministic backoff")
  func directFailureRetainsHead() async throws {
    let harness = try await makeDeliveryHarness(
      state: .reachable,
      directReplies: [.failure],
      retryPolicy: .init(initialDelay: 7, maximumDelay: 60, acknowledgementTimeout: 30))
    defer { harness.removeFiles() }

    let command = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    await harness.delivery.drain()

    let entries = await harness.journal.allEntries()
    #expect(entries.map(\.command.id) == [command.id])
    #expect(entries.first?.attemptCount == 1)
    #expect(entries.first?.nextAttemptAt == deliveryNow.addingTimeInterval(7))
    #expect(try await harness.channel.directCommandIDs() == [command.id])
  }

  @Test("background transfer keeps the row until a strict application ACK")
  func backgroundTransferWaitsForApplicationAck() async throws {
    let harness = try await makeDeliveryHarness(state: .background)
    defer { harness.removeFiles() }

    let command = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    await harness.delivery.drain()

    let queued = try #require(await harness.channel.backgroundCommandData().first)
    #expect(await harness.journal.allEntries().map(\.command.id) == [command.id])
    #expect(await harness.journal.allEntries().first?.attemptCount == 1)

    // A successful WCSession transfer completion is transport-only.
    await harness.delivery.backgroundTransferFinished(commandData: queued, error: nil)
    #expect(await harness.journal.allEntries().map(\.command.id) == [command.id])

    let wireCommand = try LorvexWatchCommand.decodeWireData(queued)
    let acknowledgement = try LorvexWatchCommandAck(
      command: wireCommand, outcome: .applied)
    await harness.delivery.receiveAcknowledgementData(try acknowledgement.wireData())
    #expect(await harness.journal.allEntries().isEmpty)
  }

  @Test("future and duplicate ACKs cannot consume the FIFO head")
  func invalidAckOrderingCannotConsumeHead() async throws {
    let harness = try await makeDeliveryHarness(state: .inactive)
    defer { harness.removeFiles() }

    let first = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    let second = try await harness.delivery.enqueue(.cancelTask(id: deliveryTask2))
    let futureAck = try LorvexWatchCommandAck(
      command: second.wireCommand(), outcome: .applied)

    await harness.delivery.receiveAcknowledgementData(try futureAck.wireData())
    #expect(await harness.journal.allEntries().map(\.command.id) == [first.id, second.id])

    let firstAck = try LorvexWatchCommandAck(
      command: first.wireCommand(), outcome: .applied)
    await harness.delivery.receiveAcknowledgementData(try firstAck.wireData())
    #expect(await harness.journal.allEntries().map(\.command.id) == [second.id])

    await harness.delivery.receiveAcknowledgementData(try firstAck.wireData())
    #expect(await harness.journal.allEntries().map(\.command.id) == [second.id])
  }

  @Test("inactive session retains commands without recording a delivery attempt")
  func inactiveSessionDoesNotAttemptTransport() async throws {
    let harness = try await makeDeliveryHarness(state: .inactive)
    defer { harness.removeFiles() }

    let command = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    await harness.delivery.drain()

    let entries = await harness.journal.allEntries()
    #expect(entries.map(\.command.id) == [command.id])
    #expect(entries.first?.attemptCount == 0)
    #expect(try await harness.channel.directCommandIDs().isEmpty)
    #expect(await harness.channel.backgroundCommandData().isEmpty)
  }

  @Test("an identical outstanding background transfer is not enqueued twice")
  func outstandingBackgroundTransferIsNotDuplicated() async throws {
    let harness = try await makeDeliveryHarness(state: .background)
    defer { harness.removeFiles() }

    let command = try await harness.delivery.enqueue(.completeTask(id: deliveryTask1))
    let commandData = try command.wireCommand().wireData()
    await harness.channel.setOutstanding(commandData)
    await harness.delivery.drain()

    #expect(await harness.channel.backgroundCommandData().isEmpty)
    let entries = await harness.journal.allEntries()
    #expect(entries.map(\.command.id) == [command.id])
    #expect(entries.first?.attemptCount == 0)
    #expect(entries.first?.nextAttemptAt == deliveryNow.addingTimeInterval(30))
  }
}

private struct DeliveryHarness {
  let rootURL: URL
  let journal: LorvexWatchCommandJournal
  let delivery: LorvexWatchCommandDelivery
  let channel: FakeWatchCommandChannel

  func removeFiles() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private func makeDeliveryHarness(
  state: LorvexWatchDeliveryChannelState,
  directReplies: [FakeWatchDirectReply] = [],
  retryPolicy: LorvexWatchDeliveryRetryPolicy = .init(
    initialDelay: 5, maximumDelay: 60, acknowledgementTimeout: 30)
) async throws -> DeliveryHarness {
  let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("watch-delivery-\(UUID().uuidString)", isDirectory: true)
  let fileManager = DeliveryFixedContainerFileManager(containerURL: rootURL)
  let replicaStore = LorvexWatchReplicaStore(
    appGroupID: "group.com.lorvex.delivery-tests",
    fileManagerBox: LorvexWatchFileManagerBox(fileManager))
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-07-16T12:00:00Z",
    workspaceInstanceID: deliveryWorkspace,
    timezone: "UTC",
    stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [])
  let replica = try LorvexWatchReplicaEnvelope(
    workspaceInstanceID: deliveryWorkspace,
    snapshotData: JSONEncoder().encode(snapshot))
  _ = try await replicaStore.accept(try replica.wireData())

  let journalURL =
    rootURL
    .appendingPathComponent("Lorvex", isDirectory: true)
    .appendingPathComponent("commands-v1.json")
  let journal = try LorvexWatchCommandJournal(
    fileURL: journalURL,
    newInstallID: deliveryInstallID)
  let channel = FakeWatchCommandChannel(state: state, directReplies: directReplies)
  let delivery = LorvexWatchCommandDelivery(
    journal: journal,
    replicaStore: replicaStore,
    channel: channel,
    retryPolicy: retryPolicy,
    now: { deliveryNow },
    schedulesRetries: false)
  return DeliveryHarness(
    rootURL: rootURL,
    journal: journal,
    delivery: delivery,
    channel: channel)
}

private enum FakeWatchDirectReply: Sendable {
  case acknowledgement(LorvexWatchCommandAck.Outcome)
  case failure
}

private enum FakeWatchDeliveryError: Error {
  case transportFailed
}

private actor FakeWatchCommandChannel: LorvexWatchCommandChannel {
  private let state: LorvexWatchDeliveryChannelState
  private var directReplies: [FakeWatchDirectReply]
  private var directCommands: [Data] = []
  private var backgroundCommands: [Data] = []
  private var outstandingCommands = Set<Data>()

  init(
    state: LorvexWatchDeliveryChannelState,
    directReplies: [FakeWatchDirectReply]
  ) {
    self.state = state
    self.directReplies = directReplies
  }

  func deliveryState() async -> LorvexWatchDeliveryChannelState { state }

  func sendDirect(_ commandData: Data) async throws -> Data {
    directCommands.append(commandData)
    guard !directReplies.isEmpty else { throw FakeWatchDeliveryError.transportFailed }
    switch directReplies.removeFirst() {
    case .acknowledgement(let outcome):
      let command = try LorvexWatchCommand.decodeWireData(commandData)
      let code = outcome == .applied ? nil : "test_outcome"
      return try LorvexWatchCommandAck(
        command: command,
        outcome: outcome,
        code: code
      ).wireData()
    case .failure:
      throw FakeWatchDeliveryError.transportFailed
    }
  }

  func hasOutstandingBackgroundCommand(_ commandData: Data) async -> Bool {
    outstandingCommands.contains(commandData)
  }

  func enqueueBackground(_ commandData: Data) async throws {
    backgroundCommands.append(commandData)
  }

  func setOutstanding(_ commandData: Data) {
    outstandingCommands.insert(commandData)
  }

  func directCommandIDs() throws -> [String] {
    try directCommands.map { try LorvexWatchCommand.decodeWireData($0).commandID }
  }

  func backgroundCommandData() -> [Data] { backgroundCommands }
}

private final class DeliveryFixedContainerFileManager: FileManager, @unchecked Sendable {
  private let fixedContainerURL: URL?

  init(containerURL: URL?) {
    self.fixedContainerURL = containerURL
    super.init()
  }

  override func containerURL(
    forSecurityApplicationGroupIdentifier groupIdentifier: String
  ) -> URL? {
    fixedContainerURL
  }
}

private let deliveryNow = Date(timeIntervalSince1970: 1_752_667_200)
private let deliveryInstallID = "11111111-1111-4111-8111-111111111111"
private let deliveryWorkspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
private let deliveryTask1 = LorvexTask.ID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
private let deliveryTask2 = LorvexTask.ID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")
