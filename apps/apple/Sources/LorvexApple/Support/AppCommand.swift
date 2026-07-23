import SwiftUI

enum AppCommand: String, CaseIterable, Identifiable {
  case newTask
  case refresh

  var id: String { rawValue }

  var title: String {
    switch self {
    case .newTask:
      String(localized: "app.commands.new_task", defaultValue: "New Task", table: "Localizable", bundle: LorvexL10n.bundle)
    case .refresh:
      String(localized: "app.command.refresh", defaultValue: "Refresh", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .newTask: "plus.circle"
    case .refresh: "arrow.clockwise"
    }
  }

  var keyboardShortcut: KeyboardShortcut {
    switch self {
    case .newTask:
      KeyboardShortcut("n", modifiers: [.command])
    case .refresh:
      KeyboardShortcut("r", modifiers: [.command])
    }
  }

  var action: AppCommandAction {
    switch self {
    case .newTask: .focusQuickAdd
    case .refresh: .refreshStore
    }
  }

  @MainActor
  func perform(in store: AppStore) {
    LorvexCommandDispatcher(store: store) { _ in }.perform(action)
  }
}
