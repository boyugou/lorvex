import Foundation
import SwiftUI
import Testing

@testable import LorvexApple

/// The main window's columns: the window's floor is the sum of the visible
/// columns, and a screen too narrow for all three gives the sidebar's place to
/// the inspector.
@MainActor
struct MainWindowLayoutTests {
  /// The visible width of a 13-inch display at a larger text size.
  private static let narrow: CGFloat = 1147
  private static let wide: CGFloat = 1440

  private static func layout(screenWidth: CGFloat?) -> MainWindowLayout {
    let layout = MainWindowLayout()
    layout.screenDidChange(width: screenWidth, inspectorOpen: false)
    return layout
  }

  @Test("Each set of columns needs its own width: 1320, 1000, 1088, 768")
  func columnWidths() {
    #expect(MainWindowLayout.columnsWidth(sidebar: true, inspector: true) == 1320)
    #expect(MainWindowLayout.columnsWidth(sidebar: true, inspector: false) == 1000)
    #expect(MainWindowLayout.columnsWidth(sidebar: false, inspector: true) == 1088)
    #expect(MainWindowLayout.columnsWidth(sidebar: false, inspector: false) == 768)
  }

  @Test("On a narrow screen the inspector hides the sidebar, and closing it shows the sidebar again")
  func narrowScreenSwapsTheSidebarForTheInspector() {
    let layout = Self.layout(screenWidth: Self.narrow)
    #expect(!layout.fitsAllColumns)

    layout.inspectorDidChange(isOpen: true)
    #expect(layout.columnVisibility == .detailOnly)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1088)

    layout.inspectorDidChange(isOpen: false)
    #expect(layout.columnVisibility == .all)
    #expect(layout.minimumContentWidth(inspectorOpen: false) == 1000)
  }

  @Test("On a wide screen the sidebar stays beside the inspector")
  func wideScreenKeepsTheSidebar() {
    let layout = Self.layout(screenWidth: Self.wide)
    layout.inspectorDidChange(isOpen: true)
    #expect(layout.columnVisibility == .all)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1320)
  }

  @Test("The floor never exceeds the screen, even without the sidebar")
  func floorStaysWithinTheScreen() {
    let layout = Self.layout(screenWidth: 1024)
    layout.inspectorDidChange(isOpen: true)
    #expect(layout.columnVisibility == .detailOnly)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1024)
  }

  @Test("A sidebar the person hid stays hidden after the inspector closes")
  func personHiddenSidebarStaysHidden() {
    let layout = Self.layout(screenWidth: Self.narrow)
    layout.columnVisibility = .detailOnly
    #expect(!layout.sidebarVisibilityDidChange(inspectorOpen: false))

    layout.inspectorDidChange(isOpen: true)
    layout.inspectorDidChange(isOpen: false)
    #expect(layout.columnVisibility == .detailOnly)
    #expect(layout.minimumContentWidth(inspectorOpen: false) == 768)
  }

  @Test("Showing the sidebar beside an open inspector closes the inspector only on a narrow screen")
  func showingTheSidebarClosesTheInspectorWithoutRoom() {
    let narrow = Self.layout(screenWidth: Self.narrow)
    narrow.inspectorDidChange(isOpen: true)
    narrow.columnVisibility = .all
    #expect(narrow.sidebarVisibilityDidChange(inspectorOpen: true))
    // Once the inspector closes, the sidebar the person showed stays.
    narrow.inspectorDidChange(isOpen: false)
    #expect(narrow.columnVisibility == .all)

    let wide = Self.layout(screenWidth: Self.wide)
    wide.columnVisibility = .detailOnly
    wide.inspectorDidChange(isOpen: true)
    wide.columnVisibility = .all
    #expect(!wide.sidebarVisibilityDidChange(inspectorOpen: true))
  }

  @Test("The layout's own sidebar changes never ask the inspector to close")
  func layoutChangesDoNotCloseTheInspector() {
    let layout = Self.layout(screenWidth: Self.narrow)
    layout.inspectorDidChange(isOpen: true)
    #expect(!layout.sidebarVisibilityDidChange(inspectorOpen: true))
    layout.inspectorDidChange(isOpen: false)
    #expect(!layout.sidebarVisibilityDidChange(inspectorOpen: false))
  }

  @Test("Moving between a narrow and a wide screen with the inspector open re-fits the sidebar")
  func screenChangesRefitTheColumns() {
    let layout = Self.layout(screenWidth: Self.narrow)
    layout.inspectorDidChange(isOpen: true)
    #expect(layout.columnVisibility == .detailOnly)

    layout.screenDidChange(width: Self.wide, inspectorOpen: true)
    #expect(layout.columnVisibility == .all)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1320)

    layout.screenDidChange(width: Self.narrow, inspectorOpen: true)
    #expect(layout.columnVisibility == .detailOnly)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1088)
  }

  @Test("Before the window is on a screen, all columns count as fitting and the floor is uncapped")
  func unknownScreenFitsEverything() {
    let layout = Self.layout(screenWidth: nil)
    #expect(layout.fitsAllColumns)
    layout.inspectorDidChange(isOpen: true)
    #expect(layout.columnVisibility == .all)
    #expect(layout.minimumContentWidth(inspectorOpen: true) == 1320)
  }
}
