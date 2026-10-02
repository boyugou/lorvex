import LorvexCore
import Testing

/// A view that draws a stored list, habit, or event icon as an SF Symbol, such
/// as a habit's ring on every platform, falls back to its own mark whenever the
/// icon cannot be drawn as one.
@Suite("Stored icon symbol")
struct LorvexSymbolTests {
  @Test
  func keepsARealSymbol() {
    #expect(LorvexSymbol.name(for: "figure.run", fallback: "repeat") == "figure.run")
  }

  @Test
  func fallsBackWithoutAnIcon() {
    #expect(LorvexSymbol.name(for: nil, fallback: "repeat") == "repeat")
    #expect(LorvexSymbol.name(for: "", fallback: "repeat") == "repeat")
  }

  /// An emoji is not a symbol name; it would draw an empty box.
  @Test
  func fallsBackForAnEmoji() {
    #expect(LorvexSymbol.name(for: "🏃", fallback: "repeat") == "repeat")
  }

  /// A name this system does not have, such as one set over MCP, would draw
  /// the missing-symbol box.
  @Test
  func fallsBackForAnUnknownName() {
    #expect(LorvexSymbol.name(for: "no.such.symbol.anywhere", fallback: "repeat") == "repeat")
  }
}
