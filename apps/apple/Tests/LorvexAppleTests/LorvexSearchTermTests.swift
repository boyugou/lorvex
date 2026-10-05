import LorvexCore
import Testing

/// The in-memory comparison used by pickers, the palette, Siri entity queries,
/// and catalog search must find what the store's search finds: text typed
/// without the accents, case, or letter variants of the stored text.
@Suite("Search term matching")
struct LorvexSearchTermTests {
  @Test("a term typed without letter variants finds the stored text")
  func letterVariants() {
    #expect("Łódź".containsSearchTerm("lodz"))
    #expect("Đi chợ mua rau".containsSearchTerm("di cho"))
    #expect("Işık".containsSearchTerm("isik"))
    #expect("Ørsted".containsSearchTerm("orsted"))
    #expect("أسماء".containsSearchTerm("اسماء"))
    #expect("Straße".containsSearchTerm("STRASSE"))
  }

  @Test("what the system comparison finds is still found")
  func systemComparison() {
    #expect("Mañana".containsSearchTerm("manana"))
    #expect("Café".containsSearchTerm("CAFE"))
    #expect("всё".containsSearchTerm("все"))
    #expect("ฉันไปตลาด".containsSearchTerm("ตลาด"))
  }

  @Test("full-width letters match plain text in both directions")
  func fullWidthLetters() {
    #expect("Today".containsSearchTerm("ｔｏｄａｙ"))
    #expect("Ｔｏｄａｙ".containsSearchTerm("today"))
  }

  @Test("an unrelated or empty term matches nothing")
  func misses() {
    #expect(!"Łódź".containsSearchTerm("krakow"))
    #expect(!"Łódź".containsSearchTerm(""))
  }

  @Test("catalog search needs every term and reads letter variants")
  func catalogSearch() {
    let fields: [String?] = ["Łódź", nil, "Weekend trip"]
    #expect(LorvexCatalogSearch.matches("lodz trip", fields: fields))
    #expect(LorvexCatalogSearch.matches("TRIP LODZ", fields: fields))
    #expect(!LorvexCatalogSearch.matches("lodz berlin", fields: fields))
    #expect(LorvexCatalogSearch.matches("  ", fields: fields))
  }
}
