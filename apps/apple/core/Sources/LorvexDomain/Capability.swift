/// Per-envelope acceptance decision.
public enum EnvelopeAcceptance: Sendable, Equatable {
  /// Version zero is outside the 1-based payload contract ladder.
  case rejectInvalid
  /// Known version: parse all fields.
  case parseFully
  /// One version ahead: forward-compat — parse known fields, ignore unknown.
  case parseForwardCompat
  /// Too far ahead: cannot safely parse — queue to pending inbox.
  case deferToPendingInbox
}

public enum Capability {
  /// Check per-envelope acceptance based on its payload schema version.
  public static func checkEnvelopeVersion(
    envelopePayloadVersion: UInt32, localMaxVersion: UInt32
  ) -> EnvelopeAcceptance {
    if envelopePayloadVersion == 0 {
      return .rejectInvalid
    }
    if envelopePayloadVersion <= localMaxVersion {
      return .parseFully
    }
    let nextVersion =
      localMaxVersion == UInt32.max ? UInt32.max : localMaxVersion + 1
    if envelopePayloadVersion == nextVersion {
      return .parseForwardCompat
    }
    return .deferToPendingInbox
  }
}
