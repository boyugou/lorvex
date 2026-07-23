import SwiftUI

enum AppCommandMenu: CaseIterable {
  case workspace
  case navigate
  case task

  var title: String {
    switch self {
    case .workspace:
      String(localized: "app.command_menu.workspace", defaultValue: "Workspace", table: "Localizable", bundle: LorvexL10n.bundle)
    case .navigate:
      String(localized: "app.command_menu.navigate", defaultValue: "Navigate", table: "Localizable", bundle: LorvexL10n.bundle)
    case .task:
      String(localized: "app.command_menu.task", defaultValue: "Task", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
