import SwiftUI

/// A habit's identity color, independent of completion state.
///
/// The user's chosen `color` (a `#RRGGBB` hex) wins. A habit without one takes
/// a hue from ``LorvexDesign/Palette/identityHues`` picked by a stable hash of
/// its id, so it keeps the same color on every device and every launch; the
/// hash deliberately avoids `hashValue`, which Swift randomizes per process.
/// Views that show today's state swap in ``LorvexDesign/Palette/done`` once
/// the habit is finished; the identity color is everything else about it.
public enum LorvexHabitPalette {
  public static func baseColor(for habit: LorvexHabit) -> Color {
    baseColor(id: habit.id, color: habit.color)
  }

  /// The identity color for a habit known only by its id and stored color, as
  /// a widget or watch snapshot carries it.
  public static func baseColor(id: String, color: String?) -> Color {
    if let custom = Color(lorvexHex: color) { return custom }
    let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    let hues = LorvexDesign.Palette.identityHues
    return hues[hash % hues.count]
  }
}
