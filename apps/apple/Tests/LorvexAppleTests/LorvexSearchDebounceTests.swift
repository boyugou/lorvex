import LorvexCore
import Testing

/// Search fields wait for a typing pause before a typed query runs, and a
/// search a newer query superseded reports that it should not run.
struct LorvexSearchDebounceTests {
  @Test("An empty query searches at once")
  func emptyQuerySearchesAtOnce() async {
    let clock = ContinuousClock()
    let start = clock.now
    #expect(await LorvexSearchDebounce.shouldSearch(""))
    #expect(await LorvexSearchDebounce.shouldSearch("  \n"))
    #expect(clock.now - start < LorvexSearchDebounce.pause)
  }

  @Test("A typed query searches after the typing pause")
  func typedQueryWaitsForThePause() async {
    let clock = ContinuousClock()
    let start = clock.now
    #expect(await LorvexSearchDebounce.shouldSearch("milk"))
    #expect(clock.now - start >= LorvexSearchDebounce.pause)
  }

  @Test("A superseded search does not run")
  func cancelledSearchDoesNotRun() async {
    let search = Task { await LorvexSearchDebounce.shouldSearch("milk") }
    search.cancel()
    #expect(await search.value == false)
  }
}
