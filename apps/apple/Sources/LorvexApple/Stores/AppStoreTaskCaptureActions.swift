import Foundation
import LorvexCore

extension AppStore {
  /// Signal the inline quick-add row of the current task surface to claim
  /// keyboard focus. ⌘N (the New Task command) calls this instead of opening
  /// a popup window — every `QuickAddRow` observes `quickAddFocusToken` and
  /// focuses its field when the value bumps.
  func requestQuickAddFocus() {
    quickAddFocusToken &+= 1
  }

  /// Global quick capture from the command palette and the menu bar: get the
  /// thought out of the user's head and into the default list (the Inbox unless
  /// the user chose another), undated, then leave them exactly where they were.
  ///
  /// Captured work deliberately claims no place on today. A day surface only
  /// means something if everything on it was actually committed to, so stamping
  /// every stray thought with today's date would refill the day with untriaged
  /// noise. The Today quick-add row, which does mean "today", uses
  /// `createInlineTask(_:destination:)` with `.today`.
  ///
  /// Because the new row may be invisible from wherever capture fired, the toast
  /// is the confirmation — this path neither navigates nor selects.
  ///
  /// `isCreating` covers only the write and the reads that show the new row, so
  /// a second submit in that window, a duplicate of the same capture, is
  /// dropped. The fan-out that follows (Spotlight, reminders, badge, widget,
  /// one sync cycle) runs after the flag is released; a slow cycle never holds
  /// the capture field.
  func createTask(title: String, notes: String) async {
    guard !isCreating else { return }
    isCreating = true
    let outcome = await commitCapturedTask(title: title, notes: notes)
    isCreating = false
    guard let outcome else { return }
    confirmCapture(outcome)
    await publishAfterTaskCreate()
  }

  /// What a capture that lands out of sight created: how many tasks, and the
  /// list the core filed them in.
  struct CaptureOutcome: Equatable {
    var count: Int
    var listID: String?
  }

  /// Write one captured task to the default list, undated, and reload the
  /// surfaces that show it. Returns what was created, or `nil` when the write
  /// failed (the error has already been presented).
  private func commitCapturedTask(title: String, notes: String) async -> CaptureOutcome? {
    guard
      let task = await performCanonicalMutation({
        try await core.createTask(title: title, notes: notes)
      })
    else { return nil }

    await reconcileAfterCommittedMutation(source: "macos.task.create.reconcile") {
      today = try await core.loadToday()
      lists = try await core.loadLists()
      try await reloadTaskWorkspaceIfLoadedReportingFailure()
    }
    return CaptureOutcome(count: 1, listID: task.listID)
  }

  /// The confirmation for a capture that lands out of sight: feedback plus a
  /// toast naming what was created and where.
  private func confirmCapture(_ outcome: CaptureOutcome) {
    feedbackProvider.playFeedback(.captureSubmitted)
    toastMessage = Self.captureToastMessage(
      count: outcome.count, listName: captureListName(outcome.listID))
  }

  /// The shown name of the list a capture landed in. The core files an
  /// undirected capture in the default list, or in the Inbox when no valid
  /// default is set, so a list this store has not loaded reads as the Inbox.
  private func captureListName(_ listID: String?) -> String {
    lists?.lists.first { $0.id == listID }?.displayName ?? LorvexListNaming.localizedInboxName
  }

  /// Confirmation for a capture that lands out of sight: the created count and
  /// the shown name of the list it landed in, pluralized through the catalog
  /// rather than a call-site branch.
  static func captureToastMessage(count: Int, listName: String) -> String {
    String(
      localized: "capture.toast.list",
      defaultValue: "Captured \(count) tasks to \(listName).",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Read a quick-add line against the user's lists and the logical today, the
  /// same parse the row previews while the user types and the one
  /// `createInlineTask(_:destination:)` commits.
  func captureParse(_ text: String) -> LorvexCaptureParse {
    LorvexCaptureParser.parse(
      text,
      lists: orderedLists.map(LorvexCaptureParser.ListOption.init(list:)),
      todayWeekday: logicalTodayWeekday,
      today: logicalTodayDateString)
  }

  /// The logical today's weekday, 1 = Sunday … 7 = Saturday, read from the
  /// logical day string in UTC so the device zone cannot shift it.
  var logicalTodayWeekday: Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: logicalTodayDateString) else { return 1 }
    return calendar.component(.weekday, from: date)
  }

  /// Create a task from an inline quick-add line without leaving the surface
  /// the user is typing in, so consecutive adds flow. No toast: the surface
  /// visibly gains the row.
  ///
  /// The line is parsed first ("Call the caterer tomorrow 3pm 20 min
  /// #offsite"). `destination` is where the task lands when the line names no
  /// place of its own: Today plans it for the logical today, a list files it
  /// there, the inbox leaves it undated. A day or `#list` written in the line
  /// overrides that default, a clock time with no day plans the task for
  /// today, and the typed line is kept as the task's raw input whenever
  /// it carried details.
  ///
  /// Lines typed back to back all land, in order: each commit (the write plus
  /// the reads that show the row) waits for the one before it instead of being
  /// dropped by a busy flag, and `isCreating` is never raised, so the row stays
  /// enabled and focused throughout. The fan-out (Spotlight, reminders, badge,
  /// widget, one sync cycle) runs after the commit and never gates the next
  /// line.
  func createInlineTask(_ text: String, destination: InlineCaptureDestination) async {
    guard let trimmed = text.trimmedNilIfEmpty else { return }
    let previous = inlineCaptureCommitTail
    let commit = Task { @MainActor in
      await previous?.value
      return await self.commitInlineTask(trimmed, destination: destination)
    }
    inlineCaptureCommitTail = Task { @MainActor in _ = await commit.value }
    guard await commit.value else { return }
    feedbackProvider.playFeedback(.captureSubmitted)
    await publishAfterTaskCreate()
  }

  /// Write one inline quick-add line and reload the surfaces that show it.
  /// Returns `false` when the write failed (the error has already been
  /// presented). Parsing happens here, after any earlier inline commit, so a
  /// `#list` naming a list created a moment ago resolves.
  private func commitInlineTask(
    _ trimmed: String, destination: InlineCaptureDestination
  ) async -> Bool {
    let parse = captureParse(trimmed)
    guard
      await performCanonicalMutation({
        var draft = TaskCreateDraft(title: parse.title)
        draft.priority = parse.priority ?? draft.priority
        draft.estimatedMinutes = parse.estimatedMinutes
        draft.tags = parse.tags.isEmpty ? nil : parse.tags
        draft.rawInput = parse.hasDetails ? trimmed : nil
        draft.listID = parse.listID
        if case .list(let listID) = destination, draft.listID == nil { draft.listID = listID }
        if let offset = parse.resolvedPlannedDayOffset {
          draft.plannedDate = try storageDate(daysFromLogicalToday: offset)
        } else if destination == .today {
          draft.plannedDate = try storageDate(daysFromLogicalToday: 0)
        }
        draft.plannedTime = parse.plannedTime
        if let offset = parse.resolvedDueDayOffset {
          draft.dueDate = try storageDate(daysFromLogicalToday: offset)
        }
        draft.recurrence = parse.recurrence
        return try await core.createTask(draft)
      }) != nil
    else { return false }

    await reconcileAfterCommittedMutation(source: "macos.task.create_inline.reconcile") {
      today = try await core.loadToday()
      lists = try await core.loadLists()
      // A planned task also lands in the calendar's scheduled lane.
      try await refreshCurrentCalendarTimeline()
      try await loadSelectedListDetail()
      try await reloadTaskWorkspaceIfLoadedReportingFailure()
    }
    return true
  }

  /// The fan-out a durable task create owes the rest of the system: the
  /// Spotlight index, reminders, the badge, the widget snapshot, and one sync
  /// cycle. Awaiting it means the local surfaces reflect the caller's write;
  /// the sync cycle it starts runs on without being awaited
  /// (``republishSurfacesAfterLocalMutation()``). A create that lands while a
  /// pass is in flight coalesces into one trailing pass rather than running a
  /// second reminder re-plan against the same notification center.
  func publishAfterTaskCreate() async {
    await taskCreateFanOutFlight.run {
      await reindexTasksForSpotlight()
      await republishSurfacesAfterLocalMutation()
    }
  }
}

/// Where an inline quick-add line lands when the line itself names no day or
/// list: the surface the row sits on decides.
enum InlineCaptureDestination: Equatable {
  /// Planned for the logical today (the Today page).
  case today
  /// Filed in one list (a list page or a list-scoped task workspace).
  case list(LorvexList.ID)
  /// Undated, in the default list (the unscoped task workspace).
  case inbox
}
