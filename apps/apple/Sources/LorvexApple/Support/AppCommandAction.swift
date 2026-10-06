enum AppCommandAction: Equatable {
  /// Focus the inline quick-add of the current task surface, navigating to
  /// Tasks first when the active workspace has no quick-add to focus.
  case focusQuickAdd
  /// Open the Quick Capture window over the current app.
  case showQuickCapture
  case refreshStore
}
