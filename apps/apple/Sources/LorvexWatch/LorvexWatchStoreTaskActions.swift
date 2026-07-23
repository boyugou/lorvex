import Foundation
import LorvexCore
import LorvexWidgetKitSupport

extension LorvexWatchStore {
  /// Completes the primary focus task and refreshes state.
  ///
  /// When the backend is the read-only snapshot and a mutation forwarder is
  /// configured, the mutation is forwarded to the paired iPhone instead of
  /// applied locally.
  public func completePrimaryTask() async {
    guard let task = primaryTask else { return }
    await performMutation(.completeTask(id: task.id)) { core in
      _ = try await core.completeTask(id: task.id)
    }
  }

  /// Completes one of today's habits from the wrist. Done habits are no-ops.
  /// The optimistic progress bump lives in `applyOptimisticUpdate`, so it lands
  /// only after the command is durably journaled on the watch. A later terminal
  /// phone rejection remains visible in the delivery section.
  public func completeHabit(id: String) async {
    guard let index = habits.firstIndex(where: { $0.id == id }),
      !habits[index].isDoneToday
    else { return }
    do {
      let date = try await mutationLogicalDay()
      await performMutation(.completeHabit(id: id, date: date)) { core in
        _ = try await core.completeHabit(id: id, date: date)
      }
    } catch {
      self.error = error
    }
  }

  /// Cancels the primary focus task occurrence and refreshes state. If the task
  /// repeats, the series continues with its next occurrence.
  public func cancelPrimaryTask() async {
    guard let task = primaryTask else { return }
    await performMutation(.cancelTask(id: task.id)) { core in
      _ = try await core.cancelTask(id: task.id)
    }
  }

  /// Defers the primary focus task until tomorrow and refreshes state.
  public func deferPrimaryTaskToTomorrow() async {
    guard let task = primaryTask else { return }
    do {
      let tomorrow = try await tomorrowDate()
      let plannedDate = LorvexDateFormatters.ymdUTC.string(from: tomorrow)
      await performMutation(.deferTaskToTomorrow(id: task.id, plannedDate: plannedDate)) { core in
        _ = try await core.deferTask(id: task.id, until: tomorrow)
      }
    } catch {
      self.error = error
    }
  }

  /// Removes the primary task from today's focus plan and refreshes state.
  public func removePrimaryTaskFromFocus() async {
    guard let task = primaryTask else { return }
    do {
      let date = try await mutationLogicalDay()
      await performMutation(.removeFromFocus(id: task.id, date: date)) { core in
        _ = try await core.removeFromCurrentFocus(date: date, taskID: task.id)
      }
    } catch {
      self.error = error
    }
  }

  /// Completes a specific queued focus task (identified by id) and refreshes state.
  ///
  /// Unlike `completePrimaryTask`, this acts on any task in the focus queue, so the
  /// watch's "Next" rows can be completed without first promoting them to primary.
  public func completeTask(id: LorvexTask.ID) async {
    await performMutation(.completeTask(id: id)) { core in
      _ = try await core.completeTask(id: id)
    }
  }

  /// Defers a specific queued focus task until tomorrow and refreshes state.
  public func deferTaskToTomorrow(id: LorvexTask.ID) async {
    do {
      let tomorrow = try await tomorrowDate()
      let plannedDate = LorvexDateFormatters.ymdUTC.string(from: tomorrow)
      await performMutation(.deferTaskToTomorrow(id: id, plannedDate: plannedDate)) { core in
        _ = try await core.deferTask(id: id, until: tomorrow)
      }
    } catch {
      self.error = error
    }
  }

  /// Tomorrow relative to the materialized product day, anchored at UTC
  /// midnight for the planned-date storage convention.
  private func tomorrowDate() async throws -> Date {
    let day = try await mutationLogicalDay()
    guard
      let tomorrow = LorvexDateFormatters.ymdUTCAddingDays(day, days: 1),
      let date = LorvexDateFormatters.ymdUTC.date(from: tomorrow)
    else {
      throw LorvexCoreError.validation(
        field: "date", message: "The current logical day is invalid.")
    }
    return date
  }

  private func mutationLogicalDay() async throws -> String {
    switch backend {
    case .core(let core):
      if let logicalDayOverride { return logicalDayOverride }
      return try await core.getSessionContext().date
    case .snapshot:
      guard let logicalDay else {
        throw LorvexCoreError.unsupportedOperation(
          "Refresh the watch snapshot before applying a day-scoped action.")
      }
      return logicalDay
    case .snapshotUnavailable:
      throw LorvexCoreError.unsupportedOperation(
        "A watch snapshot is required before applying a day-scoped action.")
    }
  }

  /// Creates an inbox task from the watch quick-capture draft.
  public func captureTask() async {
    let trimmedTitle = captureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    switch backend {
    case .core(let core):
      guard !isLoading else { return }
      isLoading = true
      error = nil
      defer { isLoading = false }
      do {
        _ = try await core.createTask(title: trimmedTitle, notes: "")
        captureTitle = ""
      } catch {
        self.error = error
      }
    case .snapshot, .snapshotUnavailable:
      guard !isLoading else { return }
      guard let forwarder = mutationForwarder else {
        error = LorvexCoreError.unsupportedOperation(
          String(
            localized: "watch.error.capture_forwarder_required", defaultValue: "Open Lorvex on iPhone or Mac to capture new tasks.",
            table: "Localizable", bundle: WatchL10n.bundle)
        )
        return
      }
      // The production forwarder returns only after the command is durably
      // journaled on the watch. Clear the draft and show a pending confirmation
      // after that persistence boundary — queueing is not application, and an
      // enqueue failure must leave the user's text intact.
      let pendingTitle = trimmedTitle
      isLoading = true
      error = nil
      defer { isLoading = false }
      do {
        try await forwarder.forward(.captureTask(title: pendingTitle))
        // The main actor can re-enter while awaiting persistence. Do not erase
        // newer text the user typed while the original title was being queued.
        if captureTitle.trimmingCharacters(in: .whitespacesAndNewlines) == pendingTitle {
          captureTitle = ""
        }
      } catch {
        self.error = error
      }
    }
  }

  // MARK: - Shared dispatch

  /// Dispatches a mutation through the writable core (direct path) or via the
  /// forwarder when the backend is read-only. Errors from either path are
  /// surfaced on `self.error`.
  func performMutation(
    _ mutation: LorvexWatchMutation,
    coreOperation: @escaping (any LorvexCoreServicing) async throws -> Void
  ) async {
    switch backend {
    case .core(let core):
      isLoading = true
      error = nil
      defer { isLoading = false }
      do {
        try await coreOperation(core)
        await refresh()
      } catch {
        self.error = error
      }
    case .snapshot, .snapshotUnavailable:
      guard let forwarder = mutationForwarder else {
        error = LorvexCoreError.unsupportedOperation(
          String(
            localized: "watch.error.forwarder_required", defaultValue: "Open Lorvex on iPhone or Mac to apply this action.",
            table: "Localizable", bundle: WatchL10n.bundle)
        )
        return
      }
      isLoading = true
      error = nil
      defer { isLoading = false }
      do {
        try await forwarder.forward(mutation)
        // Apply an optimistic update so the UI reflects the action immediately.
        // The next phone-pushed snapshot is the source of truth and will overwrite
        // this optimistic state when it arrives.
        applyOptimisticUpdate(for: mutation)
      } catch {
        self.error = error
      }
    }
  }

}
