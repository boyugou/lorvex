import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

#if canImport(WatchConnectivity)
  @MainActor
  @Suite("Phone Watch command receiver")
  struct PhoneWatchConnectivityReceiverTests {
    @Test("strict command Data applies through the Core transaction boundary")
    func strictCommandDataApplies() async throws {
      let service = try await makeSeededInMemoryCore()
      let task = try await service.createTask(title: "Complete via Watch", notes: "")
      let receiver = try #require(PhoneWatchConnectivityReceiver(
        store: MobileStore(core: service),
        complicationReloader: NoOpComplicationReloader()))
      let command = try await makeCommand(
        service: service, sequence: 1,
        mutation: .completeTask(id: task.id))

      let ack = try #require(await receiver.applyCommandData(command.wireData()))

      #expect(ack.matches(command))
      #expect(try await service.loadTask(id: task.id).status == .completed)
    }

    @Test("capture retry replays the Core receipt instead of creating twice")
    func repeatedCaptureAppliesOnce() async throws {
      let service = try await makeSeededInMemoryCore()
      let receiver = try #require(PhoneWatchConnectivityReceiver(
        store: MobileStore(core: service),
        complicationReloader: NoOpComplicationReloader()))
      let command = try await makeCommand(
        service: service, sequence: 2,
        mutation: .captureTask(title: "Exactly once capture"))
      let data = try command.wireData()

      let first = try #require(await receiver.applyCommandData(data))
      let second = try #require(await receiver.applyCommandData(data))

      #expect(first == second)
      #expect(first.matches(command))
      let today = try await service.loadToday()
      #expect(today.tasks.filter { $0.title == "Exactly once capture" }.count == 1)
    }

    @Test("malformed command Data never reaches Core and receives no ACK")
    func malformedCommandGetsNoAck() async throws {
      let service = try await makeSeededInMemoryCore()
      let receiver = try #require(PhoneWatchConnectivityReceiver(
        store: MobileStore(core: service),
        complicationReloader: NoOpComplicationReloader()))

      let ack = await receiver.applyCommandData(Data("not-json".utf8))

      #expect(ack == nil)
    }

    @Test("application ACK never reads stale MobileStore presentation errors")
    func ackIgnoresMobileStoreErrorMessage() async throws {
      let service = try await makeSeededInMemoryCore()
      let task = try await service.createTask(title: "Core ACK authority", notes: "")
      let store = MobileStore(core: service)
      store.errorMessage = "Unrelated stale UI error"
      let receiver = try #require(PhoneWatchConnectivityReceiver(
        store: store,
        complicationReloader: NoOpComplicationReloader()))
      let command = try await makeCommand(
        service: service, sequence: 4,
        mutation: .completeTask(id: task.id))

      let ack = try #require(await receiver.applyCommandData(command.wireData()))

      #expect(ack.outcome == .applied)
      #expect(try await service.loadTask(id: task.id).status == .completed)
      #expect(store.errorMessage == "Unrelated stale UI error")
    }

    @Test("same command id with different payload fails closed in Core")
    func sameIDDifferentPayloadFailsClosed() async throws {
      let service = try await makeSeededInMemoryCore()
      let store = MobileStore(core: service)
      let receiver = try #require(PhoneWatchConnectivityReceiver(
        store: store,
        complicationReloader: NoOpComplicationReloader()))
      let sourceID = UUID().uuidString.lowercased()
      let commandID = UUID().uuidString.lowercased()
      let workspaceID = try await service.currentWatchWorkspaceInstanceID()
      let first = try LorvexWatchCommand(
        sourceInstallID: sourceID,
        workspaceInstanceID: workspaceID,
        sequence: 3,
        commandID: commandID,
        createdAt: "2026-07-16T12:00:00.000Z",
        mutation: .captureTask(title: "Original"))
      let conflicting = try LorvexWatchCommand(
        sourceInstallID: sourceID,
        workspaceInstanceID: workspaceID,
        sequence: 3,
        commandID: commandID,
        createdAt: "2026-07-16T12:00:00.000Z",
        mutation: .captureTask(title: "Conflicting"))

      let firstAck = try #require(await receiver.applyCommandData(first.wireData()))
      let conflictAck = try #require(await receiver.applyCommandData(conflicting.wireData()))

      #expect(firstAck.matches(first))
      #expect(conflictAck.matches(conflicting))
      let today = try await service.loadToday()
      #expect(today.tasks.filter { $0.title == "Original" }.count == 1)
      #expect(!today.tasks.contains { $0.title == "Conflicting" })
    }

    private func makeCommand(
      service: SwiftLorvexCoreService,
      sequence: Int64,
      mutation: LorvexWatchMutation
    ) async throws -> LorvexWatchCommand {
      try LorvexWatchCommand(
        sourceInstallID: UUID().uuidString.lowercased(),
        workspaceInstanceID: try await service.currentWatchWorkspaceInstanceID(),
        sequence: sequence,
        commandID: UUID().uuidString.lowercased(),
        createdAt: "2026-07-16T12:00:00.000Z",
        mutation: mutation)
    }
  }

  private struct NoOpComplicationReloader: WatchComplicationReloading {
    func reloadTimelines() {}
  }

#endif

@Suite("Phone Watch receiver contracts")
struct PhoneWatchConnectivityReceiverContractTests {
  @Test("terminal outcomes refresh the replica while retryable outcomes remain pending")
  func replicaRefreshPolicyMatchesCommandTerminality() {
    #expect(PhoneWatchReplicaRefreshPolicy.shouldRefresh(after: .applied))
    #expect(PhoneWatchReplicaRefreshPolicy.shouldRefresh(after: .rejected))
    #expect(!PhoneWatchReplicaRefreshPolicy.shouldRefresh(after: .retryable))
  }

  @Test("background ACK queue suppresses an identical outstanding transfer")
  func backgroundAckQueueDeduplicatesByWireData() throws {
    let source = try String(
      contentsOf: applePackageRoot()
        .appending(path: "Sources/LorvexMobile/PhoneWatchConnectivityReceiver.swift"),
      encoding: .utf8)

    #expect(source.contains("session.outstandingUserInfoTransfers.contains"))
    #expect(
      source.contains(
        "transfer.userInfo[LorvexWatchConnectivityKey.commandAckV1] as? Data == ackData"))
    #expect(source.contains("guard !isAlreadyOutstanding else"))
  }

  @Test("mobile app activates the retained receiver before its root view task")
  func appWiresReceiverAtLaunch() throws {
    let source = try String(
      contentsOf: applePackageRoot()
        .appending(path: "Sources/LorvexMobileApp/LorvexMobileApp.swift"),
      encoding: .utf8)

    let initRange = try #require(source.range(of: "init() {"))
    let rootRange = try #require(source.range(of: "private var rootContent"))
    let receiverRange = try #require(
      source.range(of: "let receiver = PhoneWatchConnectivityReceiver(store: builtStore)"))
    let activateRange = try #require(source.range(of: "receiver?.activate()"))
    #expect(receiverRange.lowerBound > initRange.lowerBound)
    #expect(activateRange.lowerBound > receiverRange.lowerBound)
    #expect(activateRange.lowerBound < rootRange.lowerBound)
    #expect(source.contains("private let watchReceiver: PhoneWatchConnectivityReceiver?"))

    let receiverSource = try String(
      contentsOf: applePackageRoot()
        .appending(path: "Sources/LorvexMobile/PhoneWatchConnectivityReceiver.swift"),
      encoding: .utf8)
    #expect(receiverSource.contains("guard activationState == .activated else { return }"))
    #expect(receiverSource.contains("self?.scheduleReplicaBaselineRefresh()"))
  }
}

private func applePackageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
