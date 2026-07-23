import Foundation

public struct EventKitCalendarDescriptor: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let sourceTitle: String?
  /// The calendar's own color as `#RRGGBB`, for a color dot beside its title in
  /// the event form's calendar picker. `nil` when EventKit reports no color (or
  /// the descriptor is for a surface that doesn't display one, e.g. the mirror
  /// include/exclude settings list).
  public let colorHex: String?

  public init(id: String, title: String, sourceTitle: String?, colorHex: String? = nil) {
    self.id = id
    self.title = title
    self.sourceTitle = sourceTitle
    self.colorHex = colorHex
  }
}
