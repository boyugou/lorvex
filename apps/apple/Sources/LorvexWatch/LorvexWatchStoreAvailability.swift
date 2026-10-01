extension LorvexWatchStore {
  /// True when a task action can run now: nothing is in flight and there is a
  /// write path.
  public var canMutateTasks: Bool {
    !isLoading && canWrite
  }

  public var canCaptureTask: Bool {
    guard !captureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard !isLoading else { return false }
    return canWrite
  }

  /// True when the store can apply mutations — either via the writable core
  /// backend, or via a mutation forwarder on the snapshot backend.
  public var canWrite: Bool {
    switch backend {
    case .core: return true
    case .snapshot, .snapshotUnavailable: return mutationForwarder != nil
    }
  }

  /// Why the task actions cannot run, or nil when they can.
  public var taskActionUnavailableReason: String? {
    guard !isLoading else { return Self.refreshingUnavailableReason }
    if case .core = backend {
      return nil
    }
    if mutationForwarder == nil {
      return String(
        localized: "watch.unavailable.task_action", defaultValue: "Open Lorvex on iPhone to change tasks.",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
    return nil
  }

  public var captureUnavailableReason: String? {
    guard !isLoading else { return Self.refreshingUnavailableReason }
    if case .core = backend {
      return nil
    }
    if mutationForwarder == nil {
      return String(
        localized: "watch.unavailable.capture", defaultValue: "Open Lorvex on iPhone or Mac to capture new tasks.",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
    return nil
  }

  private static var refreshingUnavailableReason: String {
    String(
      localized: "watch.unavailable.refreshing", defaultValue: "Wait for Lorvex to finish refreshing.",
      table: "Localizable", bundle: WatchL10n.bundle)
  }
}
