import Foundation

/// Ephemeral fetch cursor reconstructed from the authoritative SQLite traversal
/// state immediately before each CloudKit request. It is never persisted in a
/// sidecar file; page effects and the successor token commit atomically in the
/// managed database.
public struct CloudSyncChangeCursor: Equatable, Sendable {
  public let accountIdentifier: String
  public let zoneName: String
  public let generationEpoch: Int
  public let generationID: String
  public let readyWitness: String
  public let serverChangeTokenData: Data

  public init(
    accountIdentifier: String, zoneName: String, generationEpoch: Int,
    generationID: String, readyWitness: String,
    serverChangeTokenData: Data
  ) {
    self.accountIdentifier = accountIdentifier
    self.zoneName = zoneName
    self.generationEpoch = generationEpoch
    self.generationID = generationID
    self.readyWitness = readyWitness
    self.serverChangeTokenData = serverChangeTokenData
  }
}
