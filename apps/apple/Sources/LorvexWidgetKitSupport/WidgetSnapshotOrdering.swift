import Foundation
import LorvexCore

/// Monotonic database-revision ordering for widget snapshot writes.
///
/// `generatedAt` remains freshness metadata only: wall clocks can jump forward,
/// so using it as a state version can pin a destination on stale data forever.
/// Every writer first compares the durable physical-storage generation, then
/// `localChangeSequence` within the same database workspace, then the local
/// Focus-filter revision when the database revision ties, then the logical day
/// materialized from that exact revision. A different workspace inside one
/// generation is a replacement and is accepted.
public enum WidgetSnapshotOrdering {
  /// Parses a `generatedAt` wire string. Accepts both the plain
  /// `.withInternetDateTime` shape the projector emits and the fractional-second
  /// shape, so a snapshot produced by either survives the comparison.
  public static func parse(_ raw: String) -> Date? {
    if let date = LorvexDateFormatters.iso8601Fractional.date(from: raw) {
      return date
    }
    return LorvexDateFormatters.iso8601.date(from: raw)
  }

  /// True when `candidate` was generated strictly before `reference`.
  ///
  /// Fails open: when either timestamp can't be parsed the result is `false`, so
  /// an unparseable timestamp never causes a write to be dropped — a possibly
  /// redundant overwrite is preferred over silently losing an update. Equal
  /// timestamps are not "older", so a re-emitted snapshot in the same second
  /// still overwrites (submission order breaks the tie at the write seam).
  public static func isStrictlyOlder(_ candidate: String, than reference: String) -> Bool {
    guard let candidateDate = parse(candidate), let referenceDate = parse(reference) else {
      return false
    }
    return candidateDate < referenceDate
  }

  /// True when `candidate` represents an earlier committed database revision
  /// than `reference`. Storage generation is globally monotonic for this managed
  /// location and therefore dominates workspace/sequence. Different physical
  /// databases inside one generation remain intentionally incomparable.
  public static func isStrictlyOlder(
    _ candidate: WidgetSnapshot, than reference: WidgetSnapshot
  ) -> Bool {
    if candidate.storageGeneration != reference.storageGeneration {
      return candidate.storageGeneration < reference.storageGeneration
    }
    guard candidate.workspaceInstanceID == reference.workspaceInstanceID else {
      return false
    }
    if candidate.localChangeSequence != reference.localChangeSequence {
      return candidate.localChangeSequence < reference.localChangeSequence
    }
    if candidate.focusFilterRevision != reference.focusFilterRevision {
      return candidate.focusFilterRevision < reference.focusFilterRevision
    }
    return isLogicalDayStrictlyOlder(candidate.logicalDay, than: reference.logicalDay)
  }

  /// Reads just the `generated_at` field from encoded `WidgetSnapshot` JSON,
  /// or `nil` when the data isn't a decodable snapshot. Cheaper and more
  /// tolerant than decoding the whole snapshot when only the timestamp is needed
  /// to decide whether an incoming payload is stale.
  public static func generatedAt(fromEncoded data: Data) -> String? {
    try? JSONDecoder().decode(GeneratedAtProbe.self, from: data).generatedAt
  }

  /// Reads the strict v3 ordering fields from encoded snapshot JSON. Returning
  /// nil fails open at the file seam, where a redundant overwrite is safer than
  /// discarding an update based on an incomplete key.
  public static func orderingKey(fromEncoded data: Data) -> OrderingKey? {
    try? JSONDecoder().decode(OrderingKey.self, from: data)
  }

  public struct OrderingKey: Codable, Equatable, Sendable {
    public let storageGeneration: Int
    public let focusFilterRevision: Int
    public let workspaceInstanceID: String
    public let localChangeSequence: Int
    public let logicalDay: String?

    enum CodingKeys: String, CodingKey {
      case storageGeneration = "storage_generation"
      case focusFilterRevision = "focus_filter_revision"
      case workspaceInstanceID = "workspace_instance_id"
      case localChangeSequence = "local_change_sequence"
      case logicalDay = "logical_day"
    }

    public init(
      storageGeneration: Int,
      focusFilterRevision: Int,
      workspaceInstanceID: String,
      localChangeSequence: Int,
      logicalDay: String?
    ) {
      self.storageGeneration = max(0, storageGeneration)
      self.focusFilterRevision = max(0, focusFilterRevision)
      self.workspaceInstanceID = workspaceInstanceID
      self.localChangeSequence = localChangeSequence
      self.logicalDay = logicalDay
    }
  }

  public static func isStrictlyOlder(_ candidate: OrderingKey, than reference: OrderingKey) -> Bool {
    if candidate.storageGeneration != reference.storageGeneration {
      return candidate.storageGeneration < reference.storageGeneration
    }
    guard candidate.workspaceInstanceID == reference.workspaceInstanceID else {
      return false
    }
    if candidate.localChangeSequence != reference.localChangeSequence {
      return candidate.localChangeSequence < reference.localChangeSequence
    }
    if candidate.focusFilterRevision != reference.focusFilterRevision {
      return candidate.focusFilterRevision < reference.focusFilterRevision
    }
    return isLogicalDayStrictlyOlder(candidate.logicalDay, than: reference.logicalDay)
  }

  /// Compare only canonical day keys. A missing/malformed candidate is older
  /// than a canonical reference, so legacy or corrupt equal-revision payloads
  /// cannot replace a source-anchored snapshot; a canonical candidate replaces
  /// an unanchored legacy reference.
  private static func isLogicalDayStrictlyOlder(
    _ candidate: String?, than reference: String?
  ) -> Bool {
    let candidateDay = canonicalLogicalDay(candidate)
    let referenceDay = canonicalLogicalDay(reference)
    switch (candidateDay, referenceDay) {
    case let (candidateDay?, referenceDay?):
      return candidateDay < referenceDay
    case (nil, .some):
      return true
    case (.some, nil), (nil, nil):
      return false
    }
  }

  private static func canonicalLogicalDay(_ raw: String?) -> String? {
    guard let raw, raw.count == 10,
      let date = LorvexDateFormatters.ymdUTC.date(from: raw),
      LorvexDateFormatters.ymdUTC.string(from: date) == raw
    else { return nil }
    return raw
  }

  private struct GeneratedAtProbe: Decodable {
    let generatedAt: String
    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at" }
  }
}
