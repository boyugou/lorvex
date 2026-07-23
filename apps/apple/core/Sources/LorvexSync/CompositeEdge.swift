import Foundation
import LorvexDomain

/// Shared parsing for sync edge entity IDs.
///
/// Sync relation edges use `left:right` IDs for two-column primary keys
/// (`task_tag`, `task_dependency`, `task_calendar_event_link`,
/// `habit_completion`). Parsing is strict and centralized so FK preflight,
/// apply handlers, version lookup, and pending-inbox remaps all reject
/// malformed IDs identically: exactly one `:` separator and non-empty halves.
public enum CompositeEdge {
  /// A composite edge id that does not split into exactly one `:` with
  /// non-empty halves.
  public struct CompositeEdgeIdError: Error, Equatable, CustomStringConvertible {
    public let entityId: String
    public let colonCount: Int

    public var description: String {
      "edge entity_id must contain exactly one ':' separator with non-empty halves, "
        + "got \(colonCount) separator(s) in \(applyDebugQuoted(entityId))"
    }
  }

  /// True when `entityType` is one of the four composite-key edge types.
  public static func isCompositeEdgeEntityType(_ entityType: String) -> Bool {
    switch entityType {
    case EdgeName.taskTag, EdgeName.taskDependency, EdgeName.taskCalendarEventLink,
      EdgeName.habitCompletion:
      return true
    default:
      return false
    }
  }

  /// Split `left:right` into its halves, requiring exactly one `:` separator
  /// with non-empty left and right.
  public static func splitCompositeEdgeId(
    _ entityId: String
  ) -> Result<(String, String), CompositeEdgeIdError> {
    let colonCount = entityId.utf8.filter { $0 == 0x3A }.count
    guard let idx = entityId.firstIndex(of: ":") else {
      return .failure(CompositeEdgeIdError(entityId: entityId, colonCount: colonCount))
    }
    let left = String(entityId[entityId.startIndex..<idx])
    let right = String(entityId[entityId.index(after: idx)...])
    if colonCount != 1 || left.isEmpty || right.isEmpty {
      return .failure(CompositeEdgeIdError(entityId: entityId, colonCount: colonCount))
    }
    return .success((left, right))
  }

  /// Rewrite either half of a composite edge id when it equals `oldPart`,
  /// replacing it with `newPart`. Returns `.success(nil)` when neither half
  /// changes (no remap needed), `.success(newId)` when one or both halves were
  /// rewritten, `.failure` when `original` is not a valid composite id.
  public static func remapCompositeEdgeId(
    _ original: String, oldPart: String, newPart: String
  ) -> Result<String?, CompositeEdgeIdError> {
    switch splitCompositeEdgeId(original) {
    case .failure(let e):
      return .failure(e)
    case .success(let (left, right)):
      let newLeft = left == oldPart ? newPart : left
      let newRight = right == oldPart ? newPart : right
      if newLeft == left && newRight == right {
        return .success(nil)
      }
      return .success("\(newLeft):\(newRight)")
    }
  }
}
