import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A lightweight reference to a task checklist item for intra-app drag-and-drop
/// reordering.
///
/// Carries only the item `id`; the drop handler resolves the item and its new
/// position from the store. A dedicated transfer type — rather than a bare
/// `String` — means a checklist row only accepts (and highlights for) genuine
/// checklist drags, not arbitrary dragged text from elsewhere.
public struct LorvexChecklistItemRef: Codable, Sendable, Hashable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

extension UTType {
  /// Private UTType for intra-app `LorvexChecklistItemRef` drag-and-drop.
  public static let lorvexChecklistItem = UTType(exportedAs: "com.lorvex.apple.checklist-item-ref")
}

extension LorvexChecklistItemRef: Transferable {
  public static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .lorvexChecklistItem)
  }
}
