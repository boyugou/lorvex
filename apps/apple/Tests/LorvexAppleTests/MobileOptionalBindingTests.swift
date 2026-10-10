import SwiftUI
import Testing

@testable import LorvexMobile

/// A sheet that edits a draft held in an optional closes by clearing the draft,
/// and the closing sheet still reads and writes its binding afterwards.
@MainActor
@Suite("Optional binding unwrapping")
struct MobileOptionalBindingTests {
  /// An optional source with a plain `Binding` over it, the shape of a
  /// `@State` draft.
  private final class Source: @unchecked Sendable {
    var value: String?

    init(_ value: String?) { self.value = value }

    var binding: Binding<String?> {
      Binding(get: { self.value }, set: { self.value = $0 })
    }
  }

  @Test("An empty source yields no binding")
  func emptySourceYieldsNoBinding() {
    let source = Source(nil)
    #expect(Binding(unwrapping: source.binding) == nil)
  }

  @Test("Reads and writes pass through while the source holds a value")
  func passesThroughWhileHeld() throws {
    let source = Source("Draft")
    let binding = try #require(Binding(unwrapping: source.binding))

    #expect(binding.wrappedValue == "Draft")
    binding.wrappedValue = "Edited"
    #expect(source.value == "Edited")
    #expect(binding.wrappedValue == "Edited")
  }

  @Test("A read after the source is cleared answers with the last held value")
  func readAfterClearAnswersWithHeldValue() throws {
    let source = Source("Draft")
    let binding = try #require(Binding(unwrapping: source.binding))

    source.value = nil
    #expect(binding.wrappedValue == "Draft")
  }

  @Test("A write after the source is cleared leaves it cleared")
  func writeAfterClearIsIgnored() throws {
    let source = Source("Draft")
    let binding = try #require(Binding(unwrapping: source.binding))

    source.value = nil
    binding.wrappedValue = "Late write"
    #expect(source.value == nil)
  }
}
