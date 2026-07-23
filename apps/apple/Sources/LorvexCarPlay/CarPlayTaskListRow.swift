import Foundation
import LorvexCore

extension CarPlayTaskListController {

  /// A single row in the Today or Focus list.
  public struct Row: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let isFocus: Bool

    public init(id: String, title: String, isFocus: Bool) {
      self.id = id
      self.title = title
      self.isFocus = isFocus
    }
  }
}
