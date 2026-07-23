import Testing

@testable import LorvexCore

/// The `OSSignposter` phase vocabulary: its `domain.phase` labels are a stable
/// contract (a saved Instruments template matches on them), and its interval API
/// must stay callable. Signposts themselves are not unit-assertable — no tool is
/// recording under test — so this pins the vocabulary and exercises the API.
@Suite("LorvexSignpost vocabulary")
struct LorvexSignpostTests {

  @Test("phase labels are the frozen domain.phase vocabulary")
  func phaseLabelsAreStable() {
    let expected: [LorvexSignpost.Phase: String] = [
      .databaseOpen: "database.open",
      .databaseRead: "database.read",
      .databaseWrite: "database.write",
      .cloudSync: "cloud.sync",
      .eventKitIngest: "eventkit.ingest",
      .spotlightReplace: "spotlight.replace",
      .notificationsReplace: "notifications.replace",
      .refreshTotal: "refresh.total",
    ]
    // Every case is pinned and nothing is unmapped: a newly added phase forces
    // this table (and thus a deliberate vocabulary decision) to be updated.
    #expect(Set(LorvexSignpost.Phase.allCases) == Set(expected.keys))
    for phase in LorvexSignpost.Phase.allCases {
      #expect(phase.label == expected[phase])
    }
  }

  @Test("the interval API is callable and balanced")
  func intervalAPICallable() async {
    // begin/end round-trips without a recording tool attached.
    let interval = LorvexSignpost.begin(.databaseRead)
    LorvexSignpost.end(interval)

    // The sync bracket returns the body's value.
    let sum = LorvexSignpost.withInterval(.databaseWrite) { 2 + 3 }
    #expect(sum == 5)

    // The async bracket awaits the body and returns its value.
    let value = await LorvexSignpost.withInterval(.refreshTotal) {
      await Task.yield()
      return 7
    }
    #expect(value == 7)
  }
}
