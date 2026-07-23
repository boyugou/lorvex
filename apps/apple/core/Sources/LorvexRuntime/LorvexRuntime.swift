/// LorvexRuntime — the shared operating model: DB locator, device identity,
/// sync checkpoints, and local change sequence. The fifth pure-Swift core
/// module.
///
/// The concrete surfaces live in their own files: ``DeviceIdentity``,
/// ``LocalChangeSeq``, ``SyncCheckpoints``, and ``DbLocator``.
public enum LorvexRuntime {
  /// Module schema/version marker for the runtime operating model.
  public static let version: UInt32 = 1
}
