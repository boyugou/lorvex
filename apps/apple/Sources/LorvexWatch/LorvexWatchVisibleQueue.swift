enum LorvexWatchVisibleQueue {
  static func taskIDs(focusTaskIDs: [String], activeTaskID: String?) -> [String] {
    guard let activeTaskID else {
      return Array(focusTaskIDs.dropFirst())
    }
    return focusTaskIDs.filter { $0 != activeTaskID }
  }
}
