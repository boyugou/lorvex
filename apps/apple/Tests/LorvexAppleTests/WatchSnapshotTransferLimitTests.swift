import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The phone→watch snapshot publisher (`WCSessionWatchSnapshotPublisher`) is
/// gated on `os(iOS)` and cannot run on the macOS test host; its over-cap
/// detection threshold is factored into the platform-neutral
/// `WatchSnapshotTransferLimit` so it can be covered here.
struct WatchSnapshotTransferLimitTests {
  @Test
  func payloadAtOrBelowCapIsWithinLimit() {
    #expect(WatchSnapshotTransferLimit.isWithinLimit(0))
    #expect(WatchSnapshotTransferLimit.isWithinLimit(1_024))
    #expect(
      WatchSnapshotTransferLimit.isWithinLimit(
        WatchSnapshotTransferLimit.maxApplicationContextPayloadBytes))
  }

  @Test
  func payloadAboveCapIsFlagged() {
    #expect(
      !WatchSnapshotTransferLimit.isWithinLimit(
        WatchSnapshotTransferLimit.maxApplicationContextPayloadBytes + 1))
    #expect(!WatchSnapshotTransferLimit.isWithinLimit(1_000_000))
  }

  @Test
  func transferGateRequiresEveryRuntimePrecondition() {
    #expect(
      WatchSnapshotTransferGate.shouldTransfer(
        byteCount: 1_024, sessionIsActivated: true, isPaired: true,
        isWatchAppInstalled: true))
    #expect(
      !WatchSnapshotTransferGate.shouldTransfer(
        byteCount: 1_024, sessionIsActivated: false, isPaired: true,
        isWatchAppInstalled: true))
    #expect(
      !WatchSnapshotTransferGate.shouldTransfer(
        byteCount: 1_024, sessionIsActivated: true, isPaired: false,
        isWatchAppInstalled: true))
    #expect(
      !WatchSnapshotTransferGate.shouldTransfer(
        byteCount: 1_024, sessionIsActivated: true, isPaired: true,
        isWatchAppInstalled: false))
    #expect(
      !WatchSnapshotTransferGate.shouldTransfer(
        byteCount: WatchSnapshotTransferLimit.maxApplicationContextPayloadBytes + 1,
        sessionIsActivated: true, isPaired: true, isWatchAppInstalled: true))
  }

  @Test("maximum raw snapshot leaves room for the complete application context")
  func maximumReplicaEnvelopeFitsApplicationContextPayloadBudget() throws {
    let envelope = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: "00000000-0000-4000-8000-000000000001",
      snapshotData: Data(
        repeating: 0x61, count: LorvexWatchReplicaEnvelope.maximumSnapshotBytes))

    let applicationContext = [
      LorvexWatchConnectivityKey.replicaEnvelopeV1: try envelope.wireData()
    ]
    let encodedApplicationContext = try PropertyListSerialization.data(
      fromPropertyList: applicationContext, format: .binary, options: 0)

    #expect(
      encodedApplicationContext.count
        <= WatchSnapshotTransferLimit.maxApplicationContextPayloadBytes)
    #expect(
      try WatchSnapshotTransferLimit.serializedByteCount(of: applicationContext)
        == encodedApplicationContext.count)
  }

  @Test("replicas use replaceable latest-state context, not an ordered event queue")
  func replicaTransportUsesApplicationContext() throws {
    let source = try String(
      contentsOf: applePackageRoot()
        .appending(path: "Sources/LorvexMobile/WCSessionWatchSnapshotPublisher.swift"),
      encoding: .utf8)

    #expect(source.contains("try session.updateApplicationContext(applicationContext)"))
    #expect(!source.contains(".transferUserInfo("))
  }
}

private func applePackageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
