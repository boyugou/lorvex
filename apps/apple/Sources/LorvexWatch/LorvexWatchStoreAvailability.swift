extension LorvexWatchStore {
  public var canCompletePrimaryTask: Bool {
    canMutatePrimaryTask
  }

  public var canCancelPrimaryTask: Bool {
    canMutatePrimaryTask
  }

  public var canDeferPrimaryTask: Bool {
    canMutatePrimaryTask
  }

  public var canRemovePrimaryTaskFromFocus: Bool {
    canMutatePrimaryTask
  }

  public var canCaptureTask: Bool {
    guard !captureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard !isLoading else { return false }
    return canWrite
  }

  public var canMutatePrimaryTask: Bool {
    guard primaryTask != nil, !isLoading else { return false }
    return canWrite
  }

  /// True when a queued focus task (a "Next" row, not the primary) can be mutated.
  ///
  /// Unlike `canMutatePrimaryTask`, this does not require `primaryTask`; the queue
  /// rows act on their own id. Still gated on no in-flight mutation and a writable
  /// path, matching how the primary-task buttons gate themselves.
  public var canMutateQueuedTask: Bool {
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

  public var completionUnavailableReason: String? {
    mutationUnavailableReason(
      snapshotMessage: String(
        localized: "watch.unavailable.complete", defaultValue: "Open Lorvex on iPhone or Mac to complete this task.",
        table: "Localizable", bundle: WatchL10n.bundle))
  }

  public var focusMutationUnavailableReason: String? {
    mutationUnavailableReason(
      snapshotMessage: String(
        localized: "watch.unavailable.focus_mutation", defaultValue: "Open Lorvex on iPhone or Mac to change focus.",
        table: "Localizable", bundle: WatchL10n.bundle))
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

  private func mutationUnavailableReason(snapshotMessage: String) -> String? {
    guard primaryTask != nil else { return nil }
    guard !isLoading else { return Self.refreshingUnavailableReason }
    if case .core = backend {
      return nil
    }
    if mutationForwarder == nil {
      return snapshotMessage
    }
    return nil
  }

  private static var refreshingUnavailableReason: String {
    String(
      localized: "watch.unavailable.refreshing", defaultValue: "Wait for Lorvex to finish refreshing.",
      table: "Localizable", bundle: WatchL10n.bundle)
  }
}
