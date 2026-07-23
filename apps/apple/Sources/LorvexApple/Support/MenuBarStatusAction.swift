enum MenuBarStatusAction: CaseIterable {
  case openMain
  case refresh
  case quit

  var title: String {
    switch self {
    case .openMain:
      Self.openWindowTitle(LorvexWindowID.main.title)
    case .refresh: AppCommand.refresh.title
    case .quit:
      String(
        format: String(
          localized: "menubar.action.quit_app",
          defaultValue: "Quit %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        LorvexWindowID.main.title
      )
    }
  }

  private static func openWindowTitle(_ title: String) -> String {
    String(
      format: String(
        localized: "menubar.action.open_window",
        defaultValue: "Open %@",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      title
    )
  }

  var commandAction: MenuBarStatusCommandAction {
    switch self {
    case .openMain:
      .openWindow(.main)
    case .refresh:
      .appCommand(.refreshStore)
    case .quit:
      .quitApplication
    }
  }
}
