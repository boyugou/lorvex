import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A lightweight reference to one or more tasks suitable for drag-and-drop
/// transfer.
///
/// Carries only task `id`s and `title`s — the full `LorvexTask` stays in the
/// store. The receiving drop handler resolves the tasks from the store by ID.
/// A drag of one task carries that task alone; dragging a row that belongs to a
/// multi-task selection carries the whole selection, the dragged row first
/// (`self`) and the other selected rows in `companions`. Lorvex's own drop
/// targets take the reference itself and read ``taskIDs``; any other app that
/// receives the drag (Notes, Mail, Messages, Calendar, Reminders, a text field)
/// gets the titles as plain text, one per line.
public struct LorvexTaskRef: Codable, Sendable, Hashable {
  public let id: String
  public let title: String
  /// The other tasks dragged together with this one, in the order the surface
  /// shows them. Empty for a drag of a single task.
  public let companions: [LorvexTaskRef]

  public init(id: String, title: String, companions: [LorvexTaskRef] = []) {
    self.id = id
    self.title = title
    self.companions = companions
  }

  /// The ids of every dragged task, the dragged row first.
  public var taskIDs: [String] {
    [id] + companions.flatMap(\.taskIDs)
  }

  /// The titles of every dragged task, in ``taskIDs`` order.
  public var titles: [String] {
    [title] + companions.flatMap(\.titles)
  }
}

extension Sequence where Element == LorvexTaskRef {
  /// The ids of every task in the dropped references, each once, in drop order.
  /// A drop handler reads this instead of mapping `id`, so a multi-task drag
  /// acts on the whole selection.
  public var droppedTaskIDs: [String] {
    var seen = Set<String>()
    return flatMap(\.taskIDs).filter { seen.insert($0).inserted }
  }
}

extension UTType {
  /// Private UTType for intra-app `LorvexTaskRef` drag-and-drop.
  ///
  /// The identifier is declared in `UTExportedTypeDeclarations` of the macOS and
  /// iOS `Info.plist` (conforming to `public.data`); `verify_app_metadata.py`
  /// keeps the two in step. The declaration is required, not decorative: for a
  /// custom type the system does not know, SwiftUI accepts a drop over a
  /// `dropDestination` yet never decodes the payload, so the drop handler does
  /// not run.
  public static let lorvexTask = UTType(exportedAs: "com.lorvex.apple.task-ref", conformingTo: .data)
}

extension LorvexTaskRef: Transferable {
  public static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .lorvexTask)
    ProxyRepresentation(exporting: { $0.titles.joined(separator: "\n") })
  }
}
