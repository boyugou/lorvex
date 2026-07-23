import Foundation
import LorvexCore
import Testing

@Suite("Watch command wire contract")
struct LorvexWatchCommandWireTests {
  private let workspaceID = "018f0000-0000-7000-8000-000000000001"
  private let installID = "018f0000-0000-7000-8000-000000000002"
  private let commandID = "018f0000-0000-7000-8000-000000000003"
  private let taskID = "018f0000-0000-7000-8000-000000000004"
  private let habitID = "018f0000-0000-7000-8000-000000000005"

  @Test("every mutation round-trips through the strict command envelope")
  func mutationRoundTrips() throws {
    let mutations: [LorvexWatchMutation] = [
      .completeTask(id: taskID),
      .cancelTask(id: taskID),
      .deferTaskToTomorrow(id: taskID, plannedDate: "2026-07-16"),
      .removeFromFocus(id: taskID, date: "2026-07-15"),
      .captureTask(title: "Follow up / 下一步"),
      .completeHabit(id: habitID, date: "2026-07-15"),
    ]

    for (offset, mutation) in mutations.enumerated() {
      let command = try makeCommand(sequence: Int64(offset + 1), mutation: mutation)
      let decoded = try LorvexWatchCommand.decodeWireData(command.wireData())
      #expect(decoded == command)
    }
  }

  @Test("unknown top-level and mutation keys fail closed")
  func unknownKeysFailClosed() throws {
    let command = try makeCommand(mutation: .completeTask(id: taskID))
    let clean = try #require(
      try JSONSerialization.jsonObject(with: command.wireData()) as? [String: Any])

    var topLevel = clean
    topLevel["future"] = true
    #expect(throws: LorvexWatchWireError.self) {
      try LorvexWatchCommand.decodeWireData(
        JSONSerialization.data(withJSONObject: topLevel, options: [.sortedKeys]))
    }

    var nested = clean
    var mutation = try #require(nested["mutation"] as? [String: Any])
    mutation["future"] = true
    nested["mutation"] = mutation
    #expect(throws: LorvexWatchWireError.self) {
      try LorvexWatchCommand.decodeWireData(
        JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys]))
    }
  }

  @Test("payload mutation without a new checksum is rejected")
  func checksumMismatchFailsClosed() throws {
    let command = try makeCommand(mutation: .captureTask(title: "Original"))
    var object = try #require(
      try JSONSerialization.jsonObject(with: command.wireData()) as? [String: Any])
    var mutation = try #require(object["mutation"] as? [String: Any])
    mutation["title"] = "Changed"
    object["mutation"] = mutation
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    #expect(throws: LorvexWatchWireError.checksumMismatch) {
      try LorvexWatchCommand.decodeWireData(tampered)
    }
  }

  @Test("application ACK is identity-bound and strict")
  func acknowledgementRoundTripAndIdentity() throws {
    let command = try makeCommand(mutation: .completeTask(id: taskID))
    let ack = try LorvexWatchCommandAck(command: command, outcome: .applied)
    let decoded = try LorvexWatchCommandAck.decodeWireData(ack.wireData())
    #expect(decoded == ack)
    #expect(decoded.matches(command))

    let other = try makeCommand(sequence: 2, mutation: .completeTask(id: taskID))
    #expect(!decoded.matches(other))

    let retryable = try LorvexWatchCommandAck(
      command: command,
      outcome: .retryable,
      code: "storage_unavailable",
      message: "Try again")
    #expect(try LorvexWatchCommandAck.decodeWireData(retryable.wireData()) == retryable)
  }

  @Test("replica baseline round-trips and rejects tampering")
  func replicaEnvelopeRoundTrip() throws {
    let snapshot = Data(#"{"version":2}"#.utf8)
    let replica = try LorvexWatchReplicaEnvelope(
      workspaceInstanceID: workspaceID,
      snapshotData: snapshot)
    #expect(try LorvexWatchReplicaEnvelope.decodeWireData(replica.wireData()) == replica)

    var object = try #require(
      try JSONSerialization.jsonObject(with: replica.wireData()) as? [String: Any])
    object["snapshot_data"] = Data("different".utf8).base64EncodedString()
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    #expect(throws: LorvexWatchWireError.checksumMismatch) {
      try LorvexWatchReplicaEnvelope.decodeWireData(tampered)
    }
  }

  @Test("noncanonical identity and date fields are rejected before transport")
  func canonicalFieldsAreRequired() {
    #expect(throws: LorvexWatchWireError.self) {
      try LorvexWatchCommand(
        sourceInstallID: installID,
        workspaceInstanceID: workspaceID.uppercased(),
        sequence: 1,
        commandID: commandID,
        createdAt: "2026-07-15T12:00:00.000Z",
        mutation: .completeTask(id: taskID))
    }
    #expect(throws: LorvexWatchWireError.self) {
      try LorvexWatchCommand(
        sourceInstallID: installID,
        workspaceInstanceID: workspaceID,
        sequence: 1,
        commandID: commandID,
        createdAt: "2026-07-15T12:00:00.000Z",
        mutation: .completeHabit(id: habitID, date: "2026-02-30"))
    }
  }

  private func makeCommand(
    sequence: Int64 = 1,
    mutation: LorvexWatchMutation
  ) throws -> LorvexWatchCommand {
    try LorvexWatchCommand(
      sourceInstallID: installID,
      workspaceInstanceID: workspaceID,
      sequence: sequence,
      commandID: sequence == 1 ? commandID : "018f0000-0000-7000-8000-000000000006",
      createdAt: "2026-07-15T12:00:00.000Z",
      mutation: mutation)
  }
}
