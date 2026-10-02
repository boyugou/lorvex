#if DEBUG
  import Foundation
  import LorvexCore
  import LorvexWidgetKitSupport

  /// The `-lorvexUIPreview` launch of the watch app, which
  /// `script/watch_sim_screenshots.sh` uses: a replica written from a fixed
  /// sample day so every page can be captured headlessly on a simulator with no
  /// paired phone pushing snapshots. `-lorvexUIPreviewPage <today|habits|capture>`
  /// picks the page to open and `-lorvexUIPreviewActions` opens the lead task's
  /// actions. Mutations go to a forwarder that accepts and drops them, so the
  /// buttons are live and their optimistic updates show.
  public enum LorvexWatchUIPreview {
    public static var isRequested: Bool { CommandLine.arguments.contains("-lorvexUIPreview") }

    public static var page: LorvexWatchPage {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-lorvexUIPreviewPage"), index + 1 < arguments.count
      else { return .today }
      return LorvexWatchPage(rawValue: arguments[index + 1]) ?? .today
    }

    public static var opensActions: Bool { CommandLine.arguments.contains("-lorvexUIPreviewActions") }

    /// Accepts every mutation and applies nothing: the preview has no phone,
    /// and the optimistic update is what a capture shows.
    public static let forwarder: any LorvexWatchMutationForwarding = DroppingForwarder()

    private struct DroppingForwarder: LorvexWatchMutationForwarding {
      func forward(_ mutation: LorvexWatchMutation) async throws {}
    }

    /// Writes the sample replica and returns its URL. The day is built around
    /// `now`: a started task whose saved time runs from 20 minutes ago to 25
    /// minutes ahead (the running lead), a started task without a time, an
    /// overdue task, a task timed later today, and one with only an estimate,
    /// written in the language the interface runs in (``LorvexSampleText``).
    public static func writeReplica(now: Date = Date()) throws -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("lorvex-watch-ui-preview", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
      let envelope = try LorvexWatchReplicaEnvelope(
        workspaceInstanceID: workspaceInstanceID,
        snapshotData: JSONEncoder().encode(snapshot(now: now)))
      try envelope.wireData().write(to: url, options: [.atomic])
      return url
    }

    static let workspaceInstanceID = "d1e5f0a4-6b2c-4c8e-9f3a-2b7c9d1e0f5a"

    static func snapshot(now: Date) -> WidgetSnapshot {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .current
      let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
      let nowMinutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 0)
      let logicalDay = String(
        format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
      func clock(_ minutes: Int) -> String {
        let bounded = min(max(minutes, 0), 23 * 60 + 59)
        return String(format: "%02d:%02d", bounded / 60, bounded % 60)
      }
      let open = LorvexTask.Status.open.rawValue
      let started = LorvexTask.Status.inProgress.rawValue
      let yesterday = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: -1)
      let text = LorvexSampleText(language: .running)
      return WidgetSnapshot(
        generatedAt: LorvexDateFormatters.iso8601.string(from: now),
        workspaceInstanceID: workspaceInstanceID,
        localChangeSequence: 1,
        timezone: TimeZone.current.identifier,
        logicalDay: logicalDay,
        stats: .init(todayCount: 5, overdueCount: 1, dueTodayCount: 2, completedTodayCount: 2),
        briefing: text("The launch checklist first; the status update after the design review."),
        tasks: [
          .init(
            id: "preview-checklist", title: text("Review the launch checklist"), status: started,
            dueDate: logicalDay, priority: 1, listID: nil, estimatedMinutes: 45,
            scheduledStart: clock(nowMinutes - 20), scheduledEnd: clock(nowMinutes + 25)),
          .init(
            id: "preview-agenda", title: text("Draft the team offsite agenda"), status: started,
            dueDate: nil, priority: 2, listID: nil, estimatedMinutes: 30),
          .init(
            id: "preview-passport", title: text("Renew passport"), status: open,
            dueDate: yesterday, priority: 1, listID: nil, estimatedMinutes: nil),
          .init(
            id: "preview-status", title: text("Send the weekly status update"), status: open,
            dueDate: logicalDay, priority: 2, listID: nil, estimatedMinutes: 30,
            scheduledStart: clock(nowMinutes + 45), scheduledEnd: clock(nowMinutes + 75)),
          .init(
            id: "preview-venue", title: text("Book the offsite venue"), status: open,
            dueDate: nil, priority: 2, listID: nil, estimatedMinutes: 20),
        ],
        habits: [
          .init(id: "preview-meditate", name: text("Meditate"), icon: "brain.head.profile", completedToday: 0, target: 1),
          .init(id: "preview-run", name: text("Morning run"), icon: "figure.run", completedToday: 1, target: 1),
          .init(id: "preview-read", name: text("Read 30 min"), icon: "book.fill", completedToday: 1, target: 1),
          .init(id: "preview-review", name: text("Review the day"), icon: "checklist", completedToday: 0, target: 1),
        ])
    }
  }
#endif
