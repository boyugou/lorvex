import SwiftUI

/// A status chip a host puts on a task row: a short fact in a tint, such as
/// "Until 3:00 PM" or "Pushed 4 times". Chips state facts; the row's own
/// controls carry its actions.
public struct LorvexTaskRowChip: Identifiable, Equatable, Sendable {
  /// Stable within one row; also names the chip's accessibility identifier.
  public let id: String
  public let title: String
  public var systemImage: String?
  public var tint: Color

  public init(
    id: String, title: String, systemImage: String? = nil,
    tint: Color = LorvexDesign.Palette.neutral
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
  }
}
