import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A lightweight reference to a task suitable for drag-and-drop transfer.
///
/// Only carries the task `id` and `title` — the full `LorvexTask` stays in the
/// store. The receiving drop handler resolves the task from the store by ID.
public struct LorvexTaskRef: Codable, Sendable, Hashable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

extension UTType {
  /// Private UTType for intra-app `LorvexTaskRef` drag-and-drop.
  public static let lorvexTask = UTType(exportedAs: "com.lorvex.apple.task-ref")
}

extension LorvexTaskRef: Transferable {
  public static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .lorvexTask)
  }
}
