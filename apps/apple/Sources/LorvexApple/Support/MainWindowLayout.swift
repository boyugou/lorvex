import SwiftUI

/// The width range of the main window's trailing inspector column.
enum MainWindowLayoutMetrics {
  // The task detail's content (priority chips, action row, checklist rows with
  // trailing menus) needs ~300pt to render without its trailing controls
  // clipping, so the inspector must not be squeezed below that.
  static let inspectorMinWidth: CGFloat = 300
  static let inspectorIdealWidth: CGFloat = 320
  static let inspectorMaxWidth: CGFloat = 380
}

/// The main window's columns: whether the sidebar shows, how wide the window
/// must stay for the columns on screen, and how much room its screen gives.
///
/// The window's minimum width is the sum of its visible columns: the
/// two-column base of sidebar and workspace, less the sidebar while it is
/// hidden, plus the inspector while it is open, and never more than the screen
/// is wide, so the columns are never wider than the window that holds them.
///
/// A screen narrower than all three columns cannot show them side by side.
/// There the inspector takes the sidebar's place, the way a Mac split view
/// collapses its sidebar when the window runs out of room: opening the
/// inspector hides the sidebar, and closing it shows the sidebar again, unless
/// the person had hidden the sidebar themselves. Showing the sidebar while the
/// inspector is open on such a screen closes the inspector instead, because
/// the person asked for the sidebar last. On a screen wide enough for all
/// three, the sidebar stays and the window grows to fit the inspector.
///
/// `ContentView` owns one layout for the main window, binds the split view's
/// column visibility to ``columnVisibility``, and reports the inspector
/// opening and closing and the sidebar showing and hiding.
/// `WindowMinWidthEnforcer` holds the AppKit window to
/// ``minimumContentWidth(inspectorOpen:)`` and reports the screen's width.
@MainActor
@Observable
final class MainWindowLayout {
  /// The split view's column visibility, which the toolbar's sidebar button
  /// and View ▸ Show Sidebar also set.
  var columnVisibility: NavigationSplitViewVisibility = .all

  /// The visible width of the window's screen, or nil before the window is on
  /// a screen.
  private(set) var screenWidth: CGFloat?

  /// Whether the layout hid the sidebar to make room for the inspector, so
  /// closing the inspector shows the sidebar again.
  private(set) var sidebarHiddenForInspector = false

  var isSidebarVisible: Bool { columnVisibility != .detailOnly }

  /// Whether the screen fits the sidebar, the workspace, and the inspector
  /// side by side. True while the screen is unknown.
  var fitsAllColumns: Bool {
    guard let screenWidth else { return true }
    return Self.columnsWidth(sidebar: true, inspector: true) <= screenWidth
  }

  /// The window's minimum content width for the columns on screen, never more
  /// than the screen is wide.
  func minimumContentWidth(inspectorOpen: Bool) -> CGFloat {
    let width = Self.columnsWidth(sidebar: isSidebarVisible, inspector: inspectorOpen)
    guard let screenWidth else { return width }
    return min(width, screenWidth)
  }

  /// The width a set of columns needs. The two-column base
  /// (`LorvexWindowID.main.minimumContentSize`) budgets the sidebar at its
  /// ideal width, so a hidden sidebar gives that width back; an open
  /// inspector adds its ideal width.
  static func columnsWidth(sidebar: Bool, inspector: Bool) -> CGFloat {
    var width = LorvexWindowID.main.minimumContentSize.width
    if !sidebar { width -= SidebarMetrics.columnIdealWidth }
    if inspector { width += MainWindowLayoutMetrics.inspectorIdealWidth }
    return width
  }

  /// Fits the columns to the inspector opening or closing.
  func inspectorDidChange(isOpen: Bool) {
    if isOpen {
      makeRoomForInspector()
    } else {
      showSidebarHiddenForInspector()
    }
  }

  /// Records the visible width of the window's screen, after the window moves
  /// to another screen or the screen's resolution changes, and fits the
  /// columns to it.
  func screenDidChange(width: CGFloat?, inspectorOpen: Bool) {
    guard width != screenWidth else { return }
    screenWidth = width
    guard inspectorOpen else { return }
    if fitsAllColumns {
      showSidebarHiddenForInspector()
    } else {
      makeRoomForInspector()
    }
  }

  /// Takes note of the sidebar showing or hiding, and returns whether the
  /// inspector must close: true when the sidebar was shown while the inspector
  /// is open on a screen without room for both.
  func sidebarVisibilityDidChange(inspectorOpen: Bool) -> Bool {
    guard isSidebarVisible else { return false }
    sidebarHiddenForInspector = false
    return inspectorOpen && !fitsAllColumns
  }

  private func makeRoomForInspector() {
    guard !fitsAllColumns, isSidebarVisible else { return }
    sidebarHiddenForInspector = true
    columnVisibility = .detailOnly
  }

  private func showSidebarHiddenForInspector() {
    guard sidebarHiddenForInspector else { return }
    sidebarHiddenForInspector = false
    columnVisibility = .all
  }
}
