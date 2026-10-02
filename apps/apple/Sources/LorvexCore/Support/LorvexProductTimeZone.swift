import SwiftUI

extension EnvironmentValues {
  /// The synced time zone Lorvex counts its days in. It differs from this
  /// device's zone while the user travels and keeps their home zone. Task rows
  /// count their day-granular facts in it (due today or tomorrow, overdue, the
  /// relative due label, hidden until), so a row agrees with the lists the core
  /// builds for the product's logical day. Each scene root sets it from its
  /// store; without one it is this device's zone.
  @Entry public var lorvexProductTimeZone: TimeZone = .autoupdatingCurrent
}
