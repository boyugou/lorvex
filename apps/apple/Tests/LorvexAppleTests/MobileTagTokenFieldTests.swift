import Testing

@testable import LorvexMobile

/// Tags typed into the tag field join the list once each, whether Return adds
/// them or a Save folds in what was still being typed.
@Test
func tagFieldMergesTypedTagsOncePerSpelling() {
  #expect(MobileTagTokenField.merging("finance, q4 ", into: ["home"]) == ["home", "finance", "q4"])
  // A tag already present in another letter case is not added again.
  #expect(MobileTagTokenField.merging("Home,, ", into: ["home"]) == ["home"])
  #expect(MobileTagTokenField.merging("  ", into: ["home"]) == ["home"])
}
