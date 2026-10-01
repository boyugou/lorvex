import Testing

@testable import LorvexWatch

/// An open habit's ring on the watch shows the habit's own symbol, so the
/// symbol must fall back to a repeat mark whenever the stored icon cannot be
/// drawn as an SF Symbol.
@Suite("Watch habit ring symbol")
struct LorvexWatchHabitSymbolTests {
  @Test
  func keepsTheHabitsOwnSymbol() {
    #expect(LorvexWatchHabitsPage.symbol(for: "figure.run") == "figure.run")
  }

  @Test
  func fallsBackWithoutAnIcon() {
    #expect(LorvexWatchHabitsPage.symbol(for: nil) == "repeat")
    #expect(LorvexWatchHabitsPage.symbol(for: "") == "repeat")
  }

  /// An emoji is not a symbol name; it would draw an empty box.
  @Test
  func fallsBackForAnEmoji() {
    #expect(LorvexWatchHabitsPage.symbol(for: "🏃") == "repeat")
  }
}
