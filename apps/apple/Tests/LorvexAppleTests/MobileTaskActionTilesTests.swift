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

  @Test("a name has its tile's share of the row, less the grid spacing and the tile's padding")
  func labelTextWidth() {
    // Four tiles across 370pt: (370 − 3 × 8) / 4 − 2 × 4.
    #expect(MobileTaskActionLabelFit.textWidth(rowWidth: 370, columns: 4) == 78.5)
    #expect(MobileTaskActionLabelFit.textWidth(rowWidth: 0, columns: 4) == 0)
  }

  @Test("the names keep their size while every word fits, and shrink together when one does not")
  func labelScale() {
    let english = ["Start", "Defer", "Someday", "Cancel"]
    #expect(MobileTaskActionLabelFit.scale(titles: english, size: 13, width: 78.5) == 1)
    // "Когда-нибудь" is one word wider than a phone's tile, so the whole row
    // shrinks to the size at which it fits.
    let russian = ["Начать", "Отложить", "Когда-нибудь", "Отменить"]
    let scale = MobileTaskActionLabelFit.scale(titles: russian, size: 13, width: 78.5)
    #expect(scale < 1)
    #expect(scale > MobileTaskActionLabelFit.minimumScale)
    // A name of several words wraps between them, so only its widest word
    // has to fit.
    #expect(MobileTaskActionLabelFit.scale(titles: ["إلغاء المهمة"], size: 13, width: 60) == 1)
    // An unmeasured row keeps the full size, and no row goes below the floor.
    #expect(MobileTaskActionLabelFit.scale(titles: russian, size: 13, width: 0) == 1)
    #expect(
      MobileTaskActionLabelFit.scale(titles: russian, size: 13, width: 20)
        == MobileTaskActionLabelFit.minimumScale)
  }
}
