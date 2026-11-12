import LorvexCore

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
        localized: "watch.unavailable.capture", defaultValue: "Open Lorvex on iPhone to capture new tasks.",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
    return nil
  }

  /// What to say about the action that just failed, or nil when the last
  /// error was not an action's. An action tried before the iPhone has sent the
  /// watch any copy of Today cannot be journaled, and says so.
  public var actionFailureText: String? {
    guard let error, errorIsFromAction else { return nil }
    if let replicaError = error as? LorvexWatchReplicaStoreError,
      replicaError == .baselineUnavailable || replicaError == .appGroupUnavailable
    {
      return LorvexWatchCalmCopy.openPhoneFirst
    }
    return LorvexWatchCalmCopy.actionFailed
  }

  /// What a rejected action was for: the captured title, or the task's title
  /// or habit's name when the watch has listed it since launch.
  public func subject(of command: LorvexWatchRejectedCommand) -> String? {
    switch command.mutation {
    case .captureTask(let title):
      title
    case .completeTask(let id), .startTask(let id), .pauseTask(let id), .cancelTask(let id),
      .deferTaskToTomorrow(let id, _), .completeHabit(let id, _):
      knownTitles[id]
    }
  }

  private static var refreshingUnavailableReason: String {
    String(
      localized: "watch.unavailable.refreshing", defaultValue: "Wait for Lorvex to finish refreshing.",
      table: "Localizable", bundle: WatchL10n.bundle)
  }
}
