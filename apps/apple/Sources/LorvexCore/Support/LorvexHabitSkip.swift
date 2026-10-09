import Foundation
import SwiftUI

/// A habit's skip control for the day the habit was loaded for: Skip Today sets
/// the day aside as an excused day, and Undo Skip takes that back. A day that
/// already holds a check-in offers neither, since a check-in outranks a skip and
/// a day holds one or the other.
public enum LorvexHabitSkip: Equatable, Sendable {
  case skip
  case unskip

  /// The control to offer for `habit`, read against the day it was loaded for,
  /// or nil when that day holds a check-in.
  public static func action(for habit: LorvexHabit) -> LorvexHabitSkip? {
    if habit.isSkipped { return .unskip }
    return habit.completionsToday == 0 ? .skip : nil
  }

  /// The SF Symbol at the center of a skipped day's ring, and the Skip Today
  /// command's mark. It is not a moon: the moon is the Someday status's mark.
  public static let glyph = "forward.fill"

  /// The SF Symbol of the Undo Skip command, the one Reset Today wears.
  public static let undoGlyph = "arrow.counterclockwise"
}

/// A ring drawn as evenly spaced dots: the track of a habit's ring on a day it
/// is skipped, in place of the solid track. The dots sit on the circle a solid
/// stroke of `dotDiameter` would be centered on, so a skipped ring and an open
/// one have the same outline. The shape reads apart from a solid ring and from
/// the separate arcs of a habit counted several times a day without relying on
/// color. Fill it with the track's style.
public struct LorvexDottedRing: Shape {
  public var dotDiameter: CGFloat

  public init(dotDiameter: CGFloat) {
    self.dotDiameter = dotDiameter
  }

  public func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) / 2
    guard dotDiameter > 0, radius > dotDiameter else { return Path() }
    // About one dot's width of gap between neighbors, at least eight dots.
    let count = max(8, Int((2 * .pi * radius / (dotDiameter * 1.9)).rounded()))
    var path = Path()
    for index in 0..<count {
      let angle = 2 * Double.pi * Double(index) / Double(count) - Double.pi / 2
      let x = rect.midX + radius * CGFloat(cos(angle))
      let y = rect.midY + radius * CGFloat(sin(angle))
      path.addEllipse(
        in: CGRect(
          x: x - dotDiameter / 2, y: y - dotDiameter / 2, width: dotDiameter, height: dotDiameter))
    }
    return path
  }
}
