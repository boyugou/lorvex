import AppKit
import LorvexCore

/// Builds the NSMenu returned for the macOS Dock right-click menu.
///
/// The builder is a pure factory: it receives a handler closure for each
/// `LorvexQuickAction` and returns a fully-configured `NSMenu`. The handler
/// is invoked on the main actor when the user selects a menu item, so callers
/// can pass a closure that opens a URL or dispatches directly into the app
/// without needing a concrete `AppStore` reference.
@MainActor
enum LorvexDockMenuBuilder {
  /// Returns an `NSMenu` containing one item per `LorvexQuickAction` case, in
  /// `CaseIterable` order. Selecting an item calls `handler` with the
  /// corresponding action.
  static func build(handler: @escaping @MainActor (LorvexQuickAction) -> Void) -> NSMenu {
    let menu = NSMenu()
    for action in LorvexQuickAction.allCases {
      let item = makeItem(for: action, handler: handler)
      menu.addItem(item)
    }
    return menu
  }

  // MARK: - Private

  private static func makeItem(
    for action: LorvexQuickAction,
    handler: @escaping @MainActor (LorvexQuickAction) -> Void
  ) -> NSMenuItem {
    let target = DockMenuItemTarget(action: action, handler: handler)
    let item = NSMenuItem(
      title: action.localizedTitle,
      action: #selector(DockMenuItemTarget.performAction),
      keyEquivalent: ""
    )
    item.image = NSImage(systemSymbolName: action.systemImageName, accessibilityDescription: nil)
    item.target = target
    // Retain the target for the lifetime of the menu item.
    item.representedObject = target
    return item
  }
}

// MARK: - DockMenuItemTarget

/// Retains the per-item handler and dispatches it when AppKit fires the action.
@MainActor
private final class DockMenuItemTarget: NSObject {
  private let action: LorvexQuickAction
  private let handler: @MainActor (LorvexQuickAction) -> Void

  init(action: LorvexQuickAction, handler: @escaping @MainActor (LorvexQuickAction) -> Void) {
    self.action = action
    self.handler = handler
  }

  @objc func performAction() {
    handler(action)
  }
}
