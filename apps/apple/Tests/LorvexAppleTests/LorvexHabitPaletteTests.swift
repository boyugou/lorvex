import LorvexCore
import SwiftUI
import Testing

@Suite("Habit identity color")
struct LorvexHabitPaletteTests {
  private func habit(id: String, color: String?) -> LorvexHabit {
    LorvexHabit(
      id: id, name: "Stretch", icon: nil, color: color, cue: nil,
      frequencyType: "daily", targetCount: 1, completionsToday: 0,
      totalCompletions: 0, completionRate30d: 0, archived: false)
  }

  @Test("a chosen color wins over the fallback hue")
  func chosenColorWins() {
    #expect(
      LorvexHabitPalette.baseColor(for: habit(id: "h1", color: "#FF9500"))
        == Color(lorvexHex: "#FF9500"))
  }

  @Test("a habit without a color gets the same hue in every process")
  func fallbackHueIsStable() {
    // Pinned: a per-process hash such as `hashValue` would give the same habit
    // a different hue on each launch and on each device.
    #expect(LorvexHabitPalette.baseColor(for: habit(id: "h1", color: nil)) == .teal)
    #expect(
      LorvexHabitPalette.baseColor(
        for: habit(id: "fd707b37-023e-4a40-a378-58c8bdd85a3c", color: nil)) == .cyan)
  }

  @Test("the fallback hues never include green, the done color")
  func fallbackHuesExcludeGreen() {
    #expect(!LorvexDesign.Palette.identityHues.contains(.green))
  }
}
