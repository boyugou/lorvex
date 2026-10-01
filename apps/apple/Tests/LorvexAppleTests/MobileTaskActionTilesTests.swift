import LorvexCore
import Testing

@testable import LorvexMobile

@Suite("Task detail action tiles")
struct MobileTaskActionTilesTests {
  @Test("each status shows only the actions it allows, and a resolved task shows none")
  func tilesPerStatus() {
    #expect(MobileTaskActionSection.tiles(for: .open) == [.start, .deferTask, .someday, .cancel])
    #expect(MobileTaskActionSection.tiles(for: .inProgress) == [.pause, .deferTask, .cancel])
    #expect(MobileTaskActionSection.tiles(for: .someday) == [.complete, .deferTask, .cancel])
    #expect(MobileTaskActionSection.tiles(for: .completed).isEmpty)
    #expect(MobileTaskActionSection.tiles(for: .cancelled).isEmpty)
  }
}
