/// Release-facing CloudKit sync readiness declarations.
///
/// `script/verify_cloudkit_sync_readiness.py` maps these Swift ids to the
/// release manifest ids in `script/release_strategy.py` so app code, release
/// metadata, and user-facing docs cannot drift silently.
public enum CloudSyncReadiness {
  public enum Status: Sendable {
    case ready
    case pending
  }

  public struct Capability: Sendable {
    public var id: String
    public var title: String
    public var status: Status
    public var detail: String

    public init(id: String, title: String, status: Status, detail: String) {
      self.id = id
      self.title = title
      self.status = status
      self.detail = detail
    }
  }

  public static let capabilities: [Capability] = [
    Capability(
      id: "export",
      title: "Outbound record export",
      status: .ready,
      detail: "The live coordinator drains local sync outbox entries into private CloudKit records."
    ),
    Capability(
      id: "subscription",
      title: "Private database subscription",
      status: .ready,
      detail: "The app registers a private database subscription for CloudKit remote-change pushes."
    ),
    Capability(
      id: "remote-refresh",
      title: "Remote-change refresh",
      status: .ready,
      detail: "Remote-change pushes fetch private record-zone changes before the app refreshes."
    ),
    Capability(
      id: "inbound-apply",
      title: "Inbound record application",
      status: .ready,
      detail: "Decoded CloudKit records apply through the Swift sync engine with field-level merge gates."
    ),
    Capability(
      id: "change-token",
      title: "Change-token checkpointing",
      status: .ready,
      detail: "Each CloudKit page and its successor token commit atomically in the managed database."
    ),
  ]
}
