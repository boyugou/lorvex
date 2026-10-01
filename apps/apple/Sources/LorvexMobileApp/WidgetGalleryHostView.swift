#if DEBUG
  import LorvexCore
  import LorvexWidgetKitSupport
  import LorvexWidgetViews
  import SwiftUI

  /// DEBUG-only: hosts the real WidgetKit views at their canonical sizes so the
  /// widget design can be visually QA'd in the simulator (which can't screenshot
  /// live widgets). Shown as the app root when launched with `-lorvexWidgetGallery`.
  ///
  /// Renders in-app on purpose: the rows wrap `Link`/`Button(intent:)`, which an
  /// off-screen `ImageRenderer` collapses to placeholders but the live app draws
  /// faithfully. The Today models come from the real `WidgetRenderModelBuilder`
  /// over a sample day read at 10:12, so the gallery shows what the builder
  /// makes of a running time, not hand-written rows.
  ///
  /// The gallery is taller than one screen, so `-lorvexWidgetGallerySection
  /// <section>` shows one of its sections alone: `today` (the small and medium
  /// Today families), `large`, `lock` (the Lock Screen families), or `more`
  /// (Habits and Progress). Without it every section is shown.
  struct WidgetGalleryHostView: View {
    enum Section: String, CaseIterable {
      case today, large, lock, more
    }

    /// The section named on the command line, or nil for the whole gallery.
    static var requestedSection: Section? {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-lorvexWidgetGallerySection"),
        index + 1 < arguments.count
      else { return nil }
      return Section(rawValue: arguments[index + 1])
    }

    private var sections: [Section] {
      Self.requestedSection.map { [$0] } ?? Section.allCases
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          ForEach(sections, id: \.self) { section in
            self.section(section)
          }
        }
        .padding(24)
      }
      .background(LorvexDesign.Palette.groupedBackground)
    }

    @ViewBuilder
    private func section(_ section: Section) -> some View {
      switch section {
      case .today:
        group("Today · small") {
          HStack(alignment: .top, spacing: 16) {
            cell("running", 158, 158) { LorvexWidgetView(model: Self.model(.systemSmall)) }
            cell("next", 158, 158) { LorvexWidgetView(model: Self.model(.systemSmall, at: Self.earlyClock)) }
          }
          HStack(alignment: .top, spacing: 16) {
            cell("open day", 158, 158) { LorvexWidgetView(model: Self.openDayModel(.systemSmall)) }
            cell("all done", 158, 158) { LorvexWidgetView(model: Self.emptyModel(.systemSmall)) }
          }
        }
        group("Today · medium") {
          cell("systemMedium", 338, 158) { LorvexWidgetView(model: Self.model(.systemMedium)) }
          cell("systemMedium · open day", 338, 158) {
            LorvexWidgetView(model: Self.openDayModel(.systemMedium))
          }
        }
      case .large:
        group("Today · large") {
          HStack(alignment: .top, spacing: 16) {
            cell("systemLarge", 338, 354) { LorvexWidgetView(model: Self.model(.systemLarge)) }
          }
          cell("systemLarge · open day", 338, 354) {
            LorvexWidgetView(model: Self.openDayModel(.systemLarge))
          }
        }
      case .lock:
        group("Today · Lock Screen") {
          HStack(alignment: .top, spacing: 16) {
            accessoryCell("circular", 72, 72) {
              LorvexWidgetView(model: Self.model(.accessoryCircular))
            }
            accessoryCell("circular · open day", 72, 72) {
              LorvexWidgetView(model: Self.openDayModel(.accessoryCircular))
            }
            accessoryCell("circular · ahead", 72, 72) {
              LorvexWidgetView(model: Self.model(.accessoryCircular, at: Self.earlyClock))
            }
          }
          HStack(alignment: .top, spacing: 16) {
            accessoryCell("rectangular", 170, 72) {
              LorvexWidgetView(model: Self.model(.accessoryRectangular))
            }
            accessoryCell("rectangular · open day", 170, 72) {
              LorvexWidgetView(model: Self.openDayModel(.accessoryRectangular))
            }
          }
          accessoryCell("inline", 300, 30) {
            LorvexWidgetView(model: Self.model(.accessoryInline))
          }
          accessoryCell("inline · open day", 300, 30) {
            LorvexWidgetView(model: Self.openDayModel(.accessoryInline))
          }
        }
      case .more:
        group("Habits") {
          HStack(alignment: .top, spacing: 16) {
            cell("habits · small", 158, 158) {
              HabitsWidgetView(habits: Self.sampleHabits, family: .systemSmall)
            }
          }
          cell("habits · medium", 338, 158) {
            HabitsWidgetView(habits: Self.sampleHabits, family: .systemMedium)
          }
          cell("habits · medium · overflow", 338, 158) {
            HabitsWidgetView(habits: Self.sampleHabits + Self.moreSampleHabits, family: .systemMedium)
          }
        }
        group("Progress") {
          HStack(alignment: .top, spacing: 16) {
            cell("progress · small", 158, 158) {
              ProgressWidgetView(snapshot: Self.progressSnapshot, family: .systemSmall)
            }
            accessoryCell("progress · circular", 72, 72) {
              ProgressWidgetView(snapshot: Self.progressSnapshot, family: .accessoryCircular)
            }
          }
        }
      }
    }

    // MARK: Layout chrome

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(title).font(.title3.weight(.semibold))
        content()
      }
    }

    private func cell(
      _ title: String, _ width: CGFloat, _ height: CGFloat,
      @ViewBuilder _ content: () -> some View
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        content()
          .frame(width: width, height: height, alignment: .top)
          .background(LorvexDesign.Palette.card)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
      }
    }

    private func accessoryCell(
      _ title: String, _ width: CGFloat, _ height: CGFloat,
      @ViewBuilder _ content: () -> some View
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        content()
          .frame(width: width, height: height)
          .padding(10)
          .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .environment(\.colorScheme, .dark)
      }
    }

    // MARK: Sample day

    /// The gallery's clock: 10:12, twenty-seven minutes into the first task's
    /// time.
    static let runningClock = 10 * 60 + 12
    /// Before the first task's time starts.
    static let earlyClock = 8 * 60 + 40

    static var sampleSnapshot: WidgetSnapshot {
      let day: [(String, String, String?, String?, Int?)] = [
        ("Review the Q3 planning doc", "in_progress", "09:45", "10:30", 45),
        ("Refactor the sync layer", "open", "11:00", "12:30", 90),
        ("Reply to the investor update email", "open", "14:00", "14:30", 30),
        ("Read the GRPO paper", "open", nil, nil, 40),
        ("Renew passport", "open", nil, nil, nil),
      ]
      return WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z",
        timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 5, overdueCount: 1, dueTodayCount: 3, completedTodayCount: 2),
        briefing: "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.",
        tasks: day.enumerated().map { index, row in
          .init(
            id: "task-\(index)", title: row.0, status: row.1, dueDate: nil, priority: nil,
            listID: nil, estimatedMinutes: row.4, scheduledStart: row.2, scheduledEnd: row.3)
        })
    }

    /// Today at `clock` minutes past midnight in the device zone.
    static func date(at clock: Int) -> Date {
      let calendar = Calendar.autoupdatingCurrent
      let start = calendar.startOfDay(for: Date())
      return calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: start)
        ?? start
    }

    static func model(_ family: WidgetFamilyKind, at clock: Int = runningClock) -> WidgetRenderModel {
      let entry = WidgetTimelineEntry(
        date: date(at: clock),
        state: .snapshot(sampleSnapshot, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: date(at: clock).addingTimeInterval(3600))
      return WidgetRenderModelBuilder().model(entry: entry, family: family, statusText: "Updated now")
    }

    /// A day with tasks left but none leading: nothing timed, nothing started.
    static func openDayModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
      let day: [(String, Int?)] = [
        ("Read the GRPO paper", 40),
        ("Renew passport", nil),
        ("Draft the offsite agenda", 90),
        ("Book the dentist", 10),
        ("Clean up the photo library", 30),
      ]
      let open = WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 5, overdueCount: 0, dueTodayCount: 2, completedTodayCount: 1),
        briefing: "Nothing is fixed today; the paper and the agenda are the two that matter.",
        tasks: day.enumerated().map { index, row in
          .init(
            id: "open-\(index)", title: row.0, status: "open", dueDate: nil, priority: nil,
            listID: nil, estimatedMinutes: row.1, scheduledStart: nil, scheduledEnd: nil)
        })
      let entry = WidgetTimelineEntry(
        date: date(at: runningClock),
        state: .snapshot(open, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: date(at: runningClock).addingTimeInterval(3600))
      return WidgetRenderModelBuilder().model(entry: entry, family: family, statusText: "Updated now")
    }

    static func emptyModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
      let empty = WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0, completedTodayCount: 4),
        briefing: nil, tasks: [])
      let entry = WidgetTimelineEntry(
        date: date(at: runningClock),
        state: .snapshot(empty, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: date(at: runningClock).addingTimeInterval(3600))
      return WidgetRenderModelBuilder().model(entry: entry, family: family, statusText: "Updated now")
    }

    /// Stats-only snapshot for the progress widget (2 done of 5 due today → 40%).
    static var progressSnapshot: WidgetSnapshot {
      WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: "UTC",
        stats: .init(todayCount: 3, overdueCount: 1, dueTodayCount: 3, completedTodayCount: 2),
        briefing: nil, tasks: [])
    }

    static var sampleHabits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h1", name: "Meditate", icon: "brain.head.profile", completedToday: 1, target: 1),
        .init(id: "h2", name: "Read 30 minutes", icon: "book.fill", completedToday: 0, target: 1),
        .init(id: "h3", name: "Drink water", icon: "drop.fill", completedToday: 2, target: 3),
        .init(id: "h4", name: "Morning run", icon: "figure.run", completedToday: 1, target: 1),
        .init(id: "h5", name: "Stretch", icon: "figure.mind.and.body", completedToday: 0, target: 2),
      ]
    }

    /// Three more habits, so the medium overflow cell fills both columns and
    /// shows the "+N more" footer; one name is long enough to truncate.
    static var moreSampleHabits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h6", name: "Lights out by 11 PM", icon: "moon.zzz.fill", completedToday: 0, target: 1),
        .init(id: "h7", name: "Vitamins", icon: "pills.fill", completedToday: 1, target: 1),
        .init(id: "h8", name: "Journal", icon: "text.book.closed.fill", completedToday: 0, target: 1),
      ]
    }
  }
#endif
