enum MenuBarStatusCommandAction: Equatable {
  case openWindow(LorvexWindowID)
  case appCommand(AppCommandAction)
  case taskCommand(TaskCommandAction)
  case quitApplication
}
